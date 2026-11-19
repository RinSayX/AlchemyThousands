extends SceneTree
const Database := preload("res://scripts/core/content_db.gd")
const Spec := preload("res://scripts/core/baicao_definition.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")

func _initialize() -> void:
	var report := run_analysis()
	var path := "res://test-output/p8-baicao-analysis.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Baicao analysis: ", report.ok, " ", report.get("errors", []))
	quit(0 if report.ok else 1)

static func run_analysis() -> Dictionary:
	var db := Database.new()
	if not db.load_directory().ok: return {"ok": false, "errors": ["Invalid content"]}
	var loaded := Spec.read(db)
	if not loaded.ok: return {"ok": false, "errors": [loaded.message]}
	var state := Probe.fixture(db, 9, "rush", [], [])
	state.owned_furnaces = db.get_ids("furnaces")
	state.owned_flames = db.get_ids("flames")
	for id in db.get_ids("materials") + db.get_ids("consumables"): state.inventory[id] = 100
	var rows: Array = []
	var errors: Array = []
	for enabled in [false, true]:
		var setup := {"strategy": "rush", "furnace_id": "furnace_jiulong", "flame_id": "flame_zixiao", "consumable_id": "consumable_shuangsheng"}
		if enabled: setup["mutation_id"] = Pills.MUTATION_ID
		var preview: Dictionary = Alchemy.new(db).preview_alchemy(state, Pills.MUTATION_RECIPE, setup)
		if not preview.ok: return {"ok": false, "errors": [preview.message]}
		var snapshot: Dictionary = preview.result
		var sampled: Dictionary = Statistics.new()._sample("mutation_on" if enabled else "mutation_off", snapshot, 261119)
		var rng := Context.new(261119)
		var success := 0
		var mutants := 0
		var mutant_extra := 0
		for i in range(100000):
			var outcome := Rules.roll(snapshot, rng)
			if outcome.success: success += 1
			if outcome.mutation_id != "":
				mutants += 1
				if outcome.extra_pill: mutant_extra += 1
		var rate := Statistics.new()._frequency("mutation_given_success", snapshot.mutation_chance, mutants, success)
		var combined := Statistics.new()._frequency("extra_given_mutation", snapshot.extra_pill_chance, mutant_extra, mutants) if enabled else {"passed": mutant_extra == 0}
		rows.append({"enabled": enabled, "samples": 100000, "seed": 261119, "success": success, "mutants": mutants, "mutant_extra": mutant_extra, "mutation_check": rate, "combined_check": combined, "probability": sampled})
		if not sampled.passed or not rate.passed or not combined.passed: errors.append("Probability mismatch: " + str(enabled))
	var costs: Array = []
	for worlds in [[], ["world_kucao", "world_yiji"], ["world_yiji", "world_jinhuo"]]:
		var fixture := Probe.fixture(db, 10, "stable", [], worlds)
		var total := 0.0
		for id in db.get_item(Pills.MUTATION_RECIPE).materials:
			var basis := Probe.unit_basis(db, fixture, id)
			total += basis.stones * db.get_item(Pills.MUTATION_RECIPE).materials[id] * loaded.result.definition.ending.study_material_multiplier
		costs.append({"worlds": worlds, "study_material_value": total, "study_research": loaded.result.definition.ending.study_research_cost, "certify_research": loaded.result.definition.ending.research_cost})
	return {"ok": errors.is_empty(), "errors": errors, "engine": Context.ENGINE_VERSION, "definition_sha256": FileAccess.get_sha256(Spec.PATH), "groups": rows, "costs": costs, "scope": "Two on/off profiles each sampled twice at 100000 using production preview/shared sampler, conditional frequency bounds, deterministic study costs. No play-time or full policy optimality claim."}
