class_name ProgressionService
extends RefCounted

const State := preload("res://scripts/core/progression_state.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Resources := preload("res://scripts/core/resource_state.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Talents := preload("res://scripts/core/talent_rules.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Transaction := preload("res://scripts/core/state_transaction.gd")
var _state: State


func _init(content: RefCounted) -> void:
	_state = State.new(content)


func rank_definition(index: int) -> Dictionary:
	for rank_item in _state.db.get_items("ranks"):
		if rank_item.rank_index == index:
			return rank_item
	return {}


func preview(state: Dictionary) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	var talents: Array[Dictionary] = []
	for talent in _state.db.get_items("talents"):
		if talent.choice_rank == state.pending_talent_rank:
			talents.append(talent)
	if state.rank == 10:
		return Result.success({}, {"current": rank_definition(10), "next": {}, "can_promote": false, "talents": talents, "ending": state.ending})
	var target := rank_definition(state.rank + 1)
	var consumed: Dictionary = {}
	var remaining: int = target.quantity
	var discovered := false
	for quality in Pills.QUALITIES:
		var key := Pills.key(target.exam_recipe_id, quality)
		if state.alchemy_discoveries.has(key):
			discovered = true
		if Pills.QUALITIES.find(quality) < Pills.QUALITIES.find(target.min_quality):
			continue
		var take := mini(state.pills.get(key, {}).get("quantity", 0), remaining)
		if take > 0:
			consumed[key] = take
			remaining -= take
	var quest_done: bool = target.required_quest_id.is_empty()
	for instance in state.quest_instances.values():
		if instance.template_id == target.required_quest_id and instance.status == "completed":
			quest_done = true
	var flame_done: bool = target.required_flame.is_empty() or state.owned_flames.has(target.required_flame)
	var learned: bool = target.exam_recipe_id in state.unlocked_recipes
	var missing: Array[String] = []
	if state.exp < target.exp_required:
		missing.append("历练尚缺 %d" % (target.exp_required - state.exp))
	if not learned:
		missing.append("尚未习得考核丹方")
	if not discovered:
		missing.append("尚未炼成考核丹药（定式研制同样有效）")
	if remaining > 0:
		missing.append("尚缺符合品质丹药 %d 枚" % remaining)
	if not quest_done:
		missing.append("尚未完成 " + _state.db.get_item(target.required_quest_id).name)
	if not flame_done:
		missing.append("尚未收服 " + _state.db.get_item(target.required_flame).name)
	if state.pending_talent_rank > 0:
		missing.append("请先完成当前天赋抉择")
	return Result.success({}, {"current": rank_definition(state.rank), "next": target, "can_promote": missing.is_empty(), "missing": missing, "consumed": consumed, "talents": talents, "ending": {}})


func preview_study(state: Dictionary) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	if state.rank == 10:
		return Result.failure("NO_EXAM", "已完成本世认证，可继续自由炼丹与收集。")
	var exam := rank_definition(state.rank + 1)
	var recipe: Dictionary = _state.db.get_item(exam.exam_recipe_id)
	var costs: Dictionary = recipe.materials.duplicate(true)
	var discount := 0.0
	var substitution := 0
	for talent in Talents.definitions(_state.db, state):
		discount += talent.research_discount
		substitution = maxi(substitution, talent.substitution_ratio)
	var replacements: Dictionary = {}
	if substitution > 0:
		for id in costs.keys():
			if not _state.db.get_item(id).shop_available:
				var deficit := maxi(costs[id] - state.inventory.get(id, 0), 0)
				if deficit > 0:
					replacements[id] = deficit
					costs[id] -= deficit
					if costs[id] == 0:
						costs.erase(id)
					costs["herb_lingcao"] = costs.get("herb_lingcao", 0) + deficit * substitution
	var points := maxi(1, int(ceil(exam.research_cost * (1.0 - minf(discount, 0.75)))))
	var missing: Dictionary = {}
	for id in costs:
		var deficit: int = costs[id] - state.inventory.get(id, 0)
		if deficit > 0:
			missing[id] = deficit
	var available: bool = recipe.id in state.unlocked_recipes and state.rank >= recipe.required_rank
	return Result.success({}, {"recipe_id": recipe.id, "quality": exam.min_quality, "quantity": 1, "cost_items": costs, "research_cost": points, "substituted": replacements, "missing_items": missing, "missing_points": maxi(points - state.research_points, 0), "can_execute": available and missing.is_empty() and state.research_points >= points, "available": available})


func study_exam(state: Dictionary, target_rank: int, action_id: Variant) -> Dictionary:
	var prepared := _prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if target_rank != state.rank + 1 or state.rank == 10:
		return Result.failure("EXAM_CHANGED", "考核已变更，请重新查看。")
	var view := preview_study(state)
	if not view.ok:
		return view
	if not view.result.can_execute:
		return Result.failure("STUDY_REQUIREMENTS", "请先习得考核丹方，补齐药材与研究心得。")
	var plan: Dictionary = view.result
	var spent := _state.resources.inventory.plan_items(prepared.result.candidate, plan.cost_items, true)
	if not spent.ok:
		return spent
	var granted := _state.resources.inventory.plan_pill(spent.result.candidate, plan.recipe_id, plan.quality, 1)
	if not granted.ok:
		return granted
	var next: Dictionary = granted.result.candidate
	var exp: int = _state.db.get_item(plan.recipe_id).tier * 10
	if next.action_count == Economy.MAX_VALUE or next.research_crafts == Economy.MAX_VALUE or next.exp > Economy.MAX_VALUE - exp:
		return Result.failure("AMOUNT_OVERFLOW", "研制奖励或次数达到上限。")
	next.research_points -= plan.research_cost
	next.exp += exp
	next.action_count += 1
	next.research_crafts += 1
	var key := Pills.key(plan.recipe_id, plan.quality)
	if not next.alchemy_discoveries.has(key):
		next.alchemy_discoveries.append(key)
	return _commit(state, next, action_id, plan)


func promote(state: Dictionary, target_rank: int, action_id: Variant) -> Dictionary:
	var prepared := _prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if target_rank != state.rank + 1 or target_rank > 10:
		return Result.failure("INVALID_PROMOTION", "只能参加下一品阶的考核，不能越级或重复认证。")
	var view := preview(state)
	if not view.result.can_promote:
		return Result.failure("PROMOTION_REQUIREMENTS", "晋升条件不足：" + "；".join(view.result.missing))
	var next: Dictionary = prepared.result.candidate
	for key in view.result.consumed:
		next.pills[key].quantity -= view.result.consumed[key]
		if next.pills[key].quantity == 0:
			next.pills.erase(key)
	if next.action_count == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "行动数达到上限。")
	next.rank = target_rank
	next.action_count += 1
	var unlocked: Array[String] = []
	for recipe in _state.db.get_items("recipes"):
		if recipe.unlock.type == "rank" and recipe.unlock.required_rank <= target_rank and recipe.id not in next.unlocked_recipes:
			next.unlocked_recipes.append(recipe.id)
			unlocked.append(recipe.id)
	if target_rank in [3, 6, 9]:
		next.pending_talent_rank = target_rank
	if target_rank == 10:
		next.ending = {"id": "ending_grandmaster", "action_count": next.action_count, "alchemy_attempts": next.statistics.alchemy_attempts, "research_crafts": next.research_crafts, "quests_completed": next.resource_stats.quests_completed, "exp": next.exp}
	return _commit(state, next, action_id, {"rank": target_rank, "unlocked_recipes": unlocked, "ending": next.ending})


