extends RefCounted
## Resource transactions, no-resource recovery and exact exploration interval rules.

const Database := preload("res://scripts/core/content_db.gd")
const Validator := preload("res://scripts/core/content_validator.gd")
const State := preload("res://scripts/core/resource_state.gd")
const Quests := preload("res://scripts/services/quest_service.gd")
const Exploration := preload("res://scripts/services/exploration_service.gd")
const Forage := preload("res://scripts/services/forage_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/exploration_rules.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const MAX := 2147483647
var _check: Callable
var db := Database.new()
var resources: State
var quests: Quests
var explore: Exploration
var forage: Forage
var inventory: Inventory


func run(check: Callable) -> bool:
	_check = check
	if not db.load_directory().ok:
		return false
	resources = State.new(db)
	quests = Quests.new(db)
	explore = Exploration.new(db)
	forage = Forage.new(db)
	inventory = Inventory.new(db)
	_test_content()
	_test_quests()
	_test_exploration()
	_test_recovery()
	_test_distribution()
	return true


func _new(seed_value: int = 1) -> Dictionary:
	return resources.create_state(seed_value).result.state


func _expect_failure(state: Dictionary, operation: Callable, code: String, label: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = operation.call()
	_check.call(not result.ok and result.error_code == code and before == var_to_bytes(state), "P5 atomic: " + label)


func _test_content() -> void:
	var original: Dictionary = {}
	for category in Validator.CATEGORIES:
		original[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % category))
	var cases := [
		["quests", ["unlock"], {"type": "initial"}],
		["exploration_events", ["unlock"], {"type": "initial"}],
		["quests", ["required_recipe_id"], "recipe_missing"],
		["quests", ["min_quality"], "mythic"],
		["quests", ["quantity"], 0],
		["quests", ["reward_exp"], -1],
		["quests", ["repeatable"], 1],
		["quests", ["reward_items"], {"recipe_juling": 1}],
		["quests", ["reward_flame"], "flame_missing"],
		["exploration_events", ["weight"], 0],
		["exploration_events", ["weight"], INF],
		["exploration_events", ["options"], []],
		["exploration_events", ["options", 0, "cost_stones"], -1],
		["exploration_events", ["options", 0, "success_rate"], NAN],
		["exploration_events", ["options", 0, "success_rate"], 1.1],
		["exploration_events", ["options", 0, "success_items"], {"herb_missing": 1}],
		["exploration_events", ["options", 0, "failure_items"], {"herb_lingcao": 0}],
		["exploration_events", ["options", 0, "reward_flame"], "flame_missing"],
		["exploration_events", ["options", 1, "id"], "choice_gather"],
	]
	for i in range(cases.size()):
		var test: Array = cases[i]
		var changed := original.duplicate(true)
		var target: Variant = changed[test[0]].items[0]
		for j in range(test[1].size() - 1):
			target = target[test[1][j]]
		target[test[1][-1]] = test[2]
		var result := db.load_documents(changed)
		var expected_path: String = test[0] + ".items[0]"
		for segment in test[1]:
			expected_path += "[%d]" % segment if segment is int else "." + segment
		var diagnostic := false
		for error in result.errors:
			diagnostic = diagnostic or error.path.begins_with(expected_path)
		_check.call(not result.ok and diagnostic and db.get_counts().quests == 5, "P5 content rejects invalid resource field %d" % i)
	var quest := db.get_item("quest_juling_supply")
	_check.call(quest.quantity is int and quest.reward_items.herb_lingcao is int and db.get_item("event_qinglan").options[0].cost_stones is int, "P5: Resource JSON quantities normalize to runtime integers")
	var state := _new()
	state.pending_exploration = {"instance_id": [], "event_id": "event_qinglan", "serial": 1}
	state.exploration_serial = 1
	_expect_failure(state, func() -> Dictionary: return forage.forage(state, "invalid"), "INVALID_STATE", "Invalid event structure is rejected without a runtime error")


func _test_quests() -> void:
	var state := _new()
	var before := var_to_bytes(state)
	var board := quests.board(state)
	forage.preview(state)
	explore.destinations(state)
	_check.call(board.ok and board.result.rows.size() == 5 and board.result.rows[0].can_accept and before == var_to_bytes(state), "P5: Resource previews are pure and basic repeatable quest is available")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_missing", "bad"), "UNKNOWN_QUEST", "Unknown quest")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_ningshen_supply", "locked"), "QUEST_LOCKED", "Quest rank and recipe gate")
	var accepted := quests.accept(state, "quest_juling_supply", "accept")
	var id: String = accepted.result.instance_id
	_check.call(accepted.ok and state.action_count == 0 and state.quest_serial == 1 and state.needs_save, "P5: Accept creates a unique instance without consuming a gameplay action")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_juling_supply", "accept"), "ACTION_DUPLICATE", "Replay accept action")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_juling_supply", "another"), "QUEST_UNAVAILABLE", "No parallel duplicate template")
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "empty"), "INSUFFICIENT_PILLS", "Missing pills")
	inventory.add_pill(state, "recipe_juling", "common", 1, "common")
	inventory.add_pill(state, "recipe_juling", "legendary", 1, "legendary")
	before = var_to_bytes(state)
	var view := quests.preview_delivery(state, id)
	_check.call(view.ok and view.result.consumed == {Pills.key("recipe_juling", "common"): 1} and before == var_to_bytes(state), "P5: Delivery preview consumes the least eligible quality first and remains pure")
	var rng_before: Dictionary = state.rng_states.duplicate(true)
	var delivered := quests.deliver(state, id, "deliver")
	_check.call(delivered.ok and state.spirit_stones == 240 and state.exp == 6 and state.inventory.herb_lingcao == 7 and state.resource_stats.quests_completed == 1 and state.action_count == 1, "P5: Delivery consumes pills and atomically grants all rewards and statistics")
	_check.call(state.pills.has(Pills.key("recipe_juling", "legendary")) and not state.pills.has(Pills.key("recipe_juling", "common")) and state.rng_states == rng_before, "P5: Higher quality and all RNG streams remain untouched by delivery")
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "deliver"), "ACTION_DUPLICATE", "Delivery action replay")
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "new-deliver"), "QUEST_ALREADY_COMPLETED", "Fresh action cannot reclaim old instance")
	var again := quests.accept(state, "quest_juling_supply", "repeat")
	_check.call(again.ok and again.result.instance_id != id, "P5: Repeatable template creates a fresh instance")
	_check.call(quests.deliver(state, again.result.instance_id, "higher-quality").ok and state.pills.is_empty(), "P5: Higher quality can satisfy a lower-quality quest")
	var once := quests.accept(state, "quest_juling_elite", "elite")
	id = once.result.instance_id
	inventory.add_pill(state, "recipe_juling", "good", 1, "low")
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "too-low"), "INSUFFICIENT_PILLS", "Low quality cannot satisfy superior requirement")
	inventory.add_pill(state, "recipe_juling", "superior", 1, "high")
	_check.call(quests.deliver(state, id, "elite-done").ok and state.inventory.consumable_juling == 1, "P5: One-time superior quest grants its token")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_juling_elite", "elite-again"), "QUEST_UNAVAILABLE", "One-time template cannot be regenerated")
	state = _new()
	id = quests.accept(state, "quest_juling_supply", "a").result.instance_id
	inventory.add_pill(state, "recipe_juling", "common", 1, "p")
	state.spirit_stones = MAX
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "overflow"), "AMOUNT_OVERFLOW", "Wallet overflow rolls back pills, rewards and quest status")
	state.spirit_stones = 0
	state.exp = MAX
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "exp-overflow"), "AMOUNT_OVERFLOW", "Experience overflow rolls back complete delivery")
	state.exp = 0
	state.inventory.herb_lingcao = MAX
	_expect_failure(state, func() -> Dictionary: return quests.deliver(state, id, "item-overflow"), "AMOUNT_OVERFLOW", "Item overflow rolls back complete delivery")
	# Fire trial: multi-pill quantity across eligible qualities and permanent reward.
	state = _new()
	state.rank = 1
	state.unlocked_recipes.append("recipe_cuiti")
	id = quests.accept(state, "quest_fire_trial", "fire").result.instance_id
	inventory.add_pill(state, "recipe_cuiti", "common", 2, "two")
	inventory.add_pill(state, "recipe_cuiti", "good", 2, "two-good")
	var fire := quests.deliver(state, id, "fire-done")
	_check.call(fire.ok and state.owned_flames.has("flame_earth") and state.pills[Pills.key("recipe_cuiti", "good")].quantity == 1 and state.inventory.ore_tiejing == 2, "P5: Quantity spans qualities and deterministic trial grants permanent flame")


