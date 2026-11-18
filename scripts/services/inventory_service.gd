class_name InventoryService
extends RefCounted

const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")

var _db: Database
var _economy: Economy


func _init(content: Database) -> void:
	_db = content
	_economy = Economy.new(content)


func add_items(state: Dictionary, quantities: Variant, action_id: Variant) -> Dictionary:
	return _execute(state, quantities, action_id, false)


func consume_items(state: Dictionary, quantities: Variant, action_id: Variant) -> Dictionary:
	return _execute(state, quantities, action_id, true)


func _execute(state: Dictionary, quantities: Variant, action_id: Variant, remove: bool) -> Dictionary:
	var checked := _economy.prepare(state, action_id)
	if not checked.ok:
		return checked
	var planned := plan_items(state, quantities, remove)
	if not planned.ok:
		return planned
	return _economy.commit(state, planned.result.candidate, action_id)


func plan_items(state: Dictionary, quantities: Variant, remove: bool = false) -> Dictionary:
	var checked := _economy.validate_state(state)
	if not checked.ok:
		return checked
	if not quantities is Dictionary or quantities.is_empty():
		return Result.failure("INVALID_QUANTITY", "物品数量表必须为非空对象。")
	var next := state.duplicate(true)
	for id in quantities:
		if not id is String or not _economy.is_stackable(id):
			return Result.failure("UNKNOWN_ITEM", "只能增减已定义的材料与消耗品。")
		var quantity: Variant = quantities[id]
		if not Economy.valid_integer(quantity):
			return Result.failure("INVALID_QUANTITY", "数量须为范围内的正整数。")
		var owned: int = next.inventory.get(id, 0)
		if remove and owned < quantity:
			return Result.failure("INSUFFICIENT_ITEMS", "物品数量不足：" + id)
		var count: int = owned - quantity if remove else owned + quantity
		if count > Economy.MAX_VALUE:
			return Result.failure("AMOUNT_OVERFLOW", "物品数量超出上限：" + id)
		if count == 0:
			next.inventory.erase(id)
		else:
			next.inventory[id] = count
	return Result.success({}, {"candidate": next})


func add_pill(state: Dictionary, recipe_id: String, quality: String, quantity: Variant, action_id: Variant, mutation_id: Variant = "") -> Dictionary:
	return _execute_pill(state, recipe_id, quality, quantity, action_id, mutation_id, false)


func consume_pill(state: Dictionary, recipe_id: String, quality: String, quantity: Variant, action_id: Variant, mutation_id: Variant = "") -> Dictionary:
	return _execute_pill(state, recipe_id, quality, quantity, action_id, mutation_id, true)


func _execute_pill(state: Dictionary, recipe_id: String, quality: String, quantity: Variant, action_id: Variant, mutation_id: Variant, remove: bool) -> Dictionary:
	var checked := _economy.prepare(state, action_id)
	if not checked.ok:
		return checked
	var planned := plan_pill(state, recipe_id, quality, quantity, remove, mutation_id)
	if not planned.ok:
		return planned
	return _economy.commit(state, planned.result.candidate, action_id)


func plan_pill(state: Dictionary, recipe_id: String, quality: String, quantity: Variant, remove: bool = false, mutation_id: Variant = "") -> Dictionary:
	var checked := _economy.validate_state(state)
	if not checked.ok:
		return checked
	if recipe_id not in _db.get_ids("recipes"):
		return Result.failure("UNKNOWN_RECIPE", "丹方不存在。")
	if quality not in Pills.QUALITIES:
		return Result.failure("INVALID_QUALITY", "丹药品质不合法。")
	if mutation_id != null and not (mutation_id is String and mutation_id.is_empty()):
		return Result.failure("UNSUPPORTED_MUTATION", "尚未定义此变异类型。")
	if not Economy.valid_integer(quantity):
		return Result.failure("INVALID_QUANTITY", "丹药数量须为范围内的正整数。")
	var next := state.duplicate(true)
	var key := Pills.key(recipe_id, quality)
	var owned: int = next.pills.get(key, {}).get("quantity", 0)
	if remove and owned < quantity:
		return Result.failure("INSUFFICIENT_PILLS", "该品质丹药数量不足。")
	var count: int = owned - quantity if remove else owned + quantity
	if count > Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "丹药数量超出上限。")
	if count == 0:
		next.pills.erase(key)
	else:
		next.pills[key] = Pills.create(recipe_id, quality, count)
	return Result.success({}, {"candidate": next})
