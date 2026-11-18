class_name ShopService
extends RefCounted
## Authoritative quotes and all-or-nothing carts. Execution always requotes.

const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const QUALITY_NUMERATORS := {"common": 2, "good": 3, "superior": 5, "legendary": 12}
const MAX_CART_LINES := 128

var _db: Database
var _economy: Economy
var _inventory: Inventory


func _init(content: Database) -> void:
	_db = content
	_economy = Economy.new(content)
	_inventory = Inventory.new(content)


func quote_buy(state: Dictionary, lines: Variant) -> Dictionary:
	return _quote(_plan(state, lines, true))


func quote_sell(state: Dictionary, lines: Variant) -> Dictionary:
	return _quote(_plan(state, lines, false))


func buy_item(state: Dictionary, item_id: String, quantity: Variant, action_id: Variant) -> Dictionary:
	return buy_batch(state, [{"item_id": item_id, "quantity": quantity}], action_id)


func sell_item(state: Dictionary, item_id: String, quantity: Variant, action_id: Variant) -> Dictionary:
	return sell_batch(state, [{"item_id": item_id, "quantity": quantity}], action_id)


func sell_pill(state: Dictionary, recipe_id: String, quality: String, quantity: Variant, action_id: Variant, mutation_id: Variant = "") -> Dictionary:
	return sell_batch(state, [{"recipe_id": recipe_id, "quality": quality, "quantity": quantity, "mutation_id": mutation_id}], action_id)


func buy_batch(state: Dictionary, lines: Variant, action_id: Variant) -> Dictionary:
	return _execute(state, lines, action_id, true)


func sell_batch(state: Dictionary, lines: Variant, action_id: Variant) -> Dictionary:
	return _execute(state, lines, action_id, false)


func _execute(state: Dictionary, lines: Variant, action_id: Variant, buying: bool) -> Dictionary:
	var checked := _economy.prepare(state, action_id)
	if not checked.ok:
		return checked
	var planned := _plan(state, lines, buying)
	if not planned.ok:
		return planned
	return _economy.commit(state, planned.result.candidate, action_id, _quote(planned).result)


func _quote(planned: Dictionary) -> Dictionary:
	if not planned.ok:
		return planned
	var payload: Dictionary = planned.result.duplicate(true)
	payload.erase("candidate")
	return Result.success({}, payload)


func _plan(state: Dictionary, lines: Variant, buying: bool) -> Dictionary:
	var checked := _economy.validate_state(state)
	if not checked.ok:
		return checked
	if not lines is Array or lines.is_empty() or lines.size() > MAX_CART_LINES:
		return Result.failure("INVALID_CART", "交易清单须包含 1～128 行商品。")
	var next := state.duplicate(true)
	var quotes: Array[Dictionary] = []
	var total := 0
	for line in lines:
		if not line is Dictionary or not Economy.valid_integer(line.get("quantity")):
			return Result.failure("INVALID_QUANTITY", "每行交易数量须为范围内的正整数。")
		var planned := _buy_line(next, line) if buying else _sell_line(next, line)
		if not planned.ok:
			return planned
		var unit: int = planned.result.unit_price
		if unit > Economy.MAX_VALUE:
			return Result.failure("AMOUNT_OVERFLOW", "商品单价超过灵石上限。")
		# Each operand is <= 2^31-1, so the product fits int64 before this check.
		var subtotal: int = unit * line.quantity
		if subtotal > Economy.MAX_VALUE or total + subtotal > Economy.MAX_VALUE:
			return Result.failure("AMOUNT_OVERFLOW", "交易总价超出上限。")
		total += subtotal
		next = planned.result.candidate
		var row: Dictionary = line.duplicate(true)
		row["unit_price"] = unit
		row["subtotal"] = subtotal
		quotes.append(row)
	if buying and state.spirit_stones < total:
		return Result.failure("NOT_ENOUGH_STONES", "灵石不足，交易未发生。")
	if not buying and state.spirit_stones + total > Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "出售后的灵石余额超出上限。")
	var delta := -total if buying else total
	next.spirit_stones += delta
	return Result.success({}, {"candidate": next, "total": total, "spirit_stones_delta": delta, "balance_after": next.spirit_stones, "lines": quotes})


