class_name ProgressionState
extends RefCounted

const Resources := preload("res://scripts/core/resource_state.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const FIELDS := ["talent_choices", "pending_talent_rank", "research_crafts", "ending"]
var resources: Resources
var db: RefCounted


func _init(content: RefCounted) -> void:
	db = content
	resources = Resources.new(content)


func create_state(seed_value: Variant = 1) -> Dictionary:
	var created := resources.create_state(seed_value)
	if created.ok:
		created.result.state.merge({"talent_choices": [], "pending_talent_rank": 0, "research_crafts": 0, "ending": {}})
	return created


func validate(state: Dictionary) -> Dictionary:
	var checked := resources.validate(state)
	if not checked.ok:
		return checked
	for field in FIELDS:
		if not state.has(field):
			return Result.failure("INVALID_STATE", "缺少成长字段：" + field)
	if not Economy.valid_integer(state.research_crafts, 0) or state.pending_talent_rank not in [0, 3, 6, 9] or not state.pending_talent_rank is int or not state.ending is Dictionary:
		return Result.failure("INVALID_STATE", "研制、天赋或结局状态不合法。")
	var groups: Array = []
	for id in state.talent_choices:
		groups.append(db.get_item(id).choice_rank)
	var pending := 0
	for rank_value in [3, 6, 9]:
		if state.rank >= rank_value and not groups.has(rank_value):
			if state.rank != rank_value or pending != 0:
				return Result.failure("INVALID_STATE", "晋升前须完成此前的天赋抉择。")
			pending = rank_value
	if pending != state.pending_talent_rank:
		return Result.failure("INVALID_STATE", "待选天赋与境界不一致。")
	if state.rank == 10:
		var ending: Dictionary = state.ending
		if ending.size() != 6 or not ending.get("id") is String or ending.get("id") != "ending_grandmaster":
			return Result.failure("INVALID_STATE", "大宗师结局记录缺失。")
		for field in ["action_count", "alchemy_attempts", "research_crafts", "quests_completed", "exp"]:
			if not Economy.valid_integer(ending.get(field), 0):
				return Result.failure("INVALID_STATE", "结局统计不合法。")
		if ending.action_count > state.action_count or ending.alchemy_attempts > state.statistics.alchemy_attempts or ending.research_crafts > state.research_crafts or ending.quests_completed > state.resource_stats.quests_completed or ending.exp > state.exp:
			return Result.failure("INVALID_STATE", "结局统计超出本世统计。")
	elif not state.ending.is_empty():
		return Result.failure("INVALID_STATE", "未通过大宗师认证，不能提前结算。")
	return Result.success()
