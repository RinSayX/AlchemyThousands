extends RefCounted
## P2 transaction, inventory, price, boundary and idempotency regressions.

const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")

var _check: Callable
var _db: Database
var _economy: Economy
var _inventory: Inventory
var _shop: Shop


func run(check: Callable) -> bool:
	_check = check
	_db = Database.new()
	var loaded := _db.load_directory()
	_check.call(loaded.ok, "P2: Content dependency loads")
	if not loaded.ok:
		return false
	_economy = Economy.new(_db)
	_inventory = Inventory.new(_db)
	_shop = Shop.new(_db)
	_check.call(_test_currency(), "P2: Currency group completed")
	_check.call(_test_inventory(), "P2: Inventory group completed")
	_check.call(_test_shop(), "P2: Shop group completed")
	_check.call(_test_pills(), "P2: Pills group completed")
	_check.call(_test_limits(), "P2: Limits group completed")
	_check.call(_test_invalid_states(), "P2: Invalid-state group completed")
	_check.call(_test_replay_and_quotes(), "P2: Replay group completed")
	return true


func _state() -> Dictionary:
	return _economy.create_economy_state().result.state


func _test_currency() -> bool:
	var state := _state()
	_check.call(state.spirit_stones == 200 and state.inventory == {"herb_lingcao": 5, "herb_qinghua": 3} and state.unlocked_recipes == ["recipe_juling"], "P2: Economy initialization matches design baseline")
	var credited := _economy.change_stones(state, 20, "reward-1")
	_check.call(credited.ok and state.spirit_stones == 220 and credited.state_changes.spirit_stones == {"before": 200, "after": 220}, "P2: Currency credit returns a correct detached receipt")
	_reject(state, func() -> Dictionary: return _economy.change_stones(state, 20, "reward-1"), "ACTION_DUPLICATE", "Duplicate reward cannot pay twice")
	_check.call(_economy.change_stones(state, -220, "spend-1").ok and state.spirit_stones == 0, "P2: Exact debit can reach zero")
	_reject(state, func() -> Dictionary: return _economy.change_stones(state, -1, "spend-2"), "NOT_ENOUGH_STONES", "Currency cannot go below zero")
	for amount in [0, true, 1.5, "10", NAN, INF, 2147483648]:
		_reject(state, func() -> Dictionary: return _economy.change_stones(state, amount, "invalid-amount"), "INVALID_AMOUNT", "Invalid currency delta %s" % str(amount))
	for id in ["", "  ", null, 3, "a".repeat(129)]:
		_reject(state, func() -> Dictionary: return _economy.change_stones(state, 1, id), "INVALID_ACTION_ID", "Invalid action ID %s" % str(id))
	_check.call(_economy.change_stones(state, 1, "invalid-amount").ok, "P2: Failed validation does not consume an action ID")
	return true


func _test_inventory() -> bool:
	var state := _state()
	_check.call(_inventory.add_items(state, {"herb_lingcao": 2, "consumable_wendan": 1}, "grant-items").ok and state.inventory.herb_lingcao == 7, "P2: Materials and consumables stack in one grant")
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"herb_lingcao": 2}, "grant-items"), "ACTION_DUPLICATE", "Inventory rewards are idempotent")
	_check.call(_inventory.consume_items(state, {"herb_lingcao": 7, "consumable_wendan": 1}, "consume-items").ok and not state.inventory.has("herb_lingcao") and not state.inventory.has("consumable_wendan"), "P2: Consuming the last item removes its stack")
	_reject(state, func() -> Dictionary: return _inventory.consume_items(state, {"herb_qinghua": 1, "herb_lingcao": 1}, "bad-consume"), "INSUFFICIENT_ITEMS", "Multi-item consumption rolls back the whole operation")
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"herb_qinghua": 1, "missing_item": 1}, "bad-grant"), "UNKNOWN_ITEM", "Mixed valid and invalid grants are atomic")
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"recipe_zhixue": 1}, "bad-recipe"), "UNKNOWN_ITEM", "Recipes cannot masquerade as stackable inventory")
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {}, "empty-grant"), "INVALID_QUANTITY", "Empty item grant is rejected")
	for quantity in [0, -1, 0.5, false, "2", NAN, INF, 2147483648, 9223372036854775807]:
		_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"herb_lingcao": quantity}, "bad-qty"), "INVALID_QUANTITY", "Invalid stack quantity %s" % str(quantity))
	var before := var_to_bytes(state)
	var plan := _inventory.plan_items(state, {"herb_qinghua": 4})
	_check.call(plan.ok and plan.result.candidate.inventory.herb_qinghua == 7 and var_to_bytes(state) == before, "P2: Inventory plans leave caller state unchanged")
	plan.result.candidate.inventory.herb_qinghua = 999
	_check.call(state.inventory.herb_qinghua == 3, "P2: Inventory plans have no nested state aliases")
	_check.call(_inventory.add_items(state, {"herb_lingzhi": 1}, "future-quest").ok, "P2: Internal grants can hold non-shop materials without enabling purchase")
	return true


