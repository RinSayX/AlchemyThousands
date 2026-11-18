class_name AlchemyService
extends RefCounted
## One furnace, one action, one transaction; gameplay failure is still ok=true.

const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Transaction := preload("res://scripts/core/state_transaction.gd")
const FIELDS := ["exp", "research_points", "action_count", "statistics", "alchemy_discoveries", "rng_states", "equipped_furnace", "equipped_flame", "needs_save"]
const COUNTERS := ["alchemy_attempts", "alchemy_successes", "alchemy_failures"]
const Talents := preload("res://scripts/core/talent_rules.gd")
const RESIDUE := "material_danzha"

var _db: Database
var _economy: Economy
var _inventory: Inventory


func _init(content: Database) -> void:
	_db = content
	_economy = Economy.new(content)
	_inventory = Inventory.new(content)


func create_state(seed_value: Variant = 1) -> Dictionary:
	if not seed_value is int:
		return Result.failure("INVALID_SEED", "随机种子必须为整数。")
	var created := _economy.create_economy_state()
	if not created.ok:
		return created
	var state: Dictionary = created.result.state
	state.merge({"exp": 0, "research_points": 0, "action_count": 0, "statistics": {"alchemy_attempts": 0, "alchemy_successes": 0, "alchemy_failures": 0}, "alchemy_discoveries": [], "equipped_furnace": "furnace_basic", "equipped_flame": "flame_normal", "rng_states": Context.new(seed_value).snapshot(), "needs_save": false})
	var checked := validate_state(state)
	return Result.success({}, {"state": state}) if checked.ok else checked


func validate_state(state: Dictionary) -> Dictionary:
	var checked := _economy.validate_state(state)
	if not checked.ok:
		return checked
	for field in FIELDS:
		if not state.has(field):
			return Result.failure("INVALID_STATE", "缺少炼丹状态字段：" + field)
	for field in ["exp", "research_points", "action_count"]:
		if not Economy.valid_integer(state[field], 0):
			return Result.failure("INVALID_STATE", "炼丹成长数据不合法：" + field)
	if not state.needs_save is bool:
		return Result.failure("INVALID_STATE", "存档脏标记不合法。")
	if not state.statistics is Dictionary:
		return Result.failure("INVALID_STATE", "炼丹统计不合法。")
	for field in COUNTERS:
		if not Economy.valid_integer(state.statistics.get(field), 0):
			return Result.failure("INVALID_STATE", "炼丹统计计数不合法：" + field)
	if state.statistics.alchemy_attempts != state.statistics.alchemy_successes + state.statistics.alchemy_failures or state.action_count < state.statistics.alchemy_attempts:
		return Result.failure("INVALID_STATE", "炼丹次数与成功失败计数不一致。")
	if not Context.valid_snapshot(state.rng_states):
		return Result.failure("INVALID_RNG_STATE", "炼丹随机流快照不合法。")
	if not state.equipped_furnace is String or state.equipped_furnace not in state.owned_furnaces or not state.equipped_flame is String or state.equipped_flame not in state.owned_flames:
		return Result.failure("INVALID_STATE", "当前装备未拥有或不合法。")
	if not state.alchemy_discoveries is Array:
		return Result.failure("INVALID_STATE", "炼丹发现记录必须为数组。")
	var seen: Dictionary = {}
	var allowed: Array[String] = []
	for id in _db.get_ids("recipes"):
		for quality in Pills.QUALITIES:
			allowed.append(Pills.key(id, quality))
	for key in state.alchemy_discoveries:
		if not key is String or key not in allowed or seen.has(key):
			return Result.failure("INVALID_STATE", "炼丹发现记录含未知或重复条目。")
		seen[key] = true
	if state.has("world_modifiers") and (not state.world_modifiers is Array or not state.world_modifiers.is_empty()):
		return Result.failure("UNSUPPORTED_RULE", "此阶段尚未接入天地变数。")
	if not Talents.valid_choices(_db, state):
		return Result.failure("INVALID_STATE", "天赋引用、境界或选择次数不合法。")
	if RESIDUE not in _db.get_ids("materials"):
		return Result.failure("INVALID_CONFIG", "缺少炼丹失败产物的内容定义。")
	return Result.success()