func _test_exploration() -> void:
	var state := _new()
	var rng_before: Dictionary = state.rng_states.duplicate(true)
	var offers: Array = explore.destinations(state).result.rows
	_check.call(offers[0].encounter_probability == 0.5 and offers[1].encounter_probability == 0.25 and offers[3].encounter_probability == 0, "P5: Random encounter weights are renormalized over rank-eligible events")
	_expect_failure(state, func() -> Dictionary: return explore.enter(state, "bad", "event_missing"), "UNKNOWN_EVENT", "Unknown destination")
	_expect_failure(state, func() -> Dictionary: return explore.enter(state, "locked", "event_earth_fire"), "RANK_LOCKED", "Destination rank gate")
	var entered := explore.enter(state, "enter", "event_qinglan")
	var id: String = entered.result.instance_id
	_check.call(entered.ok and state.action_count == 1 and state.resource_stats.explorations == 1 and state.rng_states == rng_before, "P5: Direct destination costs one action and no RNG")
	_expect_failure(state, func() -> Dictionary: return explore.enter(state, "reenter"), "EVENT_PENDING", "Cannot overwrite unresolved event")
	_expect_failure(state, func() -> Dictionary: return quests.accept(state, "quest_juling_supply", "quest-pending"), "EVENT_PENDING", "Pending event blocks unrelated resource commands")
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, "old", "choice_gather", "stale"), "EVENT_CHANGED", "Stale event instance")
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "unknown", "unknown"), "UNKNOWN_OPTION", "Unknown event choice")
	var before := var_to_bytes(state)
	var view := explore.preview_option(state, id, "choice_deep")
	_check.call(view.ok and view.result.can_execute and before == var_to_bytes(state), "P5: Choice costs and preview do not draw RNG")
	state.spirit_stones = 0
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "choice_deep", "poor"), "NOT_ENOUGH_STONES", "Unaffordable choice consumes no RNG")
	var safe := explore.resolve(state, id, "choice_gather", "safe")
	_check.call(safe.ok and safe.result.success and state.pending_exploration.is_empty() and state.inventory.herb_lingcao == 7 and state.rng_states == rng_before and state.action_count == 1, "P5: Free safe choice settles once with deterministic reward")
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "choice_gather", "safe"), "ACTION_DUPLICATE", "Choice action replay")
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "choice_gather", "new-reward"), "EVENT_CHANGED", "Fresh action cannot reward resolved event")
	id = explore.enter(state, "enter2", "event_old_grove").result.instance_id
	_check.call(id != entered.result.instance_id and explore.leave(state, id, "leave").ok and state.rng_states == rng_before and state.action_count == 2, "P5: New visits have unique IDs; leaving costs nothing extra")
	state = _new(55)
	var mirror := state.duplicate(true)
	var first := explore.enter(state, "random")
	var second := explore.enter(mirror, "random")
	_check.call(first == second and state == mirror, "P5: Same seed and action replay the same random destination")
	var expected_rng := Context.new(55)
	var eligible := db.get_items("exploration_events").slice(0, 3)
	var expected_id := Rules.pick_event(eligible, expected_rng.next_float("exploration"))
	_check.call(first.result.event.id == expected_id and state.rng_states == expected_rng.snapshot(), "P5: Actual random entry uses shared weighted rule and exactly one exploration draw")
	var original_rng := Context.new(55).snapshot()
	_check.call(state.rng_states.streams.alchemy == original_rng.streams.alchemy and state.rng_states.streams.world == original_rng.streams.world and state.rng_states.streams.exploration != original_rng.streams.exploration, "P5: Random destination advances exploration stream only")
	# Paid random choice failure/success, replay from detached checkpoint.
	state = _new(2)
	id = explore.enter(state, "enter", "event_qinglan").result.instance_id
	mirror = state.duplicate(true)
	expected_rng = Context.new(2)
	var expected_success := Rules.succeeds(0.3, expected_rng.next_float("exploration"))
	var random_result := explore.resolve(state, id, "choice_deep", "risk")
	var mirrored := explore.resolve(mirror, id, "choice_deep", "risk")
	_check.call(random_result == mirrored and state == mirror and state.spirit_stones == 194, "P5: Paid random settlement replays from complete checkpoint")
	_check.call(state.rng_states.streams.exploration != original_rng.streams.exploration and state.rng_states.streams.alchemy == Context.new(2).snapshot().streams.alchemy, "P5: Choice draw leaves alchemy RNG unchanged")
	_check.call(random_result.result.success == expected_success and state.rng_states == expected_rng.snapshot() and random_result.result.items == (db.get_item("event_qinglan").options[1].success_items if expected_success else db.get_item("event_qinglan").options[1].failure_items), "P5: Actual choice branch, fallback rewards and RNG match shared probability rule")
	# Either random branch would overflow; RNG and cost must both roll back.
	state = _new()
	id = explore.enter(state, "enter", "event_qinglan").result.instance_id
	state.inventory.herb_lingcao = MAX
	state.inventory["herb_lingzhi"] = MAX
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "choice_deep", "overflow"), "AMOUNT_OVERFLOW", "Reward overflow after draw rolls back RNG, costs and pending event")
	state = _new()
	for pair in [["event_old_grove", "choice_trade", "herb_lingzhi"], ["event_soul_spring", "choice_offer", "essence_hunlu"]]:
		id = explore.enter(state, pair[0], pair[0]).result.instance_id
		_check.call(explore.resolve(state, id, pair[1], pair[1]).ok and state.inventory[pair[2]] == 1, "P5: Deterministic rare-material path: " + pair[2])
	state.rank = 1
	id = explore.enter(state, "fire-enter", "event_earth_fire").result.instance_id
	_expect_failure(state, func() -> Dictionary: return explore.resolve(state, id, "choice_ritual", "no-ore"), "INSUFFICIENT_ITEMS", "Ritual checks required items before charging")
	inventory.add_items(state, {"ore_tiejing": 4}, "ore")
	var stones: int = state.spirit_stones
	_check.call(explore.resolve(state, id, "choice_ritual", "ritual").ok and state.spirit_stones == stones - 30 and state.inventory.ore_tiejing == 2 and state.owned_flames.has("flame_earth"), "P5: Guaranteed ritual consumes costs and grants flame in one transaction")
	id = explore.enter(state, "fire-enter2", "event_earth_fire").result.instance_id
	_check.call(explore.resolve(state, id, "choice_ritual", "ritual2").ok and state.owned_flames.count("flame_earth") == 1 and not state.inventory.has("ore_tiejing"), "P5: Repeated flame reward never duplicates permanent ownership")
	state = _new()
	state.exploration_serial = MAX
	_expect_failure(state, func() -> Dictionary: return explore.enter(state, "serial"), "AMOUNT_OVERFLOW", "Random entry serial overflow restores original RNG")


