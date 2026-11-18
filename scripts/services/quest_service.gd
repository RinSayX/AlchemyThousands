class_name QuestService
extends RefCounted

const Lineage := preload("res://scripts/core/lineage_rules.gd")
const State := preload("res://scripts/core/resource_state.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var _state: State


func _init(content: Database) -> void:
	_state = State.new(content)


func board(state: Dictionary) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	var rows: Array[Dictionary] = []
	for source in _state.db.get_items("quests"):
		var template := Lineage.quest(_state.db, state, source)
		var active := ""
		var completed := false
		for id in state.quest_instances:
			var instance: Dictionary = state.quest_instances[id]
			if instance.template_id == template.id:
				if instance.status == "active":
					active = id
				else:
					completed = true
		var unlocked: bool = state.rank >= template.unlock.required_rank and template.required_recipe_id in state.unlocked_recipes
		var delivery: Dictionary = preview_delivery(state, active).result if not active.is_empty() else {}
		rows.append({"template": template, "active_id": active, "completed": completed, "can_accept": unlocked and active.is_empty() and (template.repeatable or not completed), "delivery": delivery})
	return Result.success({}, {"rows": rows})


func accept(state: Dictionary, template_id: String, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if template_id not in _state.db.get_ids("quests"):
		return Result.failure("UNKNOWN_QUEST", "委托模板不存在。")
	var template: Dictionary = _state.db.get_item(template_id)
	if state.rank < template.unlock.required_rank or template.required_recipe_id not in state.unlocked_recipes:
		return Result.failure("QUEST_LOCKED", "请先达到境界并习得所需丹方。")
	for instance in state.quest_instances.values():
		if instance.template_id == template_id and (instance.status == "active" or not template.repeatable):
			return Result.failure("QUEST_UNAVAILABLE", "同类委托已接受，或一次性委托已完成。")
	if state.quest_serial == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "委托序号超出上限。")
	var next: Dictionary = prepared.result.candidate
	next.quest_serial += 1
	var id := "quest_run_%d" % next.quest_serial
	next.quest_instances[id] = {"template_id": template_id, "status": "active", "serial": next.quest_serial}
	return _state.commit(state, next, action_id, {"instance_id": id, "template_id": template_id})


func preview_delivery(state: Dictionary, instance_id: String) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	if not state.quest_instances.has(instance_id):
		return Result.failure("UNKNOWN_QUEST", "委托实例不存在。")
	var instance: Dictionary = state.quest_instances[instance_id]
	if instance.status != "active":
		return Result.failure("QUEST_ALREADY_COMPLETED", "此委托已经交付并领奖。")
	var template := Lineage.quest(_state.db, state, _state.db.get_item(instance.template_id))
	var remaining: int = template.quantity
	var consumed: Dictionary = {}
	for quality in Pills.QUALITIES:
		if Pills.QUALITIES.find(quality) < Pills.QUALITIES.find(template.min_quality):
			continue
		var key := Pills.key(template.required_recipe_id, quality)
		var owned: int = state.pills.get(key, {}).get("quantity", 0)
		var take := mini(owned, remaining)
		if take > 0:
			consumed[key] = take
			remaining -= take
	return Result.success({}, {"can_deliver": remaining == 0, "missing": remaining, "consumed": consumed, "template": template})


func deliver(state: Dictionary, instance_id: String, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	var preview := preview_delivery(state, instance_id)
	if not preview.ok:
		return preview
	if not preview.result.can_deliver:
		return Result.failure("INSUFFICIENT_PILLS", "符合品质的丹药不足，交付未发生。")
	var next: Dictionary = prepared.result.candidate
	for key in preview.result.consumed:
		next.pills[key].quantity -= preview.result.consumed[key]
		if next.pills[key].quantity == 0:
			next.pills.erase(key)
	var template: Dictionary = preview.result.template
	var granted := _state.reward(next, template.reward_items, template.reward_spirit_stones, template.reward_exp, template.reward_flame)
	if not granted.ok:
		return granted
	next = granted.result.candidate
	next.quest_instances[instance_id].status = "completed"
	var counted := _state.count_action(next, "quests_completed")
	if not counted.ok:
		return counted
	return _state.commit(state, next, action_id, {"instance_id": instance_id, "consumed": preview.result.consumed, "items": template.reward_items, "spirit_stones": template.reward_spirit_stones, "exp": template.reward_exp, "flame": template.reward_flame})
