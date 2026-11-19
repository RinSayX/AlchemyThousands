extends SceneTree
## Recurring one-furnace economics; separate from full-run pacing or play time.
const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const WORLDS := [[], ["world_kucao", "world_yiji"], ["world_yiji", "world_jinhuo"]]
const BUILDS := [
	{"style": "stable", "strategy": "stable", "recipe": "recipe_juling", "furnace": "furnace_qingmu", "flame": "flame_earth", "pair": ["consumable_wendan", "consumable_juling"]},
	{"style": "rush", "strategy": "rush", "recipe": "recipe_leijie", "furnace": "furnace_jiulong", "flame": "flame_zixiao", "pair": ["consumable_jiuzhuan", "consumable_shuangsheng"]},
	{"style": "recycle", "strategy": "stable", "recipe": "recipe_bingxin", "furnace": "furnace_xuanbing", "flame": "flame_hansui", "pair": ["consumable_bingpo", "consumable_yanjiu"]}
]

func _initialize() -> void:
	var report := run_analysis()
	var path := "res://test-output/p8-dual-analysis.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write dual consumable analysis")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Dual consumable analysis: ", report.ok, " groups=", report.get("comparisons", []).size(), " sampled=", report.get("sampled", []).size(), " errors=", report.get("errors", []))
	quit(0 if report.ok else 1)

static func run_analysis() -> Dictionary:
	var db := Database.new()
	if not db.load_directory().ok: return {"ok": false, "errors": ["Invalid content"]}
	var service := Alchemy.new(db)
	var errors: Array = []
	var comparisons: Array = []
	var sampled: Array = []
	var pairs: Array = []
	var ids: Array = db.get_ids("consumables")
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			if db.get_item(ids[a]).effect_category != db.get_item(ids[b]).effect_category: pairs.append([ids[a], ids[b]])
	for build in BUILDS:
		for worlds in WORLDS:
			var state := Probe.fixture(db, 10, build.style, [], worlds)
			state.owned_furnaces = db.get_ids("furnaces")
			state.owned_flames = db.get_ids("flames")
			for id in db.get_ids("materials") + ids: state.inventory[id] = 100
			var setup := {"strategy": build.strategy, "furnace_id": build.furnace, "flame_id": build.flame}
			var base := _expected(db, state, build.recipe, _view(service, state, build.recipe, setup, []))
			for pair in pairs:
				var one := _expected(db, state, build.recipe, _view(service, state, build.recipe, setup, [pair[0]]))
				var two := _expected(db, state, build.recipe, _view(service, state, build.recipe, setup, [pair[1]]))
				var both := _expected(db, state, build.recipe, _view(service, state, build.recipe, setup, pair))
				comparisons.append({"style": build.style, "worlds": worlds, "recipe": build.recipe, "pair": pair, "none": base, "first": one, "second": two, "both": both, "net_delta_vs_none": both.net - base.net, "net_delta_vs_best_single": both.net - maxf(one.net, two.net), "base_research_delta": both.base_research - base.base_research})
			var group: Array = []
			var probes: Array = [[], [build.pair[0]], [build.pair[1]], build.pair]
			for selected in probes:
				var chosen := setup.duplicate(true)
				chosen["consumable_ids"] = selected
				var row := Probe.analyze(db, state, build.recipe, build.style, "good", 100000, 619000 + sampled.size(), chosen)
				group.append(row)
				if not row.ok or not row.mean_within_bound or not row.frequencies_within_bounds: errors.append("Economic sample failed: " + build.style)
				if row.ok and not is_equal_approx(row.expected_net, _expected(db, state, build.recipe, _view(service, state, build.recipe, setup, selected)).net): errors.append("Analytic ledger mismatch: " + build.style)
			var view := _view(service, state, build.recipe, setup, build.pair)
			var probability: Dictionary = Statistics.new()._sample(build.style, view, 629000 + sampled.size())
			if not probability.passed: errors.append("Probability sample failed: " + build.style)
			sampled.append({"style": build.style, "worlds": worlds, "pair": build.pair, "economy": group, "probability": probability})
	var hashes: Dictionary = {}
	for path in ["res://data/consumables.json", "res://data/recipes.json", "res://data/furnaces.json", "res://data/flames.json", "res://scripts/core/alchemy_rules.gd", "res://scripts/services/alchemy_service.gd"]: hashes[path] = FileAccess.get_sha256(path)
	return {"ok": errors.is_empty(), "errors": errors, "engine": Context.ENGINE_VERSION, "baseline": "8ca605b", "input_sha256": hashes, "valid_pairs": pairs.size(), "samples_per_probe": 100000, "total_shared_samples": 4500000, "comparisons": comparisons, "sampled": sampled, "scope": "225 analytic pair/build/world comparisons; 36 economic and 9 probability probes at 100000 shared outcomes each. Recurring material/consumable cost and liquid sale/refund value only; no equipment investment, research cash conversion, full policy optimum or human play time."}

static func _view(service: RefCounted, state: Dictionary, recipe: String, setup: Dictionary, ids: Array) -> Dictionary:
	var selected := setup.duplicate(true)
	selected["consumable_ids"] = ids
	return service.preview_alchemy(state, recipe, selected).result

static func _expected(db: RefCounted, state: Dictionary, recipe: String, view: Dictionary) -> Dictionary:
	var cost := 0.0
	var refund := 0.0
	for id in view.materials:
		var basis := Probe.unit_basis(db, state, id)
		cost += basis.stones * view.materials[id]
		refund += basis.stones * view.failure_returns.get(id, 0)
	for id in view.consumables: cost += db.get_item(id).unlock.price
	var sale := 0.0
	for quality in view.quality_probabilities: sale += view.quality_probabilities[quality] * Probe.price(db, recipe, quality)
	var residue: int = preload("res://scripts/core/lineage_rules.gd").sell_price(db, state, "material_danzha", db.get_item("material_danzha").sell_price)
	var net: float = view.success_rate * sale * (1 + view.extra_pill_chance) + (1 - view.success_rate) * (residue + refund) - cost
	return {"net": net, "cost": cost, "refund_on_failure": refund, "base_research": view.research_rewards.base, "success": view.success_rate, "extra": view.extra_pill_chance, "quality": view.quality_probabilities}