func _test_shop() -> bool:
	var state := _state()
	var cart := [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}, {"item_id": "consumable_wendan", "quantity": 2}]
	var before := var_to_bytes(state)
	var quote := _shop.quote_buy(state, cart)
	_check.call(quote.ok and quote.result.total == 30 and quote.result.balance_after == 170 and var_to_bytes(state) == before and quote.state_changes.is_empty() and not quote.result.has("candidate"), "P2: Cart preview shows authoritative prices without consuming resources")
	var bought := _shop.buy_batch(state, cart, "buy-cart")
	_check.call(bought.ok and bought.result.total == 30 and state.spirit_stones == 170 and state.inventory.herb_lingcao == 7 and state.inventory.herb_qinghua == 4 and state.inventory.consumable_wendan == 2, "P2: Bulk purchase commits exact totals and inventory")
	_check.call(state.completed_actions == ["buy-cart"], "P2: Cart records one completed action")
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, cart, "buy-cart"), "ACTION_DUPLICATE", "Repeated purchase cannot charge twice")
	_check.call(_shop.sell_batch(state, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "consumable_wendan", "quantity": 2}], "sell-cart").ok and state.spirit_stones == 176 and not state.inventory.has("consumable_wendan"), "P2: Material and consumable bulk resale uses sell prices")
	_reject(state, func() -> Dictionary: return _shop.sell_item(state, "herb_lingcao", 100, "oversell"), "INSUFFICIENT_ITEMS", "Cannot sell unowned quantities")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "herb_lingzhi", 1, "rare-free"), "NOT_FOR_SALE", "Non-shop buy_price zero cannot yield free rare materials")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "herb_ningshen", 1, "locked-material"), "RANK_LOCKED", "Higher-rank materials are locked")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "consumable_hulu", 1, "locked-token"), "RANK_LOCKED", "Higher-rank consumables are locked")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "flame_earth", 1, "exploration-flame"), "NOT_FOR_SALE", "Exploration-only flames are not shop items")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "recipe_ningshen", 1, "rank-recipe"), "NOT_FOR_SALE", "Rank rewards cannot be bought from placeholder prices")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "missing_item", 1, "unknown"), "UNKNOWN_ITEM", "Unknown goods are rejected")
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, [{"item_id": "herb_lingcao", "quantity": 1, "unit_price": 0}], "forged-price"), "INVALID_CART", "Callers cannot provide forged prices")
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, [], "empty-cart"), "INVALID_CART", "Empty carts are rejected")
	var long_cart: Array = []
	long_cart.resize(129)
	long_cart.fill({"item_id": "herb_lingcao", "quantity": 1})
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, long_cart, "long-cart"), "INVALID_CART", "Oversized carts are rejected")
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, [{"item_id": "herb_lingcao", "quantity": 1}, {"item_id": "herb_lingzhi", "quantity": 1}], "late-bad-line"), "NOT_FOR_SALE", "Invalid final cart line rolls back valid earlier lines")
	_reject(state, func() -> Dictionary: return _shop.sell_batch(state, [{"item_id": "herb_lingcao", "quantity": 1}, {"item_id": "herb_lingcao", "quantity": 5}], "duplicate-sale-lines"), "INSUFFICIENT_ITEMS", "Repeated sale lines cannot overdraw a stack")
	var poor := _state()
	poor.spirit_stones = 13
	_reject(poor, func() -> Dictionary: return _shop.buy_batch(poor, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}], "poor-cart"), "NOT_ENOUGH_STONES", "Whole cart affordability is checked before charging")
	poor.spirit_stones = 14
	_check.call(_shop.buy_batch(poor, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}], "poor-cart").ok and poor.spirit_stones == 0, "P2: Exact funds can buy a full cart; failed ID remains reusable")
	_check.call(_shop.buy_item(state, "recipe_zhixue", 1, "buy-recipe").ok and state.unlocked_recipes.has("recipe_zhixue"), "P2: Buying a recipe grants a permanent unlock")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "recipe_zhixue", 1, "rebuy-recipe"), "ALREADY_OWNED", "Permanent recipes cannot be repurchased")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "furnace_qingmu", 1, "locked-furnace"), "RANK_LOCKED", "Furnaces honor rank requirements")
	state.rank = 1 # Fixture only; progression remains a later phase.
	state.spirit_stones = 1000
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "furnace_qingmu", 2, "two-furnaces"), "INVALID_QUANTITY", "Permanent equipment cannot be bulk stacked")
	_reject(state, func() -> Dictionary: return _shop.buy_batch(state, [{"item_id": "furnace_qingmu", "quantity": 1}, {"item_id": "furnace_qingmu", "quantity": 1}], "duplicate-furnaces"), "ALREADY_OWNED", "Duplicate permanent goods make the entire cart fail")
	_check.call(_shop.buy_item(state, "furnace_qingmu", 1, "buy-furnace").ok and state.spirit_stones == 780 and state.owned_furnaces.has("furnace_qingmu"), "P2: Eligible furnace purchase costs its configured price")
	_reject(state, func() -> Dictionary: return _shop.sell_item(state, "furnace_qingmu", 1, "sell-furnace"), "NOT_SELLABLE", "Permanent gear cannot be sold as a stack")
	return true


