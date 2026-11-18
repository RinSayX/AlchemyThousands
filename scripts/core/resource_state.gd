class_name ResourceState
extends RefCounted
## Shared P5 validation/reward/commit boundary; services never mutate input plans.

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Transaction := preload("res://scripts/core/state_transaction.gd")
const FIELDS := ["quest_instances", "quest_serial", "pending_exploration", "exploration_serial", "forage_uses", "resource_stats"]
const STATS := ["forages", "rests", "explorations", "quests_completed"]
var db: Database
var alchemy: Alchemy
var economy: Economy
var inventory: Inventory


func _init(content: Database) -> void:
	db = content
	alchemy = Alchemy.new(content)
	economy = Economy.new(content)
	inventory = Inventory.new(content)


func create_state(seed_value: Variant) -> Dictionary:
	var created := alchemy.create_state(seed_value)
	if not created.ok:
		return created
	var state: Dictionary = created.result.state
	state.merge({"quest_instances": {}, "quest_serial": 0, "pending_exploration": {}, "exploration_serial": 0, "forage_uses": 0, "resource_stats": {"forages": 0, "rests": 0, "explorations": 0, "quests_completed": 0}})
	return Result.success({}, {"state": state})


func validate(state: Dictionary) -> Dictionary:
	var checked := alchemy.validate_state(state)
	if not checked.ok:
		return checked
	for field in FIELDS:
		if not state.has(field):
			return Result.failure("INVALID_STATE", "缺少资源状态：" + field)
	for field in ["quest_serial", "exploration_serial", "forage_uses"]:
		if not Economy.valid_integer(state[field], 0):
			return Result.failure("INVALID_STATE", "资源计数不合法。")
	if state.forage_uses > 3 or not state.resource_stats is Dictionary:
		return Result.failure("INVALID_STATE", "采药次数或资源统计不合法。")
	for field in STATS:
		if not Economy.valid_integer(state.resource_stats.get(field), 0):
			return Result.failure("INVALID_STATE", "资源统计不合法：" + field)
	if not state.quest_instances is Dictionary or not state.pending_exploration is Dictionary:
		return Result.failure("INVALID_STATE", "委托或事件结构不合法。")
	var active: Dictionary = {}
	var single: Dictionary = {}
	for id in state.quest_instances:
		var quest: Variant = state.quest_instances[id]
		if not id is String or not quest is Dictionary or quest.size() != 3 or not quest.get("template_id") is String or quest.get("template_id") not in db.get_ids("quests") or quest.get("status") not in ["active", "completed"] or not Economy.valid_integer(quest.get("serial"), 1, state.quest_serial):
			return Result.failure("INVALID_STATE", "委托实例引用或状态不合法。")
		if id != "quest_run_%d" % quest.serial:
			return Result.failure("INVALID_STATE", "委托实例标识不一致。")
		if quest.status == "active":
			if active.has(quest.template_id):
				return Result.failure("INVALID_STATE", "同类委托不能同时重复接受。")
			active[quest.template_id] = true
		if not db.get_item(quest.template_id).repeatable:
			if single.has(quest.template_id):
				return Result.failure("INVALID_STATE", "一次性委托存在多个实例。")
			single[quest.template_id] = true
	var pending: Dictionary = state.pending_exploration
	if not pending.is_empty():
		if pending.size() != 3 or not pending.get("instance_id") is String or not pending.get("event_id") is String or pending.get("event_id") not in db.get_ids("exploration_events") or not Economy.valid_integer(pending.get("serial"), 1, state.exploration_serial) or pending.get("instance_id") != "event_run_%d" % pending.serial:
			return Result.failure("INVALID_STATE", "当前秘境实例不合法。")
	return Result.success()


func prepare(state: Dictionary, action_id: Variant, allow_pending: bool = false) -> Dictionary:
	var checked := validate(state)
	if not checked.ok:
		return checked
	if not allow_pending and not state.pending_exploration.is_empty():
		return Result.failure("EVENT_PENDING", "请先选择当前秘境行动，或离开事件。")
	return economy.prepare(state, action_id)


func reward(candidate: Dictionary, items: Dictionary, stones: int = 0, exp: int = 0, flame: String = "") -> Dictionary:
	var next := candidate.duplicate(true)
	if not items.is_empty():
		var granted := inventory.plan_items(next, items)
		if not granted.ok:
			return granted
		next = granted.result.candidate
	if next.spirit_stones > Economy.MAX_VALUE - stones or next.exp > Economy.MAX_VALUE - exp:
		return Result.failure("AMOUNT_OVERFLOW", "奖励超出灵石或经验上限。")
	next.spirit_stones += stones
	next.exp += exp
	if not flame.is_empty() and not next.owned_flames.has(flame):
		next.owned_flames.append(flame)
	return Result.success({}, {"candidate": next})


func commit(state: Dictionary, candidate: Dictionary, action_id: Variant, payload: Dictionary = {}) -> Dictionary:
	var checked := economy.prepare(state, action_id)
	if not checked.ok:
		return checked
	var next := candidate.duplicate(true)
	if next.completed_actions != state.completed_actions or next.rank != state.rank:
		return Result.failure("INVALID_STATE", "资源事务不能修改境界或历史记录。")
	next.completed_actions.append(action_id)
	next.needs_save = true
	checked = validate(next)
	if not checked.ok:
		return checked
	return Transaction.commit(state, next, Economy.FIELDS + Alchemy.FIELDS + FIELDS, payload)


func count_action(next: Dictionary, stat: String) -> Dictionary:
	if next.action_count == Economy.MAX_VALUE or next.resource_stats[stat] == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "行动或统计次数超出上限。")
	next.action_count += 1
	next.resource_stats[stat] += 1
	return Result.success()
