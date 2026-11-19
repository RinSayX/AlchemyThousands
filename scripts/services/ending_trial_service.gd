extends RefCounted
## Optional certification and deterministic post-game study. Pure composite plans.
const Spec := preload("res://scripts/core/ending_trial_definition.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var profile: RefCounted
var startup: Dictionary
var definition: Dictionary = {}

func _init(db: RefCounted) -> void:
	profile = Profile.new(db)
	startup = Spec.read(db)
	if startup.ok: definition = startup.result.definition

func preview(run: Dictionary, meta: Dictionary) -> Dictionary:
	var checked: Dictionary = _check(run, meta)
	if not checked.ok: return checked
	var requirements: Array = []
	var missing: Dictionary = {}
	for item in definition.requirements:
		var key := Pills.key(item.recipe_id, item.quality)
		var owned: int = run.pills.get(key, {}).get("quantity", 0)
		if owned < item.quantity: missing[key] = item.quantity - owned
		requirements.append({"recipe_id": item.recipe_id, "quality": item.quality, "quantity": item.quantity, "owned": owned})
	var completed := false
	for record in meta.records:
		if record.run_number == run.run_number:
			for ending in record.get("optional_endings", []):
				if ending.id == definition.id: completed = true
	var available: bool = run.rank >= definition.required_rank and not run.ending.is_empty()
	return Result.success({}, {"definition": definition, "run_number": run.run_number, "completed": completed, "available": available, "can_certify": available and not completed and missing.is_empty(), "requirements": requirements, "missing": missing})

func preview_study(run: Dictionary, meta: Dictionary, recipe_id: String) -> Dictionary:
	var checked: Dictionary = _check(run, meta)
	if not checked.ok: return checked
	for rule in definition.study:
		if rule.recipe_id != recipe_id: continue
		var costs: Dictionary = {}
		var missing: Dictionary = {}
		for id in profile.db.get_item(recipe_id).materials:
			costs[id] = profile.db.get_item(recipe_id).materials[id] * rule.material_multiplier
			if run.inventory.get(id, 0) < costs[id]: missing[id] = costs[id] - run.inventory.get(id, 0)
		var available: bool = run.rank >= definition.required_rank and not run.ending.is_empty() and recipe_id in run.unlocked_recipes
		return Result.success({}, {"recipe_id": recipe_id, "quality": "legendary", "quantity": 1, "cost_items": costs, "research_cost": rule.research_cost, "missing_items": missing, "missing_points": maxi(rule.research_cost - run.research_points, 0), "available": available, "can_execute": available and missing.is_empty() and run.research_points >= rule.research_cost})
	return Result.failure("UNKNOWN_ENDING_RECIPE", "此丹方不在神丹精研范围内。")

func plan_study(run: Dictionary, meta: Dictionary, source_run: int, recipe_id: String, action_id: Variant) -> Dictionary:
	var prepared := _prepare(run, meta, source_run, action_id)
	if not prepared.ok: return prepared
	var view := preview_study(run, meta, recipe_id)
	if not view.ok: return view
	var plan: Dictionary = view.result
	if not plan.available: return Result.failure("ENDING_STUDY_LOCKED", "先完成大宗师认证并习得此丹方，才可精研。")
	if plan.missing_points > 0: return Result.failure("INSUFFICIENT_RESEARCH", "研究心得不足，未扣除任何材料。")
	if not plan.missing_items.is_empty(): return Result.failure("INSUFFICIENT_ITEMS", "精研材料不足，未扣除研究心得。")
	var spent: Dictionary = profile.runs.resources.inventory.plan_items(prepared.result.candidate, plan.cost_items, true)
	if not spent.ok: return spent
	var granted: Dictionary = profile.runs.resources.inventory.plan_pill(spent.result.candidate, recipe_id, "legendary", 1)
	if not granted.ok: return granted
	var next: Dictionary = granted.result.candidate
	var exp_value: int = profile.db.get_item(recipe_id).tier * 10
	if next.action_count == Economy.MAX_VALUE or next.research_crafts == Economy.MAX_VALUE or next.exp > Economy.MAX_VALUE - exp_value:
		return Result.failure("AMOUNT_OVERFLOW", "精研次数或历练超出上限。")
	next.research_points -= plan.research_cost
	next.exp += exp_value
	next.research_crafts += 1
	next.action_count += 1
	var key := Pills.key(recipe_id, "legendary")
	if key not in next.alchemy_discoveries: next.alchemy_discoveries.append(key)
	return _finish(next, meta, action_id, {"study": plan})

func plan_certify(run: Dictionary, meta: Dictionary, source_run: int, action_id: Variant) -> Dictionary:
	var prepared := _prepare(run, meta, source_run, action_id)
	if not prepared.ok: return prepared
	var view := preview(run, meta)
	if not view.result.available: return Result.failure("ENDING_REQUIRED", "先完成大宗师标准结局。")
	if view.result.completed: return Result.failure("ENDING_ALREADY_CERTIFIED", "本世已认证九转丹圣，不会重复扣丹或领奖。")
	if not view.result.missing.is_empty(): return Result.failure("INSUFFICIENT_PILLS", "请备齐本世所需的极品神丹。")
	var next: Dictionary = prepared.result.candidate
	var consumed: Dictionary = {}
	for item in definition.requirements:
		var planned: Dictionary = profile.runs.resources.inventory.plan_pill(next, item.recipe_id, item.quality, item.quantity, true)
		if not planned.ok: return planned
		next = planned.result.candidate
		consumed[Pills.key(item.recipe_id, item.quality)] = item.quantity
	if next.action_count == Economy.MAX_VALUE: return Result.failure("AMOUNT_OVERFLOW", "行动数达到上限。")
	next.action_count += 1
	var archive := {"id": definition.id, "action_count": next.action_count, "alchemy_attempts": next.statistics.alchemy_attempts, "research_crafts": next.research_crafts, "quests_completed": next.resource_stats.quests_completed, "exp": next.exp, "consumed": consumed}
	var permanent := meta.duplicate(true)
	if not permanent.records[-1].has("optional_endings"): permanent.records[-1]["optional_endings"] = []
	permanent.records[-1].optional_endings.append(archive)
	return _finish(next, permanent, action_id, {"certified": archive})

func _check(run: Dictionary, meta: Dictionary) -> Dictionary:
	if not startup.ok: return startup
	return profile.validate(run, meta)

func _prepare(run: Dictionary, meta: Dictionary, source_run: int, action_id: Variant) -> Dictionary:
	var checked := _check(run, meta)
	if not checked.ok: return checked
	if source_run != run.run_number: return Result.failure("RUN_CHANGED", "周目已变化，请重新查看特殊结局。")
	return profile.runs.resources.prepare(run, action_id)

func _finish(run: Dictionary, meta: Dictionary, action_id: Variant, payload: Dictionary) -> Dictionary:
	run.completed_actions.append(action_id)
	run.needs_save = true
	var permanent: Dictionary = profile.sync(run, meta)
	var checked: Dictionary = profile.validate(run, permanent)
	if not checked.ok: return checked
	var result := {"state": run, "meta": permanent, "reset_history": false}
	result.merge(payload)
	return Result.success({}, result)
