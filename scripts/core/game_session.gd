class_name GameSession
extends RefCounted
## In-memory coordinator. Views receive copies and never own mutable run state.

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var content := Database.new()
var startup: Dictionary
var _alchemy: Alchemy
var _shop: Shop
var _state: Dictionary = {}
var _history: Array[Dictionary] = []
var _pending: Dictionary = {}
var _sequence := 0


func _init() -> void:
	startup = content.load_directory()
	_alchemy = Alchemy.new(content)
	_shop = Shop.new(content)


func has_run() -> bool:
	return not _state.is_empty()


func is_busy() -> bool:
	return not _pending.is_empty()


func new_run(seed_value: Variant = null) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "丹炉尚未揭晓。")
	if not startup.ok:
		return Result.failure("INVALID_CONTENT", "内容配置读取失败，请检查游戏文件。")
	var created := _alchemy.create_state(Time.get_ticks_usec() if seed_value == null else seed_value)
	if created.ok:
		_state = created.result.state.duplicate(true)
		_history.clear()
		_sequence = 0
	return created


func state() -> Dictionary:
	return _state.duplicate(true)


func history() -> Array[Dictionary]:
	return _history.duplicate(true)


func preview(recipe_id: String, setup: Dictionary) -> Dictionary:
	return _alchemy.preview_alchemy(_state, recipe_id, setup)


func begin_brew(recipe_id: String, setup: Dictionary) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "此炉正在炼制，请先揭晓结果。")
	var outcome := _alchemy.execute_alchemy(_state, recipe_id, setup, _next_id())
	if outcome.ok:
		_pending = outcome.duplicate(true)
	return outcome


func finish_brew() -> Dictionary:
	if not is_busy():
		return Result.failure("NO_PENDING_RESULT", "没有待揭晓的丹药。")
	var outcome := _pending.duplicate(true)
	_pending.clear()
	_history.push_front(outcome.result.duplicate(true))
	if _history.size() > 20:
		_history.pop_back()
	return outcome


func quote_materials(recipe_id: String, batches: int) -> Dictionary:
	return _shop.quote_buy(_state, _material_cart(recipe_id, batches))


func buy_materials(recipe_id: String, batches: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先揭晓本炉结果。")
	return _shop.buy_batch(_state, _material_cart(recipe_id, batches), _next_id())


func _material_cart(recipe_id: String, batches: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if batches < 1 or batches > 10 or recipe_id not in _state.get("unlocked_recipes", []):
		return lines
	var recipe: Dictionary = content.get_item(recipe_id)
	for id in recipe.materials:
		lines.append({"item_id": id, "quantity": recipe.materials[id] * batches})
	return lines


func quote_item(id: String) -> Dictionary:
	return _shop.quote_buy(_state, [{"item_id": id, "quantity": 1}])


func buy_item(id: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先揭晓本炉结果。")
	return _shop.buy_item(_state, id, 1, _next_id())


func quote_products() -> Dictionary:
	var lines := _product_cart()
	if lines.is_empty():
		return Result.failure("NO_PRODUCTS", "尚无可出售的丹药或丹渣。")
	return _shop.quote_sell(_state, lines)


func sell_products() -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先揭晓本炉结果。")
	var lines := _product_cart()
	if lines.is_empty():
		return Result.failure("NO_PRODUCTS", "尚无可出售的丹药或丹渣。")
	return _shop.sell_batch(_state, lines, _next_id())


func _product_cart() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for pill in _state.get("pills", {}).values():
		lines.append({"recipe_id": pill.recipe_id, "quality": pill.quality, "mutation_id": pill.mutation_id, "quantity": pill.quantity})
	var residue: int = _state.get("inventory", {}).get("material_danzha", 0)
	if residue > 0:
		lines.append({"item_id": "material_danzha", "quantity": residue})
	return lines


func _next_id() -> String:
	_sequence += 1
	while _state.get("completed_actions", []).has("session-%d" % _sequence):
		_sequence += 1
	return "session-%d" % _sequence