func _test_recovery() -> void:
	var state := _new()
	_expect_failure(state, func() -> Dictionary: return forage.forage(state, "surplus"), "FORAGE_NOT_NEEDED", "Free forage cannot stockpile above a basic furnace")
	_expect_failure(state, func() -> Dictionary: return forage.rest(state, "early"), "REST_NOT_NEEDED", "Rest unavailable before exhaustion")
	state.inventory = {"herb_lingcao": 1}
	state.spirit_stones = 0
	var rng_before: Dictionary = state.rng_states.duplicate(true)
	var collected := forage.forage(state, "partial")
	_check.call(collected.ok and collected.result.items == {"herb_lingcao": 1, "herb_qinghua": 1} and state.inventory == {"herb_lingcao": 2, "herb_qinghua": 1} and state.rng_states == rng_before, "P5: Forage fills only missing basic materials at zero money without RNG")
	_expect_failure(state, func() -> Dictionary: return forage.forage(state, "partial"), "ACTION_DUPLICATE", "Forage action replay")
	# Find a genuine five-failure seed using the actual alchemy stream; no mocked results.
	var failure_seed := -1
	for seed_value in range(100000):
		var rng := Context.new(seed_value)
		var all_fail := true
		for i in range(5):
			if rng.next_float("alchemy") < 0.8:
				all_fail = false
				break
		if all_fail:
			failure_seed = seed_value
			break
	_check.call(failure_seed >= 0, "P5: Found fixed seed for five real consecutive failures")
	state = _new(failure_seed)
	state.spirit_stones = 0
	state.inventory.clear()
	state.pills.clear()
	var alchemy := Alchemy.new(db)
	var shop := Shop.new(db)
	var recovered := true
	for i in range(5):
		if state.forage_uses == 3:
			var checkpoint: Dictionary = state.rng_states.duplicate(true)
			var exhausted := var_to_bytes(state)
			var blocked := forage.forage(state, "exhausted")
			_check.call(not blocked.ok and blocked.error_code == "FORAGE_EXHAUSTED" and exhausted == var_to_bytes(state), "P5: Exhaustion does not charge or draw")
			_check.call(forage.rest(state, "rest-%d" % i).ok and state.forage_uses == 0 and state.rng_states == checkpoint, "P5: Free rest resets all charges without RNG or currency")
		recovered = recovered and forage.forage(state, "forage-%d" % i).ok
		var brew := alchemy.execute_alchemy(state, "recipe_juling", {}, "brew-%d" % i)
		recovered = recovered and brew.ok and not brew.result.success
		recovered = recovered and shop.sell_item(state, "material_danzha", 1, "sell-%d" % i).ok
	_check.call(recovered and state.spirit_stones == 15 and state.resource_stats.forages == 5 and state.resource_stats.rests == 1 and state.statistics.alchemy_failures == 5, "P5: Zero money/items/pills plus five failures still restores 15 stones through free forage/rest and residue sales")
	_check.call(shop.buy_batch(state, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}], "recovered-buy").ok and state.spirit_stones == 1, "P5: Worst-case recovery reaches an ordinary paid furnace")
	_check.call(resources.validate(state).ok and forage.preview(state).result.recovery_available, "P5: Recovery route remains valid after repeated failures")