func preview_alchemy(state: Dictionary, recipe_id: String, setup: Dictionary = {}) -> Dictionary:
	var checked := validate_state(state)
	if not checked.ok:
		return checked
	if recipe_id not in _db.get_ids("recipes"):
		return Result.failure("UNKNOWN_RECIPE", "丹方不存在。")
	if recipe_id not in state.unlocked_recipes:
		return Result.failure("RECIPE_LOCKED", "尚未解锁此丹方。")
	var recipe: Dictionary = _db.get_item(recipe_id)
	if state.rank < recipe.required_rank:
		return Result.failure("RANK_LOCKED", "境界不足，无法炼制此丹方。")
	for field in setup:
		if field not in ["furnace_id", "flame_id", "consumable_id", "strategy"]:
			return Result.failure("INVALID_SETUP", "未知炼丹配置字段：" + str(field))
	var selected := {"furnace_id": setup.get("furnace_id", state.equipped_furnace), "flame_id": setup.get("flame_id", state.equipped_flame), "consumable_id": setup.get("consumable_id", ""), "strategy": setup.get("strategy", "normal")}
	for field in selected:
		if not selected[field] is String:
			return Result.failure("INVALID_SETUP", "装备、符箓与策略必须为单个 ID。")
	if not Rules.STRATEGIES.has(selected.strategy):
		return Result.failure("INVALID_SETUP", "未知炼制策略。")
	if selected.furnace_id not in state.owned_furnaces or selected.flame_id not in state.owned_flames:
		return Result.failure("EQUIPMENT_NOT_OWNED", "未拥有所选丹炉或异火。")
	var consumable: Dictionary = {}
	var consume: Dictionary = {}
	if not selected.consumable_id.is_empty():
		if selected.consumable_id not in _db.get_ids("consumables"):
			return Result.failure("INVALID_SETUP", "所选符箓不存在。")
		consumable = _db.get_item(selected.consumable_id)
		consume[selected.consumable_id] = 1
	var snapshot := Rules.calculate(recipe, state.rank, _db.get_item(selected.furnace_id), _db.get_item(selected.flame_id), consumable, selected.strategy, Talents.definitions(_db, state))
	var missing: Dictionary = {}
	var missing_consumables: Dictionary = {}
	var refund: Dictionary = {}
	for id in recipe.materials:
		var deficit: int = recipe.materials[id] - state.inventory.get(id, 0)
		if deficit > 0:
			missing[id] = deficit
		var quantity := int(floor(recipe.materials[id] * snapshot.material_refund_rate))
		if quantity > 0:
			refund[id] = quantity
	for id in consume:
		if state.inventory.get(id, 0) < 1:
			missing_consumables[id] = 1
	var material_cost: Variant = _shop_cost(recipe.materials)
	var consumable_cost: Variant = 0 if consumable.is_empty() else (consumable.unlock.price if consumable.unlock.type == "shop" else null)
	var total_cost: Variant = null
	if material_cost is int and consumable_cost is int and material_cost + consumable_cost <= Economy.MAX_VALUE:
		total_cost = material_cost + consumable_cost
	snapshot.merge({"recipe_id": recipe_id, "setup": selected, "materials": recipe.materials, "consumables": consume, "missing_materials": missing, "missing_consumables": missing_consumables, "can_execute": missing.is_empty() and missing_consumables.is_empty(), "failure_returns": refund, "failure_items": {RESIDUE: 1}, "material_shop_cost": material_cost, "consumable_shop_cost": consumable_cost, "total_shop_cost": total_cost, "exp_rewards": {"success": recipe.tier * 10, "failure": recipe.tier * 3}, "research_rewards": {"base": 1, "new_quality": 2}})
	return Result.success({}, snapshot)


