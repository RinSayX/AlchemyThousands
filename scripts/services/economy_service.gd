class_name EconomyService
extends RefCounted
## Synchronous, in-memory transaction boundary. No UI, saves or RNG.

const Lineage := preload("res://scripts/core/lineage_rules.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Transaction := preload("res://scripts/core/state_transaction.gd")
const MAX_VALUE := 2147483647
const FIELDS := ["rank", "spirit_stones", "inventory", "pills", "unlocked_recipes", "owned_furnaces", "owned_flames", "completed_actions"]
const OWNERSHIP := {"unlocked_recipes": "recipes", "owned_furnaces": "furnaces", "owned_flames": "flames"}

var _db: Database


func _init(content: Database) -> void:
	_db = content


func create_economy_state() -> Dictionary:
	var state := {"rank": 0, "spirit_stones": 200, "inventory": {"herb_lingcao": 5, "herb_qinghua": 3}, "pills": {}, "unlocked_recipes": [], "owned_furnaces": [], "owned_flames": [], "completed_actions": []}
	for field in OWNERSHIP:
		for item in _db.get_items(OWNERSHIP[field]):
			if item.unlock.type == "initial":
				state[field].append(item.id)
	var checked := validate_state(state)
	if not checked.ok:
		return checked
	return Result.success({}, {"state": state})


func validate_state(state: Dictionary) -> Dictionary:
	for field in FIELDS:
		if not state.has(field):
			return Result.failure("INVALID_STATE", "缺少经济状态字段：" + field)
	if not valid_integer(state.rank, 0, 10) or not valid_integer(state.spirit_stones, 0, MAX_VALUE):
		return Result.failure("INVALID_STATE", "境界或灵石余额不合法。")
	if not state.inventory is Dictionary or not state.pills is Dictionary:
		return Result.failure("INVALID_STATE", "背包和丹药栏必须是对象。")
	for id in state.inventory:
		if not id is String or not is_stackable(id) or not valid_integer(state.inventory[id], 0, MAX_VALUE):
			return Result.failure("INVALID_STATE", "背包存在未知物品或非法数量。")
	for key in state.pills:
		var pill: Variant = state.pills[key]
		if not pill is Dictionary or pill.size() != 4:
			return Result.failure("INVALID_STATE", "丹药堆叠结构不合法。")
		if not key is String or not pill.get("recipe_id") is String or not pill.get("quality") is String or pill.get("recipe_id") not in _db.get_ids("recipes") or pill.get("quality") not in Pills.QUALITIES:
			return Result.failure("INVALID_STATE", "丹药引用或品质不合法。")
		if not pill.has("mutation_id") or not Pills.valid_mutation(pill.recipe_id, pill.mutation_id):
			return Result.failure("INVALID_STATE", "尚不支持此变异丹药。")
		if not valid_integer(pill.get("quantity"), 1, MAX_VALUE) or key != Pills.key(pill.recipe_id, pill.quality, "" if pill.mutation_id == null else pill.mutation_id):
			return Result.failure("INVALID_STATE", "丹药数量或堆叠键不合法。")
	for field in OWNERSHIP:
		if not _valid_ids(state[field], _db.get_ids(OWNERSHIP[field])):
			return Result.failure("INVALID_STATE", "装备或丹方记录不合法：" + field)
	if not state.completed_actions is Array:
		return Result.failure("INVALID_STATE", "操作记录必须是数组。")
	var seen: Dictionary = {}
	for id in state.completed_actions:
		if not valid_action_id(id) or seen.has(id):
			return Result.failure("INVALID_STATE", "操作记录存在非法或重复 ID。")
		seen[id] = true
	if not Lineage.valid_ids(_db, state):
		return Result.failure("UNSUPPORTED_RULE", "传承或世界规则引用、重复或冲突不合法。")
	return Result.success()


func prepare(state: Dictionary, action_id: Variant) -> Dictionary:
	var checked := validate_state(state)
	if not checked.ok:
		return checked
	if not valid_action_id(action_id):
		return Result.failure("INVALID_ACTION_ID", "操作 ID 必须为 1～128 字符的非空文本。")
	if state.completed_actions.has(action_id):
		return Result.failure("ACTION_DUPLICATE", "此操作已结算，请勿重复提交。")
	return Result.success({}, {"candidate": state})


func commit(state: Dictionary, candidate: Dictionary, action_id: Variant, payload: Dictionary = {}) -> Dictionary:
	var checked := prepare(state, action_id)
	if not checked.ok:
		return checked
	checked = validate_state(candidate)
	if not checked.ok:
		return checked
	if candidate.rank != state.rank or candidate.completed_actions != state.completed_actions:
		return Result.failure("INVALID_STATE", "经济事务不能修改境界或既有操作记录。")
	var next := candidate.duplicate(true)
	next.completed_actions.append(action_id)
	var fields: Array = FIELDS.duplicate()
	if state.get("needs_save") is bool:
		next.needs_save = true
		fields.append("needs_save")
	return Transaction.commit(state, next, fields, payload)


func change_stones(state: Dictionary, delta: Variant, action_id: Variant) -> Dictionary:
	var prepared := prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if not valid_integer(delta, -MAX_VALUE, MAX_VALUE) or delta == 0:
		return Result.failure("INVALID_AMOUNT", "灵石变动必须为非零整数，且不超过数量上限。")
	var next: Dictionary = prepared.result.candidate
	var balance: int = next.spirit_stones + delta
	if balance < 0:
		return Result.failure("NOT_ENOUGH_STONES", "灵石不足。")
	if balance > MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "灵石余额超出上限。")
	next.spirit_stones = balance
	return commit(state, next, action_id, {"spirit_stones_delta": delta})


func is_stackable(id: String) -> bool:
	return id in _db.get_ids("materials") or id in _db.get_ids("consumables")


static func valid_integer(value: Variant, minimum: int = 1, maximum: int = MAX_VALUE) -> bool:
	return value is int and value >= minimum and value <= maximum


static func valid_action_id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 128


func _valid_ids(value: Variant, allowed: Array) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for id in value:
		if not id is String or id not in allowed or seen.has(id):
			return false
		seen[id] = true
	return true
