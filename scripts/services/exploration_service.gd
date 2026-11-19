class_name ExplorationService
extends RefCounted

const Lineage := preload("res://scripts/core/lineage_rules.gd")
const State := preload("res://scripts/core/resource_state.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/exploration_rules.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var _state: State


func _init(content: Database) -> void:
	_state = State.new(content)


func destinations(state: Dictionary) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	var rows: Array[Dictionary] = []
	var total := 0.0
	for event in _state.db.get_items("exploration_events"):
		if _available(state, event):
			total += event.weight
	for event in _state.db.get_items("exploration_events"):
		var unlocked := _available(state, event)
		rows.append({"event": event, "unlocked": unlocked, "completed": _completed(state, event), "encounter_probability": event.weight / total if unlocked and total > 0 else 0.0})
	return Result.success({}, {"rows": rows, "pending": state.pending_exploration})


func enter(state: Dictionary, action_id: Variant, event_id: String = "") -> Dictionary:
	var prepared := _state.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	var eligible: Array[Dictionary] = []
	for event in _state.db.get_items("exploration_events"):
		if _available(state, event):
			eligible.append(event)
	if eligible.is_empty():
		return Result.failure("NO_EVENT", "没有开放的秘境。")
	var next: Dictionary = prepared.result.candidate
	if event_id.is_empty():
		var rng := Context.new()
		var restored := rng.restore(state.rng_states)
		if not restored.ok:
			return restored
		event_id = Rules.pick_event(eligible, rng.next_float("exploration"))
		next.rng_states = rng.snapshot()
	elif event_id not in _state.db.get_ids("exploration_events"):
		return Result.failure("UNKNOWN_EVENT", "秘境不存在。")
	elif state.rank < _state.db.get_item(event_id).unlock.required_rank:
		return Result.failure("RANK_LOCKED", "境界不足，秘境尚未开放。")
	elif not _available(state, _state.db.get_item(event_id)):
		return Result.failure("EVENT_EXHAUSTED", "此处试炼奖励已取得，或当前尚不满足选项条件。")
	if next.exploration_serial == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "秘境序号超出上限。")
	next.exploration_serial += 1
	var id := "event_run_%d" % next.exploration_serial
	next.pending_exploration = {"instance_id": id, "event_id": event_id, "serial": next.exploration_serial}
	var counted := _state.count_action(next, "explorations")
	if not counted.ok:
		return counted
	return _state.commit(state, next, action_id, {"instance_id": id, "event": _state.db.get_item(event_id)})


func preview_option(state: Dictionary, instance_id: String, option_id: String) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	if state.pending_exploration.is_empty() or state.pending_exploration.instance_id != instance_id:
		return Result.failure("EVENT_CHANGED", "事件已结束或发生变化，请重新查看。")
	var event: Dictionary = _state.db.get_item(state.pending_exploration.event_id)
	for source in event.options:
		if source.id != option_id:
			continue
		if not source.get("required_heritage", "").is_empty() and source.required_heritage not in state.get("equipped_inheritances", []):
			return Result.failure("OPTION_LOCKED", "此秘境选项需要携带对应传承。")
		if _claimed(state, source):
			return Result.failure("REWARD_ALREADY_OWNED", "此试炼奖励已持有，不会再次扣除材料或灵石。")
		var option := Lineage.option(_state.db, state, event.id, source)
		var can_pay: bool = state.spirit_stones >= option.cost_stones
		var missing: Dictionary = {}
		for id in option.cost_items:
			var deficit: int = option.cost_items[id] - state.inventory.get(id, 0)
			if deficit > 0:
				missing[id] = deficit
		return Result.success({}, {"option": option, "can_execute": can_pay and missing.is_empty(), "missing_items": missing, "missing_stones": maxi(option.cost_stones - state.spirit_stones, 0)})
	return Result.failure("UNKNOWN_OPTION", "事件选项不存在。")


func resolve(state: Dictionary, instance_id: String, option_id: String, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id, true)
	if not prepared.ok:
		return prepared
	var view := preview_option(state, instance_id, option_id)
	if not view.ok:
		return view
	if view.result.missing_stones > 0:
		return Result.failure("NOT_ENOUGH_STONES", "灵石不足，未执行秘境行动。")
	if not view.result.missing_items.is_empty():
		return Result.failure("INSUFFICIENT_ITEMS", "秘境行动所需物品不足。")
	var option: Dictionary = view.result.option
	var next: Dictionary = prepared.result.candidate
	if not option.cost_items.is_empty():
		var spent := _state.inventory.plan_items(next, option.cost_items, true)
		if not spent.ok:
			return spent
		next = spent.result.candidate
	next.spirit_stones -= option.cost_stones
	var success: bool = option.success_rate >= 1.0
	if option.success_rate > 0 and option.success_rate < 1:
		var rng := Context.new()
		var restored := rng.restore(state.rng_states)
		if not restored.ok:
			return restored
		success = Rules.succeeds(option.success_rate, rng.next_float("exploration"))
		next.rng_states = rng.snapshot()
	var items: Dictionary = option.success_items if success else option.failure_items
	var stones: int = option.success_stones if success else option.failure_stones
	var flame: String = option.reward_flame if success else ""
	var furnace: String = option.get("reward_furnace", "") if success else ""
	var granted := _state.reward(next, items, stones, 0, flame, furnace)
	if not granted.ok:
		return granted
	next = granted.result.candidate
	next.pending_exploration = {}
	return _state.commit(state, next, action_id, {"instance_id": instance_id, "success": success, "items": items, "spirit_stones": stones, "flame": flame, "furnace": furnace, "cost_stones": option.cost_stones, "cost_items": option.cost_items})


func leave(state: Dictionary, instance_id: String, action_id: Variant) -> Dictionary:
	var prepared := _state.prepare(state, action_id, true)
	if not prepared.ok:
		return prepared
	if state.pending_exploration.is_empty() or state.pending_exploration.instance_id != instance_id:
		return Result.failure("EVENT_CHANGED", "当前没有此事件。")
	var next: Dictionary = prepared.result.candidate
	next.pending_exploration = {}
	return _state.commit(state, next, action_id, {"left": true, "instance_id": instance_id})


func _claimed(state: Dictionary, option: Dictionary) -> bool:
	if not option.get("requires_unowned_reward", false): return false
	return option.get("reward_flame", "") in state.owned_flames or option.get("reward_furnace", "") in state.owned_furnaces


func _available(state: Dictionary, event: Dictionary) -> bool:
	if state.rank < event.unlock.required_rank: return false
	for option in event.options:
		if _claimed(state, option): continue
		if option.get("required_heritage", "") != "" and option.required_heritage not in state.get("equipped_inheritances", []): continue
		return true
	return false


func _completed(state: Dictionary, event: Dictionary) -> bool:
	for option in event.options:
		if not _claimed(state, option): return false
	return true
