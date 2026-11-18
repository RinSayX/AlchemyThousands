extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Validator := preload("res://scripts/core/content_validator.gd")
const State := preload("res://scripts/core/progression_state.gd")
const Progression := preload("res://scripts/services/progression_service.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Route := preload("res://tests/helpers/progression_route.gd")
var db := Database.new()
var progression: Progression
var states: State
var _check: Callable


func run(check: Callable) -> bool:
	_check = check
	if not db.load_directory().ok:
		return false
	progression = Progression.new(db)
	states = State.new(db)
	_content()
	_transactions()
	_talents()
	_talent_distribution()
	_route()
	return true


func fixture(rank_value: int) -> Dictionary:
	var state: Dictionary = states.create_state(1).result.state
	state.rank = rank_value
	state.exp = 2000
	state.research_points = 500
	for material in db.get_items("materials"):
		state.inventory[material.id] = 100
	for recipe in db.get_items("recipes"):
		if recipe.unlock.type == "rank" and recipe.unlock.required_rank <= rank_value and recipe.id not in state.unlocked_recipes:
			state.unlocked_recipes.append(recipe.id)
	for group in [3, 6, 9]:
		if group < rank_value:
			state.talent_choices.append("talent_stable_%d" % group)
	state.pending_talent_rank = rank_value if rank_value in [3, 6, 9] else 0
	return state


func _reject(state: Dictionary, operation: Callable, code: String, label: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = operation.call()
	_check.call(not result.ok and result.error_code == code and before == var_to_bytes(state), "P6 atomic: " + label)


func _content() -> void:
	var documents: Dictionary = {}
	for category in Validator.CATEGORIES:
		documents[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % category))
	var cases := [
		["ranks", ["items", 1, "rank_index"], 0],
		["ranks", ["items", 1, "rank_index"], "one"],
		["ranks", ["items", 1, "rank_index"], 1.5],
		["ranks", ["items", 1, "exp_required"], -1],
		["ranks", ["items", 1, "exp_required"], []],
		["ranks", ["items", 1, "exam_recipe_id"], "recipe_missing"],
		["ranks", ["items", 1, "exam_recipe_id"], "recipe_taichu"],
		["ranks", ["items", 1, "required_quest_id"], "quest_missing"],
		["ranks", ["items", 1, "required_flame"], "flame_missing"],
		["ranks", ["items", 1, "min_quality"], "mythic"],
		["ranks", ["items", 1, "research_cost"], 0],
		["ranks", ["items", 1, "quantity"], 0],
		["ranks", ["items", 1, "unlock"], {"type": "initial"}],
		["talents", ["items", 0, "choice_rank"], 4],
		["talents", ["items", 0, "choice_rank"], true],
		["talents", ["items", 0, "style"], "script"],
		["talents", ["items", 0, "success_bonus"], INF],
		["talents", ["items", 0, "research_discount"], 1],
		["talents", ["items", 0, "substitution_ratio"], -1],
		["talents", ["items", 0, "unlock", "required_rank"], 1],
		["talents", ["items", 1, "style"], "stable"],
	]
	for i in range(cases.size()):
		var data := documents.duplicate(true)
		var current: Variant = data[cases[i][0]]
		for j in range(cases[i][1].size() - 1):
			current = current[cases[i][1][j]]
		current[cases[i][1][-1]] = cases[i][2]
		var loaded := db.load_documents(data)
		_check.call(not loaded.ok and not loaded.errors.is_empty() and db.get_counts().ranks == 11, "P6 content rejects malformed rank/talent %d" % i)
	var missing := documents.duplicate(true)
	missing.ranks.items.remove_at(5)
	_check.call(not db.load_documents(missing).ok, "P6: Missing intermediate rank is rejected")
	var order := documents.duplicate(true)
	order.ranks.items[5].exp_required = 1
	_check.call(not db.load_documents(order).ok, "P6: Decreasing experience gates are rejected")
	_check.call(db.get_item("rank_10").rank_index is int and db.get_item("talent_research_3").choice_rank is int, "P6: Progression JSON numeric enums normalize without float/int key mismatches")


func _transactions() -> void:
	var initial: Dictionary = states.create_state(1).result.state
	var before := var_to_bytes(initial)
	progression.preview(initial)
	progression.preview_study(initial)
	progression.collection(initial)
	_check.call(before == var_to_bytes(initial), "P6: Growth, research and collection previews never mutate state or RNG")
	_reject(initial, func() -> Dictionary: return progression.promote(initial, 1, "early"), "PROMOTION_REQUIREMENTS", "Experience, achievement, quest and pill requirements are checked")
	_reject(initial, func() -> Dictionary: return progression.promote(initial, 2, "skip"), "INVALID_PROMOTION", "Cannot skip a rank")
	var state := fixture(1)
	var rng_before: Dictionary = state.rng_states.duplicate(true)
	var view := progression.preview_study(state)
	var studied := progression.study_exam(state, 2, "study")
	_check.call(studied.ok and state.research_points == 500 - view.result.research_cost and state.research_crafts == 1 and state.statistics.alchemy_attempts == 0 and state.exp == 2020, "P6: Deterministic study consumes points/materials and grants pill/experience with separate craft statistics")
	_check.call(state.rng_states == rng_before and state.alchemy_discoveries.has(Pills.key("recipe_ningshen", "common")), "P6: Study records discovered quality without touching any RNG stream")
	_reject(state, func() -> Dictionary: return progression.study_exam(state, 2, "study"), "ACTION_DUPLICATE", "Study replay cannot grant twice")
	_check.call(progression.preview(state).result.can_promote, "P6: Actual research result satisfies the achievement and exam")
	var promoted := progression.promote(state, 2, "promote")
	_check.call(promoted.ok and state.rank == 2 and state.unlocked_recipes.has("recipe_zhuji") and not state.pills.has(Pills.key("recipe_ningshen", "common")) and state.rng_states == rng_before, "P6: Promotion consumes exam pill and unlocks the next rank recipe atomically")
	_reject(state, func() -> Dictionary: return progression.promote(state, 2, "promote"), "ACTION_DUPLICATE", "Promotion action replay")
	_reject(state, func() -> Dictionary: return progression.promote(state, 2, "promote-again"), "INVALID_PROMOTION", "Fresh action cannot repeat the same certification")
	_reject(state, func() -> Dictionary: return progression.study_exam(state, 2, "stale"), "EXAM_CHANGED", "Stale study button cannot run an old exam")
	for kind in ["points", "materials", "recipe", "pill_overflow", "exp_overflow", "action_overflow", "craft_overflow"]:
		state = fixture(1)
		if kind == "points": state.research_points = 0
		if kind == "materials": state.inventory.clear()
		if kind == "recipe": state.unlocked_recipes.erase("recipe_ningshen")
		if kind == "pill_overflow": state.pills[Pills.key("recipe_ningshen", "common")] = Pills.create("recipe_ningshen", "common", 2147483647)
		if kind == "exp_overflow": state.exp = 2147483647
		if kind == "action_overflow": state.action_count = 2147483647
		if kind == "craft_overflow": state.research_crafts = 2147483647
		_reject(state, func() -> Dictionary: return progression.study_exam(state, 2, "failed-study"), "AMOUNT_OVERFLOW" if kind.ends_with("overflow") else "STUDY_REQUIREMENTS", "Study rejects " + kind)
	state = fixture(1)
	Inventory.new(db).add_pill(state, "recipe_ningshen", "common", 1, "pill-fixture")
	_check.call(not progression.preview(state).result.can_promote, "P6: Merely owning an injected exam pill does not satisfy its discovery achievement")
	state = fixture(5)
	progression.study_exam(state, 6, "prepare")
	_reject(state, func() -> Dictionary: return progression.promote(state, 6, "no-flame"), "PROMOTION_REQUIREMENTS", "Sixth-rank milestone requires a flame with a deterministic P5 acquisition path")
	state = fixture(1)
	progression.study_exam(state, 2, "prepare")
	var collection_before := progression.collection(state)
	progression.promote(state, 2, "pass")
	_check.call(progression.collection(state).result.discovered == collection_before.result.discovered, "P6: Consuming the exam pill preserves the discovered collection entry")


func _talents() -> void:
	var state := fixture(3)
	var alchemy := Alchemy.new(db)
	var before := alchemy.preview_alchemy(state, "recipe_zhuji", {"strategy": "stable"})
	_reject(state, func() -> Dictionary: return progression.choose_talent(state, "talent_stable_9", "future"), "TALENT_UNAVAILABLE", "Cannot choose a later milestone talent")
	_check.call(progression.preview(state).result.talents.size() == 3 and progression.choose_talent(state, "talent_stable_3", "choose").ok and state.pending_talent_rank == 0, "P6: Three choices are offered once at third rank")
	var after := alchemy.preview_alchemy(state, "recipe_zhuji", {"strategy": "stable"})
	_check.call(after.ok and is_equal_approx(after.result.raw_success_rate - before.result.raw_success_rate, 0.03) and is_equal_approx(after.result.material_refund_rate, 0.1), "P6: Stable talent applies its disclosed success and refund only to stable strategy")
	_check.call(alchemy.preview_alchemy(state, "recipe_zhuji", {"strategy": "normal"}).result.success_breakdown.get("talent", 0.0) == 0, "P6: Inactive talent strategy grants no hidden bonus")
	_reject(state, func() -> Dictionary: return progression.choose_talent(state, "talent_rush_3", "rechoose"), "TALENT_UNAVAILABLE", "Cannot reselect the milestone with a fresh action ID")
	state = fixture(3)
	before = alchemy.preview_alchemy(state, "recipe_zhuji", {"strategy": "rush"})
	progression.choose_talent(state, "talent_rush_3", "choose")
	after = alchemy.preview_alchemy(state, "recipe_zhuji", {"strategy": "rush"})
	_check.call(is_equal_approx(after.result.raw_success_rate - before.result.raw_success_rate, -0.03) and after.result.quality_weights.legendary == before.result.quality_weights.legendary + 3, "P6: Rush talent trades success for exactly the stated legendary weight")
	state = fixture(3)
	state.inventory.erase("herb_lingzhi")
	before = progression.preview_study(state)
	progression.choose_talent(state, "talent_research_3", "choose")
	after = progression.preview_study(state)
	_check.call(after.result.research_cost == 20 and before.result.research_cost == 24 and after.result.substituted.herb_lingzhi == 1 and after.result.cost_items.herb_lingcao == 3 and not after.result.cost_items.has("herb_lingzhi"), "P6: Research talent changes study cost and substitutes missing rare materials with ordinary herbs")
	var herbs: int = state.inventory.herb_lingcao
	_check.call(progression.study_exam(state, 4, "substitute").ok and state.inventory.herb_lingcao == herbs - 3 and state.pills.has(Pills.key("recipe_tongmai", "good")), "P6: Substitution preview and actual deterministic craft use identical costs")
	state = fixture(9)
	state.talent_choices = ["talent_research_3", "talent_research_6"]
	progression.choose_talent(state, "talent_research_9", "choose")
	_check.call(progression.preview_study(state).result.research_cost == 25 and state.talent_choices.size() == 3, "P6: Three research milestones stack to the explicit 75 percent cap")
	state = fixture(3)
	state.pending_talent_rank = 0
	_check.call(not states.validate(state).ok, "P6: Inconsistent pending talent save state is rejected")
	state = fixture(3)
	state.talent_choices = ["talent_stable_3", "talent_rush_3"]
	_check.call(not alchemy.validate_state(state).ok, "P6: Duplicate milestone choices cannot reach alchemy calculations")


func _talent_distribution() -> void:
	for style in ["stable", "rush"]:
		var state := fixture(3)
		progression.choose_talent(state, "talent_%s_3" % style, "choose-statistics")
		var snapshot: Dictionary = Alchemy.new(db).preview_alchemy(state, "recipe_zhuji", {"strategy": style}).result
		var before := var_to_bytes(state)
		var rng := Context.new(20261119)
		var successes := 0
		var qualities := {"common": 0, "good": 0, "superior": 0, "legendary": 0}
		for i in range(100000):
			var outcome := Rules.roll(snapshot, rng)
			if outcome.success:
				successes += 1
				qualities[outcome.quality] += 1
		var valid: bool = absf(successes / 100000.0 - snapshot.success_rate) <= 0.01 and before == var_to_bytes(state)
		for quality in qualities:
			var expected: float = snapshot.quality_probabilities[quality]
			var actual: float = qualities[quality] / float(successes)
			valid = valid and absf(actual - expected) <= maxf(0.000001, 6 * sqrt(expected * (1 - expected) / successes))
		_check.call(valid, "P6 talent statistics: %s 100000 furnaces, success %.5f / %.5f, all conditional qualities within tolerance" % [style, successes / 100000.0, snapshot.success_rate])


func _route() -> void:
	for style in ["research", "stable", "rush"]:
		var report := Route.new().run(style)
		_check.call(report.ok, "P6 full route: fresh run to grandmaster using " + style)
		if not report.ok:
			printerr(report.error)
			continue
		var session: RefCounted = report.session
		var state: Dictionary = session.state()
		_check.call(state.rank == 10 and state.ending.id == "ending_grandmaster" and state.talent_choices.size() == 3 and state.research_crafts == 10 and states.validate(state).ok, "P6 full route: valid ending and three milestone choices for " + style)
		_check.call(state.owned_flames.has("flame_earth") and state.resource_stats.quests_completed >= 1 and state.alchemy_discoveries.has(Pills.key("recipe_taichu", "superior")), "P6 full route: real quest/flame and final pill achievement for " + style)
		print("P6 route metrics: ", style, " furnaces=", report.furnaces, " actions=", state.action_count)
		_reject(state, func() -> Dictionary: return progression.promote(state, 11, "after-ending"), "INVALID_PROMOTION", "Ending cannot be certified twice")
		var ending_before: Dictionary = state.ending.duplicate(true)
		var done: Dictionary = session.forage_status()
		if done.result.can_rest: session.rest()
		if not session.preview("recipe_juling", {}).result.can_execute: session.forage()
		_check.call(session.begin_brew("recipe_juling", {}).ok and session.finish_brew().ok and session.state().ending == ending_before, "P6: Collection play remains available after ending without rewriting final statistics")