func execute_alchemy(state: Dictionary, recipe_id: String, setup: Dictionary, action_id: Variant) -> Dictionary:
	var prepared := _economy.prepare(state, action_id)
	if not prepared.ok:
		return prepared
	var preview := preview_alchemy(state, recipe_id, setup)
	if not preview.ok:
		return preview
	var snapshot: Dictionary = preview.result
	if not snapshot.missing_materials.is_empty():
		return Result.failure("INSUFFICIENT_MATERIAL", "炼丹材料不足。")
	if not snapshot.missing_consumables.is_empty():
		return Result.failure("INSUFFICIENT_CONSUMABLE", "所选符箓数量不足。")
	var costs: Dictionary = snapshot.materials.duplicate(true)
	costs.merge(snapshot.consumables)
	var consumed := _inventory.plan_items(prepared.result.candidate, costs, true)
	if not consumed.ok:
		return consumed
	var rng := Context.new()
	var restored := rng.restore(state.rng_states)
	if not restored.ok:
		return restored
	# All draws occur on a disposable context until the complete candidate commits.
	var outcome := Rules.roll(snapshot, rng)
	var planned := _settle(consumed.result.candidate, snapshot, outcome)
	if not planned.ok:
		return planned
	var next: Dictionary = planned.result.candidate
	next.rng_states = rng.snapshot()
	next.needs_save = true
	next.completed_actions.append(action_id)
	var checked := validate_state(next)
	if not checked.ok:
		return checked
	var payload: Dictionary = outcome.duplicate(true)
	payload.merge({"action_id": action_id, "snapshot": snapshot, "consumed": costs, "returned": {} if outcome.success else snapshot.failure_returns, "residue": 0 if outcome.success else 1, "exp_gained": planned.result.exp_gained, "research_gained": planned.result.research_gained, "new_quality": planned.result.new_quality})
	return Transaction.commit(state, next, Economy.FIELDS + FIELDS, payload)


func _settle(candidate: Dictionary, snapshot: Dictionary, outcome: Dictionary) -> Dictionary:
	var planned: Dictionary
	var first := false
	if outcome.success:
		planned = _inventory.plan_pill(candidate, snapshot.recipe_id, outcome.quality, outcome.quantity)
		first = not candidate.alchemy_discoveries.has(Pills.key(snapshot.recipe_id, outcome.quality))
	else:
		var returns: Dictionary = snapshot.failure_returns.duplicate(true)
		returns[RESIDUE] = returns.get(RESIDUE, 0) + 1
		planned = _inventory.plan_items(candidate, returns)
	if not planned.ok:
		return planned
	var next: Dictionary = planned.result.candidate
	var exp: int = snapshot.exp_rewards.success if outcome.success else snapshot.exp_rewards.failure
	var research: int = snapshot.research_rewards.base + (snapshot.research_rewards.new_quality if first else 0)
	var counter := "alchemy_successes" if outcome.success else "alchemy_failures"
	if next.exp > Economy.MAX_VALUE - exp or next.research_points > Economy.MAX_VALUE - research or next.action_count == Economy.MAX_VALUE or next.statistics.alchemy_attempts == Economy.MAX_VALUE or next.statistics[counter] == Economy.MAX_VALUE:
		return Result.failure("AMOUNT_OVERFLOW", "炼丹奖励或统计计数超出上限。")
	next.exp += exp
	next.research_points += research
	next.action_count += 1
	next.statistics.alchemy_attempts += 1
	next.statistics[counter] += 1
	if first:
		next.alchemy_discoveries.append(Pills.key(snapshot.recipe_id, outcome.quality))
	return Result.success({}, {"candidate": next, "exp_gained": exp, "research_gained": research, "new_quality": first})


func _shop_cost(materials: Dictionary) -> Variant:
	var total := 0
	for id in materials:
		var item: Dictionary = _db.get_item(id)
		if not item.shop_available:
			return null
		var cost: int = item.buy_price * materials[id]
		if cost > Economy.MAX_VALUE - total:
			return null
		total += cost
	return total