func _buy_line(state: Dictionary, line: Dictionary) -> Dictionary:
	if not _fields(line, ["item_id", "quantity"]) or not line.item_id is String:
		return Result.failure("INVALID_CART", "购买行须包含 item_id 和 quantity。")
	var item: Dictionary = _db.get_item(line.item_id)
	if item.is_empty():
		return Result.failure("UNKNOWN_ITEM", "商品不存在。")
	var is_material: bool = line.item_id in _db.get_ids("materials")
	var is_consumable: bool = line.item_id in _db.get_ids("consumables")
	var unit := 0
	if is_material:
		if not item.shop_available or item.unlock.type not in ["initial", "rank", "shop"]:
			return Result.failure("NOT_FOR_SALE", "此材料不可在商店购买。")
		unit = item.buy_price
	else:
		if item.unlock.type != "shop" or (is_consumable and not item.shop_available):
			return Result.failure("NOT_FOR_SALE", "此物品不可在商店购买。")
		unit = item.unlock.price
	if state.rank < item.unlock.get("required_rank", 0):
		return Result.failure("RANK_LOCKED", "境界不足，商品尚未开放。")
	if is_material or is_consumable:
		var planned := _inventory.plan_items(state, {line.item_id: line.quantity})
		if not planned.ok:
			return planned
		return Result.success({}, {"candidate": planned.result.candidate, "unit_price": unit})
	if line.quantity != 1:
		return Result.failure("INVALID_QUANTITY", "永久丹方或装备每次只能购买一件。")
	var next := state.duplicate(true)
	for field in Economy.OWNERSHIP:
		if line.item_id in _db.get_ids(Economy.OWNERSHIP[field]):
			if next[field].has(line.item_id):
				return Result.failure("ALREADY_OWNED", "已拥有此丹方或装备。")
			next[field].append(line.item_id)
			return Result.success({}, {"candidate": next, "unit_price": unit})
	return Result.failure("NOT_FOR_SALE", "不支持购买此类商品。")


@warning_ignore("integer_division")
func _sell_line(state: Dictionary, line: Dictionary) -> Dictionary:
	if line.has("item_id"):
		if not _fields(line, ["item_id", "quantity"]) or not line.item_id is String:
			return Result.failure("INVALID_CART", "普通出售行须包含 item_id 和 quantity。")
		if not _db.has_item(line.item_id):
			return Result.failure("UNKNOWN_ITEM", "物品不存在。")
		if not _economy.is_stackable(line.item_id):
			return Result.failure("NOT_SELLABLE", "永久丹方和装备不能出售。")
		var planned := _inventory.plan_items(state, {line.item_id: line.quantity}, true)
		if not planned.ok:
			return planned
		return Result.success({}, {"candidate": planned.result.candidate, "unit_price": _db.get_item(line.item_id).sell_price})
	if not _fields(line, ["recipe_id", "quality", "quantity"], ["mutation_id"]) or not line.recipe_id is String or not line.quality is String:
		return Result.failure("INVALID_CART", "丹药出售行的丹方、品质或数量字段不合法。")
	var planned := _inventory.plan_pill(state, line.recipe_id, line.quality, line.quantity, true, line.get("mutation_id", ""))
	if not planned.ok:
		return planned
	# Round down per pill before multiplying quantity: batch and singles agree.
	var unit: int = _db.get_item(line.recipe_id).base_sell_price * QUALITY_NUMERATORS[line.quality] / 2
	return Result.success({}, {"candidate": planned.result.candidate, "unit_price": unit})


func _fields(value: Dictionary, required: Array, optional: Array = []) -> bool:
	for field in required:
		if not value.has(field):
			return false
	for field in value:
		if field not in required and field not in optional:
			return false
	return true