func choose_talent(state: Dictionary, talent_id: String, action_id: Variant) -> Dictionary:
	var prepared := _prepare(state, action_id)
	if not prepared.ok:
		return prepared
	if talent_id not in _state.db.get_ids("talents") or state.pending_talent_rank == 0:
		return Result.failure("TALENT_UNAVAILABLE", "当前没有此天赋抉择，已选天赋不可重选。")
	var talent: Dictionary = _state.db.get_item(talent_id)
	if talent.choice_rank != state.pending_talent_rank:
		return Result.failure("TALENT_UNAVAILABLE", "此天赋不属于当前抉择阶段。")
	var next: Dictionary = prepared.result.candidate
	next.talent_choices.append(talent_id)
	next.pending_talent_rank = 0
	return _commit(state, next, action_id, {"talent_id": talent_id})


func collection(state: Dictionary) -> Dictionary:
	if not state.is_empty():
		var checked := _state.validate(state)
		if not checked.ok:
			return checked
	var rows: Array[Dictionary] = []
	var count := 0
	for recipe in _state.db.get_items("recipes"):
		var qualities: Dictionary = {}
		for quality in Pills.QUALITIES:
			qualities[quality] = state.get("alchemy_discoveries", []).has(Pills.key(recipe.id, quality))
			if qualities[quality]:
				count += 1
		rows.append({"recipe": recipe, "qualities": qualities, "learned": recipe.id in state.get("unlocked_recipes", [])})
	return Result.success({}, {"rows": rows, "discovered": count, "total": rows.size() * 4})


func _prepare(state: Dictionary, action_id: Variant) -> Dictionary:
	var checked := _state.validate(state)
	if not checked.ok:
		return checked
	return _state.resources.prepare(state, action_id)


func _commit(state: Dictionary, candidate: Dictionary, action_id: Variant, payload: Dictionary) -> Dictionary:
	candidate.completed_actions.append(action_id)
	candidate.needs_save = true
	var checked := _state.validate(candidate)
	if not checked.ok:
		return checked
	return Transaction.commit(state, candidate, Economy.FIELDS + Alchemy.FIELDS + Resources.FIELDS + State.FIELDS, payload)
