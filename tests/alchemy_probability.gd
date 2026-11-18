extends RefCounted
## Statistical checks use exactly the sampler called by execute_alchemy.

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const SAMPLES := 100000


func run() -> Dictionary:
	var db := Database.new()
	var loaded := db.load_directory()
	if not loaded.ok:
		return {"passed": false, "errors": loaded.errors, "profiles": []}
	var service := Alchemy.new(db)
	var profiles := [
		{"name": "normal", "rank": 0, "recipe": "recipe_juling", "setup": {}},
		{"name": "stable", "rank": 1, "recipe": "recipe_juling", "setup": {"strategy": "stable", "furnace_id": "furnace_qingmu", "flame_id": "flame_earth"}},
		{"name": "rush_fire", "rank": 1, "recipe": "recipe_cuiti", "setup": {"strategy": "rush", "furnace_id": "furnace_chiyan"}},
		{"name": "recovery", "rank": 0, "recipe": "recipe_juling", "setup": {"consumable_id": "consumable_hulu"}},
		{"name": "extra_pill_fixture", "rank": 0, "recipe": "recipe_juling", "setup": {}},
	]
	var rows: Array[Dictionary] = []
	var passed := true
	for index in range(profiles.size()):
		var profile: Dictionary = profiles[index]
		var state: Dictionary = service.create_state(1).result.state
		state.rank = profile.rank
		state.owned_furnaces = db.get_ids("furnaces")
		state.owned_flames = db.get_ids("flames")
		state.unlocked_recipes = db.get_ids("recipes")
		for item in db.get_items("materials") + db.get_items("consumables"):
			state.inventory[item.id] = 100
		var preview := service.preview_alchemy(state, profile.recipe, profile.setup)
		if not preview.ok:
			return {"passed": false, "errors": [preview], "profiles": rows}
		var snapshot: Dictionary = preview.result
		# Non-shipping positive extra chance exercises the optional sampling branch.
		if profile.name == "extra_pill_fixture":
			snapshot.extra_pill_chance = 0.35
		var row := _sample(profile.name, snapshot, 89271 + index * 97)
		row["test_fixture"] = profile.name == "extra_pill_fixture"
		rows.append(row)
		passed = passed and row.passed
	return {"schema_version": 1, "engine_version": Context.ENGINE_VERSION, "passed": passed, "samples_per_profile": SAMPLES, "total_samples": SAMPLES * rows.size(), "scope": "shared outcome sampler; excludes economy, history growth and play-time balance", "profiles": rows}


func _sample(name: String, snapshot: Dictionary, seed_value: int) -> Dictionary:
	var rng := Context.new(seed_value)
	var successes := 0
	var extra := 0
	var qualities := {"common": 0, "good": 0, "superior": 0, "legendary": 0}
	for index in range(SAMPLES):
		var outcome := Rules.roll(snapshot, rng)
		if outcome.success:
			successes += 1
			qualities[outcome.quality] += 1
			if outcome.extra_pill:
				extra += 1
	var checks: Array[Dictionary] = []
	var success_actual := float(successes) / SAMPLES
	checks.append({"name": "success", "expected": snapshot.success_rate, "actual": success_actual, "tolerance": 0.01, "passed": absf(success_actual - snapshot.success_rate) <= 0.01})
	var distribution: Dictionary = {}
	for quality in Rules.QUALITIES:
		distribution[quality] = float(qualities[quality]) / maxi(successes, 1)
		checks.append(_frequency(quality, snapshot.quality_probabilities[quality], qualities[quality], successes))
	checks.append(_frequency("legendary_per_attempt", snapshot.legendary_per_attempt, qualities.legendary, SAMPLES))
	checks.append(_frequency("extra_given_success", snapshot.extra_pill_chance, extra, successes))
	var passed := successes > 0
	for check in checks:
		passed = passed and check.passed
	return {"name": name, "seed": seed_value, "samples": SAMPLES, "successes": successes, "success_expected": snapshot.success_rate, "success_actual": success_actual, "quality_counts": qualities, "quality_expected": snapshot.quality_probabilities, "quality_actual": distribution, "extra_count": extra, "extra_expected": snapshot.extra_pill_chance, "extra_actual": float(extra) / maxi(successes, 1), "checks": checks, "passed": passed}


func _frequency(name: String, probability: float, count: int, samples: int) -> Dictionary:
	var actual := float(count) / maxi(samples, 1)
	var tolerance := maxf(6.0 * sqrt(probability * (1.0 - probability) / maxi(samples, 1)), 1.0 / maxi(samples, 1))
	var passed: bool = samples > 0 and absf(actual - probability) <= tolerance
	if probability == 0:
		passed = count == 0
	elif probability == 1:
		passed = count == samples
	return {"name": name, "expected": probability, "actual": actual, "samples": samples, "count": count, "tolerance": tolerance, "passed": passed}