func _test_distribution() -> void:
	var events := db.get_items("exploration_events")
	var total := 0.0
	for event in events: total += event.weight
	_check.call(Rules.pick_event(events, 0.0) == "event_qinglan" and Rules.pick_event(events, events[0].weight / total) == "event_old_grove" and Rules.pick_event(events, 0.99999999) == events[-1].id, "P5: Weighted event selection uses half-open boundaries")
	_check.call(not Rules.succeeds(0.3, 0.3) and Rules.succeeds(0.3, 0.29999999) and not Rules.succeeds(0, 0) and Rules.succeeds(1, 0.99999999), "P5: Event success uses exact displayed probability boundaries")
	var rng := Context.new(20261119)
	var counts: Dictionary = {}
	var wins: Dictionary = {}
	var rates := [0.25, 0.3, 0.35, 0.4, 1.0]
	for event in events:
		counts[event.id] = 0
	for rate in rates:
		wins[rate] = 0
	for i in range(100000):
		counts[Rules.pick_event(events, rng.next_float("exploration"))] += 1
		for rate in rates:
			if Rules.succeeds(rate, rng.next_float("exploration")):
				wins[rate] += 1
	for event in events:
		var expected: float = event.weight / total
		var actual: float = counts[event.id] / 100000.0
		_check.call(absf(actual - expected) <= 6 * sqrt(expected * (1 - expected) / 100000.0), "P5 statistics: %s %.4f / %.4f" % [event.id, actual, expected])
	for rate in rates:
		var actual: float = wins[rate] / 100000.0
		_check.call(absf(actual - rate) <= maxf(0.000001, 6 * sqrt(rate * (1 - rate) / 100000.0)), "P5 statistics: choice %.2f observed %.4f" % [rate, actual])
