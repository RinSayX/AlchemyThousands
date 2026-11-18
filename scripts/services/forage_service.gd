class_name ForageService
extends RefCounted

const State := preload("res://scripts/core/resource_state.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var _state: State


func _init(content: Database) -> void:
	_state = State.new(content)


func preview(state: Dictionary) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	var needed: Dictionary = {}
	var recipe: Dictionary = _state.db.get_item("recipe_juling")
	if recipe.is_empty() or recipe.id not in state.unlocked_recipes or recipe.required_rank > state.rank:
		return Result.failure("RECOVERY_UNAVAILABLE", "基础丹方不可用，无法建立恢复路线。")
	for id in recipe.materials:
		var missing: int = recipe.materials[id] - state.inventory.get(id, 0)
		if missing > 0:
			needed[id] = missing
	return Result.success({}, {"items": needed, "charges_left": 3 - state.forage_uses, "can_forage": not needed.is_empty() and state.forage_uses < 3, "can_rest": state.forage_uses == 3, "has_basic_materials": needed.is_empty(), "recovery_available": true})


func forage(state: Dictionary, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	var view := preview(state)
	if not view.ok:
		return view
	if view.result.charges_left == 0:
		return Result.failure("FORAGE_EXHAUSTED", "本趟采药次数已用尽，可免费休整后再来。")
	if view.result.items.is_empty():
		return Result.failure("FORAGE_NOT_NEEDED", "已有一炉聚灵丹药材，无需再取补给。")
	var granted := _state.reward(prepared.result.candidate, view.result.items)
	if not granted.ok:
		return granted
	var next: Dictionary = granted.result.candidate
	next.forage_uses += 1
	var counted := _state.count_action(next, "forages")
	if not counted.ok:
		return counted
	return _state.commit(state, next, action_id, {"items": view.result.items, "charges_left": 3 - next.forage_uses})


func rest(state: Dictionary, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if state.forage_uses != 3:
		return Result.failure("REST_NOT_NEEDED", "本趟仍有采药机会。")
	var next: Dictionary = prepared.result.candidate
	next.forage_uses = 0
	var counted := _state.count_action(next, "rests")
	if not counted.ok:
		return counted
	return _state.commit(state, next, action_id, {"charges_left": 3})
