extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tools/balance/campaign_route.gd")
const Experiment := preload("res://tools/balance/experiment.gd")
const Run := preload("res://scripts/core/progression_state.gd")
const Context := preload("res://scripts/core/rng_context.gd")
var _check: Callable


func run(check: Callable) -> bool:
	_check = check
	var db := Database.new()
	_ok(db.load_directory().ok, "Production content loads without balance overrides")
	var original := Experiment.fingerprint()
	var state := Probe.fixture(db, 1, "stable", [], [])
	var before := state.duplicate(true)
	var base := Probe.analyze(db, state, "recipe_juling", "stable", "common", 4096, 8181)
	_ok(base.ok and is_equal_approx(base.expected_net, 15.784), "Expected net uses four unit-rounded sale prices, failure residue and paid inputs")
	_ok(base.input_cost == 14 and base.success_probability == 0.9, "Baseline input cost and stable success match the existing game")
	_ok(base == Probe.analyze(db, state, "recipe_juling", "stable", "common", 4096, 8181), "Same seed exactly replays the complete sampled cashflow")
	_ok(state == before, "Stage analysis never mutates the supplied state or RNG")
	_ok(base.mean_within_bound and base.net_p10 <= base.net_p50 and base.net_p50 <= base.net_p90, "Bounded sample mean and ordered profit quantiles are reported")
	var quality_count := 0
	for count in base.conditional_quality_counts.values(): quality_count += count
	_ok(is_equal_approx(float(quality_count) / base.samples, base.observed_success), "Conditional quality counts only count successful furnaces")
	var impossible := Probe.analyze(db, state, "recipe_juling", "stable", "legendary", 32, 9)
	_ok(impossible.eligible_probability == 0 and impossible.expected_attempts_for_exam_pill == null and impossible.no_exam_pill_after_8 == 1, "Zero-probability qualities use null waiting time, never division by zero")
	var rare := Probe.unit_basis(db, state, "herb_lingzhi")
	_ok(rare.stones == 10 and rare.outings == 1, "Unbuyable rare materials use deterministic acquisition cost instead of zero buy_price")
	state.world_modifiers = ["world_kucao", "world_yiji"]
	var changed := Probe.unit_basis(db, state, "herb_lingzhi")
	_ok(changed.stones == 5 and changed.outings == 0.5, "World bonus changes deterministic source yield and amortized cost")
	_ok(Probe.unit_basis(db, state, "herb_qinghua").stones == 8, "Herb-price inflation rounds each unit upward")
	var recycle_state := Probe.fixture(db, 3, "recycle", [], [])
	var recycle := Probe.analyze(db, recycle_state, "recipe_zhuji", "recycle", "good", 64, 10)
	_ok(recycle.input_cost == 50 and recycle.failure_material_value == 14, "Recovery includes consumed jade and floors refunds per material")
	_ok(recycle.rare_outings_per_attempt == 1, "One rare material has zero refund at fifty percent; no fictitious half material")
	_ok(Probe.percentile([1, 2, 9, 10], 0.5) == 2 and Probe.percentile([1, 2, 9, 10], 0.9) == 10, "Quantiles use documented nearest-rank convention")
	var definitions := Experiment.scenarios(db)
	_ok(definitions.size() == 21, "Matrix contains first life, nine inheritances, ten compatible worlds and one dual loadout")
	var unique: Array = []
	var valid := true
	for scenario in definitions:
		valid = valid and scenario.id not in unique
		unique.append(scenario.id)
		if scenario.start_run == 1:
			valid = valid and scenario.worlds.is_empty() and scenario.loadout.is_empty()
		else:
			var opportunity := false
			valid = valid and scenario.worlds.size() == 2
			for id in scenario.worlds:
				var item: Dictionary = db.get_item(id)
				opportunity = opportunity or item.opportunity
				for other in scenario.worlds: valid = valid and other not in item.exclusive_with
			valid = valid and opportunity
	_ok(valid, "Every controlled later-life scenario is unique and has a compatible opportunity pair")
	var dual := Route.new(db).run(73001, "stable", ["heritage_baicao", "heritage_huishou"], ["world_dansheng", "world_huoling"], 1)
	_ok(dual.run_number == 3 and dual.status == "completed", "Dual-slot experiments start in a third-life fixture rather than a second life")
	var first_route := Route.new(db)
	var first := first_route.run(73001, "stable", [], [], 3)
	_ok(first.status == "completed" and first.rank == 3, "Natural-exam route completes first three promotions using only transactions")
	_ok(Run.new(db).validate(first_route.state).ok, "Campaign output passes production progression-state validation")
	_ok(first.cash_reconciles and first.cash_end == 200 + first.earned - first.spent and first.min_cash >= 0, "Campaign cash ledger reconciles and never goes negative")
	_ok(first == Route.new(db).run(73001, "stable", [], [], 3), "Campaign replay includes identical per-stage, equipment and income records")
	var by_recipe := 0
	for count in first.by_recipe.values(): by_recipe += count
	_ok(by_recipe == first.furnaces and first.stages.size() == 3, "Recipe and promotion metrics reconcile with total furnace count")
	_ok(first.upgrades.size() == 2 and first.upgrades[0].item == "furnace_qingmu", "Equipment and flame upgrades are actually acquired and recorded")
	var world_start: Dictionary = Context.new(73001).snapshot().streams.world
	_ok(first_route.state.rng_states.streams.world == world_start, "Controlled campaign never rerolls its assigned world rules")
	for style in ["rush", "recycle", "research"]:
		var route := Route.new(db)
		var result := route.run(73001, style, [], [], 3)
		_ok(result.status == "completed" and result.cash_reconciles and Run.new(db).validate(route.state).ok, style + " policy acquires costs and completes early promotions")
		if style == "recycle": _ok(result.ledger.consumables < 0, "Recovery policy really pays for consumables rather than receiving free jade")
		if style == "research": _ok(result.studies == 3, "Research control uses actual deterministic study transactions")
	var capped := Route.new(db).run(1, "stable", [], [], 10, 8, 1)
	_ok(capped.status == "budget_exhausted" and capped.status != "resource_deadlock", "Simulation cap is explicitly separated from a proven resource deadlock")
	for style in Probe.STYLES:
		var stress := Route.new(db).recovery_probe(73001, style, ["heritage_yuanqi"], ["world_kucao", "world_yiji"])
		_ok(stress.status == "recovered" and stress.cash_start == 0 and stress.cash_end >= stress.required_cash and stress.cash_reconciles, style + " recovers from empty inventory and zero cash under inflated prices")
	var free_source := Experiment.free_source_probe(db, 10)
	_ok(free_source.ok and free_source.cash == 70 and free_source.actions == 10 and free_source.furnaces == 0, "Free mineral cash loop is measured through real entry/reward/sale transactions")
	var summary := Experiment.summarize([first, capped])
	_ok(summary.runs == 2 and summary.completed == 1 and summary.statuses.budget_exhausted == 1, "Aggregates retain incomplete runs rather than silently selecting only winners")
	_ok(original == Experiment.fingerprint(), "No economic experiment modifies content or production service files")
	return true


func _ok(condition: bool, message: String) -> void:
	_check.call(condition, "P8 analysis: " + message)
