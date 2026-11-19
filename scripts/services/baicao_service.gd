extends RefCounted
## Composite plans for deterministic mutation study and the third ending.
const Spec := preload("res://scripts/core/baicao_definition.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
var profile: RefCounted
var startup: Dictionary
var definition: Dictionary = {}

func _init(db: RefCounted) -> void:
	profile = Profile.new(db)
	startup = Spec.read(db)
	if startup.ok: definition = startup.result.definition

func preview(run: Dictionary, meta: Dictionary) -> Dictionary:
	var checked := _check(run, meta)
	if not checked.ok: return checked
	var rule: Dictionary = definition.ending
	var found: Array = meta.get("material_journal", {}).get(run.run_id, [])
	var missing: Array = []
	for id in profile.db.get_ids("materials"):
		if id not in found: missing.append(id)
	var completed := false
	for record in meta.records:
		if record.run_number != run.run_number: continue
		for ending in record.get("optional_endings", []):
			if ending.id == Spec.ID: completed = true
	var proof := ""
	for quality in Pills.QUALITIES:
		var key := Pills.key(Pills.MUTATION_RECIPE, quality, Pills.MUTATION_ID)
		if run.pills.get(key, {}).get("quantity", 0) > 0:
			proof = key
			break
	var available: bool = run.rank >= rule.required_rank and not run.ending.is_empty()
	var can: bool = available and not completed and found.size() >= rule.material_count and run.research_crafts >= rule.research_crafts and run.research_points >= rule.research_cost and not proof.is_empty()
	return Result.success({}, {"definition": definition, "available": available, "completed": completed, "materials": found, "missing_materials": missing, "missing_crafts": maxi(rule.research_crafts - run.research_crafts, 0), "missing_points": maxi(rule.research_cost - run.research_points, 0), "proof_key": proof, "can_certify": can})

func preview_study(run: Dictionary, meta: Dictionary) -> Dictionary:
	var checked := _check(run, meta)
	if not checked.ok: return checked
	var rule: Dictionary = definition.ending
	var costs: Dictionary = {}
	var missing: Dictionary = {}
	for id in profile.db.get_item(Pills.MUTATION_RECIPE).materials:
		costs[id] = profile.db.get_item(Pills.MUTATION_RECIPE).materials[id] * rule.study_material_multiplier
		if costs[id] > run.inventory.get(id, 0): missing[id] = costs[id] - run.inventory.get(id, 0)
	var available: bool = run.rank >= rule.required_rank and not run.ending.is_empty() and Pills.MUTATION_RECIPE in run.unlocked_recipes and definition.mutation.flame_id in run.owned_flames
	return Result.success({}, {"available": available, "can_execute": available and missing.is_empty() and run.research_points >= rule.study_research_cost, "research_cost": rule.study_research_cost, "cost_items": costs, "missing_items": missing, "missing_points": maxi(rule.study_research_cost - run.research_points, 0), "recipe_id": Pills.MUTATION_RECIPE, "mutation_id": Pills.MUTATION_ID, "quality": "superior"})

func plan_study(run: Dictionary, meta: Dictionary, source_run: int, action_id: Variant) -> Dictionary:
	var prepared := _prepare(run, meta, source_run, action_id)
	if not prepared.ok: return prepared
	var view: Dictionary = preview_study(run, meta).result
	if not view.available: return Result.failure("MUTATION_STUDY_LOCKED", "需通关、习得涅槃丹并持有紫霄雷火，才可复现异变。")
	if view.missing_points > 0: return Result.failure("INSUFFICIENT_RESEARCH", "异变复现所需心得不足。")
	if not view.missing_items.is_empty(): return Result.failure("INSUFFICIENT_ITEMS", "异变复现所需药材不足。")
	var spent: Dictionary = profile.runs.resources.inventory.plan_items(prepared.result.candidate, view.cost_items, true)
	if not spent.ok: return spent
	var granted: Dictionary = profile.runs.resources.inventory.plan_pill(spent.result.candidate, Pills.MUTATION_RECIPE, "superior", 1, false, Pills.MUTATION_ID)
	if not granted.ok: return granted
	var next: Dictionary = granted.result.candidate
	if next.action_count == Economy.MAX_VALUE or next.research_crafts == Economy.MAX_VALUE or next.exp > Economy.MAX_VALUE - 60: return Result.failure("AMOUNT_OVERFLOW", "异变复现次数或历练达到上限。")
	next.research_points -= view.research_cost
	next.research_crafts += 1
	next.action_count += 1
	next.exp += 60
	var key := Pills.key(Pills.MUTATION_RECIPE, "superior")
	if key not in next.alchemy_discoveries: next.alchemy_discoveries.append(key)
	return _finish(next, meta, action_id, {"study": view})

func plan_certify(run: Dictionary, meta: Dictionary, source_run: int, action_id: Variant) -> Dictionary:
	var prepared := _prepare(run, meta, source_run, action_id)
	if not prepared.ok: return prepared
	var view: Dictionary = preview(run, meta).result
	if not view.available: return Result.failure("ENDING_REQUIRED", "先完成本世大宗师标准结局。")
	if view.completed: return Result.failure("ENDING_ALREADY_CERTIFIED", "本世已认证百草药祖。")
	if not view.can_certify: return Result.failure("BAICAO_REQUIREMENTS", "需完成本世材料发现与研制要求，备齐心得和一枚青灵异变涅槃丹。")
	var parts: PackedStringArray = view.proof_key.split("|", true)
	var removed: Dictionary = profile.runs.resources.inventory.plan_pill(prepared.result.candidate, parts[0], parts[1], 1, true, parts[2])
	if not removed.ok: return removed
	var next: Dictionary = removed.result.candidate
	if next.action_count == Economy.MAX_VALUE: return Result.failure("AMOUNT_OVERFLOW", "行动数达到上限。")
	next.research_points -= definition.ending.research_cost
	next.action_count += 1
	var archive := {"id": Spec.ID, "action_count": next.action_count, "alchemy_attempts": next.statistics.alchemy_attempts, "research_crafts": next.research_crafts, "quests_completed": next.resource_stats.quests_completed, "exp": next.exp, "consumed": {view.proof_key: 1}, "evidence": {"materials": view.materials.duplicate(), "research_cost": definition.ending.research_cost}}
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
	if source_run != run.run_number: return Result.failure("RUN_CHANGED", "周目已变化，请重新查看百草试炼。")
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
