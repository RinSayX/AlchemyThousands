extends RefCounted
## Paired experiments over a frozen content snapshot, never live edits.
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tools/balance/campaign_route.gd")
const Experiment := preload("res://tools/balance/experiment.gd")
const Growth := preload("res://scripts/services/progression_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const SNAPSHOT := "res://tests/fixtures/p8_v1_content.json"
const VARIANTS := ["baseline", "talent_only", "furnace_only", "combined"]
const SCENARIOS := ["first", "world_huoling+world_dansheng", "world_kucao+world_yiji", "world_yiji+world_jinhuo", "heritage_jizhuan", "dual_baicao_huishou"]


static func documents(variant: String) -> Dictionary:
	if variant not in VARIANTS: return {}
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	if not source is Dictionary or not source.get("documents") is Dictionary: return {}
	var docs: Dictionary = source.documents.duplicate(true)
	if variant in ["talent_only", "combined"]:
		for item in docs.talents.items:
			if item.style == "rush":
				item.success_bonus = 0
				item.description = "选择冲击极品时，向极品转移%d点品质权重；不再额外降低成功率，冲品策略本身仍有风险。" % int(item.legendary_transfer)
	if variant in ["furnace_only", "combined"]:
		for item in docs.furnaces.items:
			if item.id == "furnace_chiyan":
				item.success_bonus = 0.03
				item.description = "炼制火属性丹方时，成功率增加3个百分点，向上品转移8点品质权重。"
	return docs


static func database(variant: String) -> RefCounted:
	var db := Database.new()
	var loaded := db.load_documents(documents(variant))
	return db if loaded.ok else null


static func run(seeds: int, samples: int, progress: Callable = Callable()) -> Dictionary:
	var inputs := _inputs()
	var live_before := _live_data()
	var runs: Array = []
	var summaries: Array = []
	var probes: Array = []
	var stress: Array = []
	var errors: Array = []
	var content_hashes: Dictionary = {}
	var cases: Array[Dictionary] = []
	for scenario in Experiment.scenarios(database("baseline")):
		if scenario.id in SCENARIOS: cases.append(scenario)
	for variant in VARIANTS:
		var db: RefCounted = database(variant)
		if db == null: return {"ok": false, "errors": ["Candidate content invalid: " + variant]}
		content_hashes[variant] = JSON.stringify(documents(variant)).sha256_text()
		var policies := ["rush", "recycle", "recycle_smart"] if variant in ["baseline", "combined"] else ["rush"]
		for scenario in cases:
			for style in policies:
				var group: Array = []
				for index in range(seeds):
					var row: Dictionary = Route.new(db).run(73001 + index, style, scenario.loadout, scenario.worlds)
					row.merge({"variant": variant, "scenario": scenario.id})
					runs.append(row)
					group.append(row)
					if row.status != "completed" or not row.cash_reconciles: errors.append("Campaign failed: " + variant + "/" + scenario.id + "/" + style)
					var recovery: Dictionary = Route.new(db).recovery_probe(73001 + index, style, scenario.loadout, scenario.worlds)
					recovery.merge({"variant": variant, "scenario": scenario.id})
					stress.append(recovery)
					if recovery.status != "recovered" or not recovery.cash_reconciles: errors.append("Recovery failed: " + variant + "/" + scenario.id + "/" + style)
				var summary := Experiment.summarize(group)
				summary.merge({"variant": variant, "scenario": scenario.id, "style": style})
				summaries.append(summary)
				for target in range(1, 11):
					var state := Probe.fixture(db, target, style, scenario.loadout, scenario.worlds)
					var exam: Dictionary = Growth.new(db).rank_definition(target)
					var row := Probe.analyze(db, state, exam.exam_recipe_id, style, exam.min_quality, samples, 91000 + target)
					row.merge({"variant": variant, "scenario": scenario.id, "target": target})
					probes.append(row)
					if not row.ok or not row.get("mean_within_bound", false) or not row.get("frequencies_within_bounds", false): errors.append("Probe failed: " + variant + "/" + scenario.id + "/" + style)
			if progress.is_valid(): progress.call("Candidate " + variant + "/" + scenario.id + ": " + str(runs.size()) + " campaigns")
	var after := _inputs()
	if inputs != after: errors.append("Source or live content changed during experiment")
	if live_before != _live_data(): errors.append("Live content changed during isolated experiment")
	return {"report_schema": 1, "engine": Context.ENGINE_VERSION, "ok": errors.is_empty(), "errors": errors, "input_hashes": inputs, "inputs_unchanged": inputs == after, "observed_live_data_hashes": live_before, "live_data_unchanged": live_before == _live_data(), "baseline_commit": "638f4c5", "effective_content_hashes": content_hashes, "seed_start": "73001", "seed_count": seeds, "samples_per_probe": samples, "variants": VARIANTS, "scenario_definitions": cases, "campaigns": runs, "summaries": summaries, "stage_probes": probes, "bankruptcy_recovery": stress, "assumptions": ["Frozen full P8 v1 content; variants only change stated talent and furnace fields plus descriptions", "Same six scenarios, eight shared campaign seeds by default; not all worlds/inheritances", "Unchanged natural-exam cap 8; unchanged prices, experience, forage and study gates", "Smart jade uses marginal paid acquisition value, including floor refunds and deterministic rare sources", "No actual permanent unlock journey or UI timing is simulated", "Original v1 reports remain historical artifacts, not regenerated in place"]}


static func _inputs() -> Dictionary:
	var result := Experiment.fingerprint()
	for key in result.keys():
		if key.begins_with("data/"): result.erase(key)
	result["tests/fixtures/p8_v1_content.json"] = FileAccess.get_sha256(SNAPSHOT)
	result["tools/balance_candidates.gd"] = FileAccess.get_sha256("res://tools/balance_candidates.gd")
	return result


static func _live_data() -> Dictionary:
	var hashes: Dictionary = {}
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"): hashes["data/" + file] = FileAccess.get_sha256("res://data/" + file)
	return hashes