func _test_pills() -> bool:
	var state := _state()
	for quality in Pills.QUALITIES:
		_check.call(_inventory.add_pill(state, "recipe_juling", quality, 2, "grant-" + quality).ok, "P2: Hold pill quality " + quality)
	_check.call(state.pills.size() == 4, "P2: Different qualities occupy separate stacks")
	_check.call(_inventory.add_pill(state, "recipe_juling", "common", 1, "grant-extra", null).ok and state.pills[Pills.key("recipe_juling", "common")].quantity == 3, "P2: Same recipe/quality merges; null mutation means ordinary pill")
	var sold := _shop.sell_batch(state, [{"recipe_id": "recipe_juling", "quality": "common", "quantity": 1}, {"recipe_id": "recipe_juling", "quality": "good", "quantity": 1}, {"recipe_id": "recipe_juling", "quality": "superior", "quantity": 1}, {"recipe_id": "recipe_juling", "quality": "legendary", "quantity": 1}], "sell-qualities")
	_check.call(sold.ok and sold.result.total == 286 and state.spirit_stones == 486, "P2: Pill prices follow 1x / 1.5x / 2.5x / 6x multipliers")
	_check.call(_inventory.consume_pill(state, "recipe_juling", "legendary", 1, "consume-pill").ok and not state.pills.has(Pills.key("recipe_juling", "legendary")), "P2: Consuming the last pill removes that quality stack")
	_reject(state, func() -> Dictionary: return _shop.sell_pill(state, "recipe_juling", "legendary", 1, "missing-pill"), "INSUFFICIENT_PILLS", "Pill sale cannot substitute another quality")
	_reject(state, func() -> Dictionary: return _inventory.add_pill(state, "recipe_missing", "common", 1, "bad-recipe"), "UNKNOWN_RECIPE", "Unknown pill recipes are rejected")
	_reject(state, func() -> Dictionary: return _inventory.add_pill(state, "recipe_juling", "mythic", 1, "bad-quality"), "INVALID_QUALITY", "Unknown pill qualities are rejected")
	_reject(state, func() -> Dictionary: return _inventory.add_pill(state, "recipe_juling", "good", 1, "bad-mutation", "mutation_fire"), "UNSUPPORTED_MUTATION", "Unregistered mutations cannot enter inventory")
	_reject(state, func() -> Dictionary: return _shop.sell_batch(state, [{"item_id": "herb_lingcao", "quantity": 1}, {"recipe_id": "recipe_juling", "quality": "legendary", "quantity": 1}], "mixed-oversell"), "INSUFFICIENT_PILLS", "Mixed material/pill sales are atomic")
	var odd_db := _modified_db(25)
	var odd_shop := Shop.new(odd_db)
	_inventory.add_pill(state, "recipe_juling", "good", 2, "rounding-fixture")
	var quote := odd_shop.quote_sell(state, [{"recipe_id": "recipe_juling", "quality": "good", "quantity": 2}])
	_check.call(quote.ok and quote.result.total == 74 and quote.result.lines[0].unit_price == 37, "P2: Odd base prices round down per pill before bulk multiplication")
	return true


