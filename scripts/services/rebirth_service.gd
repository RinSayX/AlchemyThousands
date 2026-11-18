class_name RebirthService
extends RefCounted
## Pure composite plans. The coordinator persists both halves before swapping.
const Profile := preload("res://scripts/core/profile_state.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Weighted := preload("res://scripts/core/exploration_rules.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var _profile: Profile


func _init(content: RefCounted) -> void:
	_profile = Profile.new(content)


func preview(run: Dictionary, meta: Dictionary) -> Dictionary:
	var checked := _profile.validate(run, meta)
	if not checked.ok:
		return checked
	var choices: Array[Dictionary] = []
	if not run.ending.is_empty() and run.heritage_reward.is_empty():
		for item in _profile.db.get_items("inheritances"):
			if item.min_completed_runs <= meta.records.size() and item.id not in meta.unlocked_inheritances:
				choices.append(item)
				if choices.size() == 3: break
	return Result.success({}, {"run_number": run.run_number, "completed": not run.ending.is_empty(), "reward_claimed": not run.heritage_reward.is_empty(), "choices": choices, "fallback_available": not run.ending.is_empty() and run.heritage_reward.is_empty() and choices.is_empty(), "slots": meta.heritage_slots, "unlocked": meta.unlocked_inheritances, "can_rebirth": not run.ending.is_empty() and not run.heritage_reward.is_empty()})


func plan_claim(run: Dictionary, meta: Dictionary, source_run: int, choice: String, action_id: Variant) -> Dictionary:
	var checked := _prepare(run, meta, source_run, action_id)
	if not checked.ok:
		return checked
	if run.ending.is_empty():
		return Result.failure("ENDING_REQUIRED", "完成大宗师结局后才可解锁传承。")
	if not run.heritage_reward.is_empty():
		return Result.failure("REWARD_ALREADY_CLAIMED", "本世传承奖励已领取，不可重选或重复领取。")
	var view := preview(run, meta)
	var offered: Array[String] = []
	for item in view.result.choices:
		offered.append(item.id)
	if choice == "legacy_insight":
		if not view.result.fallback_available:
			return Result.failure("INVALID_REWARD", "仍有新传承可选，尚不能领取替代奖励。")
		if meta.legacy_insight == Economy.MAX_VALUE:
			return Result.failure("AMOUNT_OVERFLOW", "永久心得计数达到上限。")
	elif choice not in offered:
		return Result.failure("INVALID_REWARD", "此传承不在本次候选中。")
	var next_run := run.duplicate(true)
	var next_meta := meta.duplicate(true)
	next_run.heritage_reward = choice
	next_run.completed_actions.append(action_id)
	next_run.needs_save = true
	next_meta.records[-1].reward = choice
	if choice == "legacy_insight":
		next_meta.legacy_insight += 1
	else:
		next_meta.unlocked_inheritances.append(choice)
	next_meta = _profile.sync(next_run, next_meta)
	checked = _profile.validate(next_run, next_meta)
	if not checked.ok:
		return checked
	return Result.success({}, {"state": next_run, "meta": next_meta, "reset_history": false, "reward": choice})


func preview_next(run: Dictionary, meta: Dictionary, loadout: Variant) -> Dictionary:
	var checked := _profile.validate(run, meta)
	if not checked.ok:
		return checked
	if run.ending.is_empty() or run.heritage_reward.is_empty():
		return Result.failure("REWARD_REQUIRED", "请先完成本世结局并领取一项传承奖励。")
	checked = _check_loadout(meta, loadout)
	if not checked.ok:
		return checked
	return _generate(run, meta, loadout)


func plan_rebirth(run: Dictionary, meta: Dictionary, source_run: int, loadout: Variant, action_id: Variant) -> Dictionary:
	var checked := _prepare(run, meta, source_run, action_id)
	if not checked.ok:
		return checked
	var generated := preview_next(run, meta, loadout)
	if not generated.ok:
		return generated
	var next_run: Dictionary = generated.result.state
	var next_meta := meta.duplicate(true)
	next_meta.records[-1].next_run = next_run.run_number
	checked = _profile.validate(next_run, next_meta)
	if not checked.ok:
		return checked
	return Result.success({}, {"state": next_run, "meta": next_meta, "reset_history": true, "worlds": generated.result.worlds, "seed": next_run.run_seed})


func _prepare(run: Dictionary, meta: Dictionary, source_run: int, action_id: Variant) -> Dictionary:
	var checked := _profile.validate(run, meta)
	if not checked.ok:
		return checked
	if source_run != run.run_number:
		return Result.failure("RUN_CHANGED", "周目已经变化，请重新查看轮回页面。")
	return _profile.runs.resources.economy.prepare(run, action_id)


func _check_loadout(meta: Dictionary, loadout: Variant) -> Dictionary:
	if not loadout is Array or loadout.size() > meta.heritage_slots:
		return Result.failure("INVALID_LOADOUT", "携带传承超出已解锁栏位。")
	var seen: Array = []
	for id in loadout:
		if not id is String or id not in meta.unlocked_inheritances or id in seen:
			return Result.failure("INVALID_LOADOUT", "只能携带已解锁且不重复的传承。")
		seen.append(id)
	return Result.success()


func _generate(run: Dictionary, meta: Dictionary, loadout: Array) -> Dictionary:
	if run.run_number == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "周目计数达到上限。")
	var old_rng := Context.new()
	var restored := old_rng.restore(run.rng_states)
	if not restored.ok:
		return restored
	var seed_value := int(old_rng.next_float("world") * 2147483646.0) + 1
	var rng := Context.new(seed_value)
	var number: int = run.run_number + 1
	var eligible: Array[Dictionary] = []
	for world in _profile.db.get_items("world_modifiers"):
		if world.min_run_number <= number:
			eligible.append(world)
	var opportunities: Array[Dictionary] = []
	for world in eligible:
		if not world.opportunity: continue
		for other in eligible:
			if other.id != world.id and other.id not in world.exclusive_with and world.id not in other.exclusive_with:
				opportunities.append(world)
				break
	if opportunities.is_empty():
		return Result.failure("NO_WORLD_PAIR", "没有可用的机会规则组合，原周目保留。")
	var first_id := Weighted.pick_event(opportunities, rng.next_float("world"))
	var first: Dictionary = _profile.db.get_item(first_id)
	var compatible: Array[Dictionary] = []
	for other in eligible:
		if other.id != first_id and other.id not in first.exclusive_with and first_id not in other.exclusive_with:
			compatible.append(other)
	if compatible.is_empty():
		return Result.failure("NO_WORLD_PAIR", "无法组成相容的两条世界规则。")
	var second_id := Weighted.pick_event(compatible, rng.next_float("world"))
	var created := _profile.create_run(seed_value, number, loadout, [first_id, second_id], meta.legacy_insight)
	if not created.ok:
		return created
	created.result.state.rng_states = rng.snapshot()
	return Result.success({}, {"state": created.result.state, "worlds": [first, _profile.db.get_item(second_id)]})
