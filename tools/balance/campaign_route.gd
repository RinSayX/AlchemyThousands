extends RefCounted
## Controlled-start economic experiments. Thereafter only production transactions.
const Profile := preload("res://scripts/core/profile_state.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Quest := preload("res://scripts/services/quest_service.gd")
const Explore := preload("res://scripts/services/exploration_service.gd")
const Forage := preload("res://scripts/services/forage_service.gd")
const Progression := preload("res://scripts/services/progression_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
var db: RefCounted
var state: Dictionary
var _alchemy: RefCounted
var _shop: RefCounted
var _quests: RefCounted
var _explore: RefCounted
var _forage: RefCounted
var _growth: RefCounted
var style: String
var error := ""
var status := "running"
var commands := 0
var budget := 5000
var cash := 200
var cash_start := 200
var min_cash := 200
var earned := 0
var spent := 0
var support_furnaces := 0
var liquidity_shortfalls := 0
var consumable_skips := 0
var ledger: Dictionary = {}
var by_recipe: Dictionary = {}
var stages: Array[Dictionary] = []
var upgrades: Array[Dictionary] = []
var active_quest := ""
var current_exam: Dictionary = {}
var _earn_bound := 0
var max_exam_attempts := 8


func _init(content: RefCounted) -> void:
	db = content
	_alchemy = Alchemy.new(db)
	_shop = Shop.new(db)
	_quests = Quest.new(db)
	_explore = Explore.new(db)
	_forage = Forage.new(db)
	_growth = Progression.new(db)


func run(seed_value: int, policy: String, loadout: Array = [], worlds: Array = [], stop_at: int = 10, exam_cap: int = 8, command_budget: int = 5000) -> Dictionary:
	style = policy
	max_exam_attempts = exam_cap
	budget = command_budget
	state = _start(seed_value, loadout, worlds)
	if policy not in Probe.STYLES or stop_at < 1 or stop_at > 10 or exam_cap < 0 or budget < 1:
		status = "invalid_experiment"
		return result(seed_value, loadout, worlds)
	var accepted: Dictionary = _quests.accept(state, "quest_juling_supply", _id())
	if not _accept(accepted, "quest_accept"):
		return result(seed_value, loadout, worlds)
	active_quest = accepted.result.instance_id
	for target in range(1, stop_at + 1):
		current_exam = _growth.rank_definition(target)
		var before := _measure()
		while target == 1 and not _first_quest_done():
			if not _earn(): break
		if not error.is_empty(): break
		if not _upgrade(): break
		var attempts := 0
		while not _has_exam_pill() and attempts < (0 if style == "research" else max_exam_attempts):
			if not _ensure(db.get_item(current_exam.exam_recipe_id).materials): break
			if not _brew(current_exam.exam_recipe_id, false): break
			attempts += 1
			if not _sell_surplus(): break
		if not error.is_empty(): break
		if not _has_exam_pill():
			var study: Dictionary = _growth.preview_study(state).result
			while state.research_points < study.research_cost:
				if not _earn(): break
			if not error.is_empty() or not _ensure(study.cost_items): break
			if not _accept(_growth.study_exam(state, target, _id()), "study"): break
		while state.exp < current_exam.exp_required or (target == 1 and not _first_quest_done()):
			if not _earn(): break
		if not error.is_empty(): break
		if not current_exam.required_flame.is_empty() and current_exam.required_flame not in state.owned_flames:
			if not _ensure({"ore_tiejing": 2}) or not _event("event_earth_fire", "choice_ritual"): break
		if not _accept(_growth.promote(state, target, _id()), "promotion"): break
		if target in [3, 6, 9]:
			if not _accept(_growth.choose_talent(state, "talent_%s_%d" % ["stable" if style == "recycle" else style, target], _id()), "talent"): break
		if not _sell_surplus(): break
		var after := _measure()
		var stage := {"target": target, "recipe": current_exam.exam_recipe_id, "random_exam_attempts": attempts, "cash_end": state.spirit_stones}
		for field in before:
			stage[field] = after[field] - before[field]
		stages.append(stage)
	if error.is_empty(): status = "completed" if state.rank == stop_at else "incomplete"
	return result(seed_value, loadout, worlds)


func _upgrade() -> bool:
	if state.rank < 1: return true
	if "furnace_qingmu" not in state.owned_furnaces:
		if "heritage_tuolu" in state.equipped_inheritances:
			if not _ensure({"ore_tiejing": 4}) or not _event("event_mineral_vein", "choice_furnace_trace"): return false
		elif not _purchase("furnace_qingmu", 1, "equipment"): return false
		_node("furnace_qingmu")
	if style == "rush" and "furnace_chiyan" not in state.owned_furnaces:
		if not _purchase("furnace_chiyan", 1, "equipment"): return false
		_node("furnace_chiyan")
	if "flame_earth" not in state.owned_flames:
		if not _ensure({"ore_tiejing": 2}) or not _event("event_earth_fire", "choice_ritual"): return false
		_node("flame_earth")
	return true


func recovery_probe(seed_value: int, policy: String, loadout: Array, worlds: Array) -> Dictionary:
	style = policy
	state = _start(seed_value, loadout, worlds)
	# Explicit bankruptcy stress fixture, never part of a normal campaign sample.
	state.spirit_stones = 0
	state.inventory = {}
	cash_start = 0
	cash = 0
	min_cash = 0
	current_exam = _growth.rank_definition(1)
	var target := 0
	for id in db.get_item("recipe_juling").materials:
		var item: Dictionary = db.get_item(id)
		target += Lineage.buy_price(db, state, item, item.buy_price) * db.get_item("recipe_juling").materials[id]
	while state.spirit_stones < target:
		if not _earn(): break
	if error.is_empty(): status = "recovered"
	var report := result(seed_value, loadout, worlds)
	report["required_cash"] = target
	return report


func _start(seed_value: int, loadout: Array, worlds: Array) -> Dictionary:
	var number := 3 if loadout.size() > 1 else (1 if worlds.is_empty() else 2)
	return Profile.new(db).create_run(seed_value, number, loadout, worlds).result.state


func _node(id: String) -> void:
	upgrades.append({"item": id, "rank": state.rank, "furnaces": state.statistics.alchemy_attempts, "actions": state.action_count, "cash": state.spirit_stones})


func _ensure(costs: Dictionary) -> bool:
	# Funding can consume basic materials already purchased earlier in this pass.
	# Recheck the complete cart, rather than claiming those materials still exist.
	for pass_index in range(100):
		if not _fill_items(costs): return false
		var complete := true
		for id in costs:
			complete = complete and state.inventory.get(id, 0) >= costs[id]
		if complete: return true
	error = "Material acquisition budget reached"
	status = "budget_exhausted"
	return false


func _fill_items(costs: Dictionary) -> bool:
	for id in costs:
		while state.inventory.get(id, 0) < costs[id]:
			var missing: int = costs[id] - state.inventory.get(id, 0)
			if db.get_item(id).shop_available:
				if not _purchase(id, missing, "materials"): return false
			elif Probe.RARE_SOURCES.has(id):
				var source: Array = Probe.RARE_SOURCES[id]
				if not _event(source[0], source[1]): return false
			else:
				error = "No supported deterministic source: " + id
				status = "unsupported_source"
				return false
	return true


func _purchase(id: String, quantity: int, category: String) -> bool:
	var item: Dictionary = db.get_item(id)
	var unit: int = Lineage.buy_price(db, state, item, item.buy_price) if item.has("buy_price") else item.unlock.price
	if not _fund(unit * quantity): return false
	return _accept(_shop.buy_item(state, id, quantity, _id()), category)


func _event(event_id: String, choice: String) -> bool:
	# Preview the actual transformed option to fund it before entry.
	var cost := 0
	for original in db.get_item(event_id).options:
		if original.id == choice:
			cost = Lineage.option(db, state, event_id, original).cost_stones
	if not _fund(cost): return false
	var entered: Dictionary = _explore.enter(state, _id(), event_id)
	if not _accept(entered, "event_entry"): return false
	return _accept(_explore.resolve(state, entered.result.instance_id, choice, _id()), "exploration")


func _fund(amount: int) -> bool:
	if state.spirit_stones < amount: liquidity_shortfalls += 1
	while state.spirit_stones < amount:
		if not _earn(): return false
	return true


func _earn() -> bool:
	_earn_bound += 1
	if _earn_bound > 1500:
		error = "Support furnace budget reached; not proof of a resource deadlock"
		status = "budget_exhausted"
		return false
	var preview: Dictionary = _alchemy.preview_alchemy(state, "recipe_juling", {}).result
	if not preview.can_execute:
		var recovery: Dictionary = _forage.preview(state).result
		if not recovery.can_forage and recovery.can_rest:
			if not _accept(_forage.rest(state, _id()), "rest"): return false
			recovery = _forage.preview(state).result
		if not recovery.can_forage:
			error = "Neither basic materials nor free recovery available"
			status = "resource_deadlock"
			return false
		if not _accept(_forage.forage(state, _id()), "forage"): return false
	if style == "stable" and active_quest.is_empty() and current_exam.exam_recipe_id != "recipe_juling":
		var accepted: Dictionary = _quests.accept(state, "quest_juling_supply", _id())
		if not _accept(accepted, "quest_accept"): return false
		active_quest = accepted.result.instance_id
	if not _brew("recipe_juling", true): return false
	if not active_quest.is_empty():
		var delivery: Dictionary = _quests.preview_delivery(state, active_quest).result
		if delivery.can_deliver:
			if not _accept(_quests.deliver(state, active_quest, _id()), "commission"): return false
			active_quest = ""
	return _sell_surplus()


func _brew(recipe_id: String, support: bool) -> bool:
	var selected := Probe.setup(db, state, recipe_id, style)
	if support and not selected.consumable_id.is_empty() and state.inventory.get(selected.consumable_id, 0) == 0:
		if state.spirit_stones < db.get_item(selected.consumable_id).unlock.price:
			selected.consumable_id = ""
			consumable_skips += 1
		elif not _purchase(selected.consumable_id, 1, "consumables"): return false
	if not support:
		var required: Dictionary = db.get_item(recipe_id).materials.duplicate()
		if not selected.consumable_id.is_empty(): required[selected.consumable_id] = 1
		if not _ensure(required): return false
	if not _accept(_alchemy.execute_alchemy(state, recipe_id, selected, _id()), "furnace"): return false
	by_recipe[recipe_id] = by_recipe.get(recipe_id, 0) + 1
	if support: support_furnaces += 1
	return true


func _has_exam_pill() -> bool:
	for quality in Pills.QUALITIES:
		if Pills.QUALITIES.find(quality) >= Pills.QUALITIES.find(current_exam.min_quality) and state.pills.has(Pills.key(current_exam.exam_recipe_id, quality)): return true
	return false


func _first_quest_done() -> bool:
	for instance in state.quest_instances.values():
		if instance.template_id == "quest_juling_supply" and instance.status == "completed": return true
	return false


func _sell_surplus() -> bool:
	var reserved := false
	var lines: Array[Dictionary] = []
	# Retain the lowest qualifying current exam pill, sell every other output.
	for quality in Pills.QUALITIES:
		for key in state.pills:
			var pill: Dictionary = state.pills[key]
			if pill.quality != quality: continue
			var amount: int = pill.quantity
			if not reserved and pill.recipe_id == current_exam.exam_recipe_id and Pills.QUALITIES.find(quality) >= Pills.QUALITIES.find(current_exam.min_quality):
				amount -= 1
				reserved = true
			if amount > 0: lines.append({"recipe_id": pill.recipe_id, "quality": quality, "quantity": amount})
	var residue: int = state.inventory.get("material_danzha", 0)
	if residue > 0: lines.append({"item_id": "material_danzha", "quantity": residue})
	return true if lines.is_empty() else _accept(_shop.sell_batch(state, lines, _id()), "sales")


func _id() -> String:
	return "balance-%d" % (commands + 1)


func _accept(outcome: Dictionary, category: String) -> bool:
	if not outcome.ok:
		error = category + ": " + outcome.error_code + " " + outcome.message
		status = "transaction_error"
		return false
	commands += 1
	var delta: int = state.spirit_stones - cash
	if delta > 0: earned += delta
	if delta < 0: spent -= delta
	ledger[category] = ledger.get(category, 0) + delta
	cash = state.spirit_stones
	min_cash = mini(min_cash, cash)
	if commands >= budget:
		error = "Command budget reached; not proof of a resource deadlock"
		status = "budget_exhausted"
		return false
	return true


func _measure() -> Dictionary:
	return {"furnaces": state.statistics.alchemy_attempts, "failures": state.statistics.alchemy_failures, "actions": state.action_count, "commands": commands, "support_furnaces": support_furnaces, "earned": earned, "spent": spent, "studies": state.research_crafts, "outings": state.resource_stats.explorations, "forages": state.resource_stats.forages, "rests": state.resource_stats.rests}


func result(seed_value: int, loadout: Array, worlds: Array) -> Dictionary:
	var summary := _measure()
	summary.merge({"status": status, "error": error, "seed": str(seed_value), "style": style, "loadout": loadout.duplicate(), "worlds": worlds.duplicate(), "ending": state.ending.duplicate(), "rank": state.rank, "cash_start": cash_start, "cash_end": state.spirit_stones, "min_cash": min_cash, "net_cash": state.spirit_stones - cash_start, "cash_reconciles": state.spirit_stones == cash_start + earned - spent, "liquidity_shortfalls": liquidity_shortfalls, "consumable_skips": consumable_skips, "ledger": ledger.duplicate(), "by_recipe": by_recipe.duplicate(), "stages": stages.duplicate(true), "upgrades": upgrades.duplicate(true), "ending_research": state.research_points, "exam_cap": max_exam_attempts})
	summary["run_number"] = state.run_number
	return summary