func _test_limits() -> bool:
	var state := _state()
	state.spirit_stones = Economy.MAX_VALUE
	_reject(state, func() -> Dictionary: return _economy.change_stones(state, 1, "rich-reward"), "AMOUNT_OVERFLOW", "Wallet credits cannot exceed the cap")
	_reject(state, func() -> Dictionary: return _shop.sell_item(state, "herb_lingcao", 1, "rich-sale"), "AMOUNT_OVERFLOW", "Wallet overflow cannot consume sold inventory")
	state.inventory.herb_lingcao = Economy.MAX_VALUE
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"herb_lingcao": 1}, "full-stack"), "AMOUNT_OVERFLOW", "Item stacks cannot exceed the cap")
	state.inventory.clear()
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "herb_lingcao", Economy.MAX_VALUE, "huge-cart"), "AMOUNT_OVERFLOW", "Large price products are checked before settlement")
	_check.call(_inventory.add_pill(state, "recipe_juling", "common", Economy.MAX_VALUE, "max-pill-stack").ok, "P2: Maximum pill quantity is stored without per-unit allocation")
	_reject(state, func() -> Dictionary: return _inventory.add_pill(state, "recipe_juling", "common", 1, "pill-overflow"), "AMOUNT_OVERFLOW", "Pill stack overflow fails without changing resources")
	var expensive := Shop.new(_modified_db(Economy.MAX_VALUE))
	_reject(state, func() -> Dictionary: return expensive.sell_pill(state, "recipe_juling", "legendary", 1, "expensive-no-stock"), "INSUFFICIENT_PILLS", "Expensive pills still require the exact stack")
	_inventory.add_pill(state, "recipe_juling", "legendary", Economy.MAX_VALUE, "expensive-stock")
	_reject(state, func() -> Dictionary: return expensive.sell_pill(state, "recipe_juling", "legendary", Economy.MAX_VALUE, "unit-overflow"), "AMOUNT_OVERFLOW", "Pill multiplier overflow is caught before quantity multiplication")
	state = _state()
	_check.call(_inventory.add_items(state, {"herb_lingcao": Economy.MAX_VALUE - 5}, "fill-to-cap").ok and state.inventory.herb_lingcao == Economy.MAX_VALUE, "P2: Exact item cap is allowed")
	return true


