extends RefCounted
## Proposed content over the immutable pre-expansion baseline, with pure probes.
const Candidates := preload("res://tools/balance/candidate_experiment.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const PROPOSAL := "res://tests/fixtures/p8_equipment_proposal.json"


static func proposal() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPOSAL))
	return data if data is Dictionary else {}


static func documents() -> Dictionary:
	var docs := Candidates.documents("combined")
	for category in proposal():
		docs[category].items.append_array(proposal()[category])
	return docs


static func database() -> RefCounted:
	var db := Database.new()
	return db if db.load_documents(documents()).ok else null


static func profiles() -> Array[Dictionary]:
	return [
		{"name": "qinglian_wood", "rank": 3, "recipe": "recipe_zhuji", "strategy": "stable", "furnace": "furnace_qingmu", "flame": "flame_qinglian"},
		{"name": "ice_recovery", "rank": 4, "recipe": "recipe_pojing", "strategy": "stable", "furnace": "furnace_xuanbing", "flame": "flame_hansui"},
		{"name": "thunder_mid_rush", "rank": 6, "recipe": "recipe_xuanyuan", "strategy": "rush", "furnace": "furnace_zixiao", "flame": "flame_zixiao"},
		{"name": "thunder_late_rush", "rank": 9, "recipe": "recipe_taichu", "strategy": "rush", "furnace": "furnace_zixiao", "flame": "flame_zixiao"},
		{"name": "dragon_rush", "rank": 9, "recipe": "recipe_taichu", "strategy": "rush", "furnace": "furnace_jiulong", "flame": "flame_zixiao"},
		{"name": "dragon_stable", "rank": 9, "recipe": "recipe_taichu", "strategy": "stable", "furnace": "furnace_jiulong", "flame": "flame_earth"},
		{"name": "dragon_forbidden_fire", "rank": 9, "recipe": "recipe_taichu", "strategy": "rush", "furnace": "furnace_jiulong", "flame": "flame_normal", "worlds": ["world_yiji", "world_jinhuo"]},
		{"name": "dragon_inactive_wood", "rank": 9, "recipe": "recipe_juling", "strategy": "normal", "furnace": "furnace_jiulong", "flame": "flame_normal"},
		{"name": "thunder_inactive_stable", "rank": 9, "recipe": "recipe_taichu", "strategy": "stable", "furnace": "furnace_zixiao", "flame": "flame_zixiao"},
	]


static func fixture(db: RefCounted, profile: Dictionary) -> Dictionary:
	var style: String = "rush" if profile.strategy == "rush" else "stable"
	var state := Probe.fixture(db, profile.rank + 1, style, [], profile.get("worlds", []))
	# A conditioned build, not a claim that this equipment was granted at this rank.
	state.owned_furnaces = db.get_ids("furnaces")
	state.owned_flames = db.get_ids("flames")
	for item in db.get_items("materials") + db.get_items("consumables"):
		state.inventory[item.id] = 100
	return state


static func setup(profile: Dictionary) -> Dictionary:
	return {"furnace_id": profile.furnace, "flame_id": profile.flame, "strategy": profile.strategy}


static func run() -> Dictionary:
	var db: RefCounted = database()
	if db == null: return {"ok": false, "errors": ["Invalid equipment proposal"]}
	var probabilities: Array = []
	var economy: Array = []
	var errors: Array = []
	var index := 0
	for profile in profiles():
		var state := fixture(db, profile)
		var selected := setup(profile)
		var preview: Dictionary = Alchemy.new(db).preview_alchemy(state, profile.recipe, selected)
		if not preview.ok: return {"ok": false, "errors": [preview.message]}
		var sampled: Dictionary = Statistics.new()._sample(profile.name, preview.result, 160001 + index)
		probabilities.append(sampled)
		var value := Probe.analyze(db, state, profile.recipe, profile.strategy, "superior", 100000, 160001 + index, selected)
		value["profile"] = profile.name
		economy.append(value)
		if not sampled.passed or not value.mean_within_bound or not value.frequencies_within_bounds: errors.append(profile.name)
		index += 1
	return {"report_schema": 1, "engine": Context.ENGINE_VERSION, "ok": errors.is_empty(), "errors": errors, "counts": db.get_counts(), "baseline": "638f4c5 + combined tuning", "proposal_sha256": FileAccess.get_sha256(PROPOSAL), "effective_content_sha256": JSON.stringify(documents()).sha256_text(), "samples_per_profile": 100000, "profiles": profiles(), "probability": probabilities, "economy": economy, "scope": "Conditioned production preview and sampler; sunk acquisition costs excluded; real acquisition is separately tested via public session commands"}