func _test_invalid_states() -> bool:
	var variants := [
		["spirit_stones", -1], ["spirit_stones", 200.0], ["rank", 11], ["inventory", []],
		["inventory", {"herb_lingcao": -1}], ["inventory", {"herb_lingcao": 1.0}], ["inventory", {"unknown_item": 1}],
		["owned_furnaces", ["furnace_missing"]], ["unlocked_recipes", ["recipe_juling", "recipe_juling"]],
		["completed_actions", ["same", "same"]], ["pills", {"bad-key": Pills.create("recipe_juling", "good", 1)}],
		["pills", {Pills.key("recipe_juling", "common"): Pills.create("recipe_missing", "common", 1)}],
	]
	for case in variants:
		var state := _state()
		state[case[0]] = case[1]
		_reject(state, func() -> Dictionary: return _shop.buy_item(state, "herb_lingcao", 1, "bad-state"), "INVALID_STATE", "Malformed state field " + case[0])
	var state := _state()
	state.erase("pills")
	_reject(state, func() -> Dictionary: return _inventory.add_items(state, {"herb_lingcao": 1}, "missing-state"), "INVALID_STATE", "Missing required state fields fail without repair")
	return true


func _test_replay_and_quotes() -> bool:
	var state := _state()
	state["rng_states"] = {"alchemy": 1234, "exploration": 5678}
	state["meta"] = {"collection": ["unchanged"]}
	var quote := _shop.quote_buy(state, [{"item_id": "herb_lingcao", "quantity": 10}])
	quote.result.lines[0].unit_price = 0
	_economy.change_stones(state, -199, "spend-after-preview")
	_reject(state, func() -> Dictionary: return _shop.buy_item(state, "herb_lingcao", 10, "stale-preview"), "NOT_ENOUGH_STONES", "Execution rechecks funds after a stale or edited preview")
	_check.call(state.rng_states == {"alchemy": 1234, "exploration": 5678} and state.meta == {"collection": ["unchanged"]}, "P2: Transactions preserve unrelated state and RNG streams")
	var receipt := _inventory.add_items(state, {"herb_qinghua": 2}, "shared-id")
	receipt.state_changes.inventory.after.herb_qinghua = 999
	_check.call(state.inventory.herb_qinghua == 5, "P2: Editing a receipt cannot change committed inventory")
	_reject(state, func() -> Dictionary: return _economy.change_stones(state, 10, "shared-id"), "ACTION_DUPLICATE", "Action IDs cannot be replayed through another service")
	var restored: Dictionary = bytes_to_var(var_to_bytes(state))
	_reject(restored, func() -> Dictionary: return _inventory.add_items(restored, {"herb_qinghua": 2}, "shared-id"), "ACTION_DUPLICATE", "Action history protects an independently restored state")
	var batch := _state()
	var singles := _state()
	_shop.buy_batch(batch, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_lingcao", "quantity": 3}], "batch")
	for index in range(5):
		_shop.buy_item(singles, "herb_lingcao", 1, "single-%d" % index)
	_check.call(batch.spirit_stones == singles.spirit_stones and batch.inventory == singles.inventory, "P2: Duplicate bulk lines aggregate identically to single purchases")
	var snapshot := var_to_bytes(batch)
	_shop.quote_sell(batch, [{"item_id": "herb_lingcao", "quantity": 1}])
	_shop.quote_sell(batch, [{"recipe_id": "recipe_juling", "quality": "good", "quantity": 1}])
	_check.call(var_to_bytes(batch) == snapshot, "P2: Both successful and failed sale previews are pure")
	return true


func _modified_db(base_price: int) -> Database:
	var documents: Dictionary = {}
	for category in ["recipes", "materials", "furnaces", "flames", "consumables", "quests", "exploration_events", "ranks", "talents", "inheritances", "world_modifiers"]:
		documents[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + category + ".json"))
	documents.recipes.items[0].base_sell_price = base_price
	var db := Database.new()
	var loaded := db.load_documents(documents)
	_check.call(loaded.ok, "P2: Modified price fixture validates")
	return db


func _reject(state: Dictionary, operation: Callable, code: String, name: String) -> void:
	var snapshot := var_to_bytes(state)
	var result: Dictionary = operation.call()
	var unchanged := snapshot == var_to_bytes(state)
	var rejected: bool = not result.ok and result.error_code == code and not result.message.is_empty() and result.state_changes.is_empty() and result.result.is_empty()
	_check.call(rejected and unchanged, "P2 rejects atomically: " + name)
	if not rejected or not unchanged:
		printerr("Expected %s, got %s; state unchanged: %s" % [code, result, unchanged])
