class_name GameSession
extends RefCounted
## Run coordinator with optional persistence. Views only receive detached state.

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Rebirth := preload("res://scripts/services/rebirth_service.gd")
const Resources := preload("res://scripts/core/progression_state.gd")
const Progression := preload("res://scripts/services/progression_service.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Quests := preload("res://scripts/services/quest_service.gd")
const Exploration := preload("res://scripts/services/exploration_service.gd")
const Forage := preload("res://scripts/services/forage_service.gd")
const MaterialSources := preload("res://scripts/core/material_sources.gd")
const EndingTrial := preload("res://scripts/services/ending_trial_service.gd")
var _ending_trial: RefCounted
var content := Database.new()
var startup: Dictionary
var _alchemy: Alchemy
var _shop: Shop
var _resources: Resources
var _quests: Quests
var _exploration: Exploration
var _forage: Forage
var _state: Dictionary = {}
var _history: Array[Dictionary] = []
var _meta: Dictionary = {}
var _profiles: Profile
var _rebirth: Rebirth
var _pending: Dictionary = {}
var _progression: Progression
var _saves: Saves
var save_status: Dictionary = {}
var save_path := ""


func _init(path: String = "") -> void:
	startup = content.load_directory()
	_profiles = Profile.new(content)
	_rebirth = Rebirth.new(content)
	_alchemy = Alchemy.new(content)
	_shop = Shop.new(content)
	_resources = Resources.new(content)
	_quests = Quests.new(content)
	_exploration = Exploration.new(content)
	_forage = Forage.new(content)
	_progression = Progression.new(content)
	_ending_trial = EndingTrial.new(content)
	if not _ending_trial.startup.ok: startup = _ending_trial.startup.duplicate(true)
	save_path = path
	if not path.is_empty():
		_saves = Saves.new(content, path)


func has_run() -> bool:
	return not _state.is_empty()


func is_busy() -> bool:
	return not _pending.is_empty() or not _state.get("pending_exploration", {}).is_empty()


func new_run(seed_value: Variant = null) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	if not startup.ok:
		return Result.failure("INVALID_CONTENT", "内容配置读取失败，请检查游戏文件。")
	var base: Dictionary = _state.duplicate(true)
	var permanent: Dictionary = _meta.duplicate(true)
	if base.is_empty() and _saves != null:
		var saved := _saves.load_run()
		if saved.ok:
			base = saved.result.state
			permanent = saved.result.meta
	if not base.get("ending", {}).is_empty():
		return Result.failure("REBIRTH_REQUIRED", "本世已通关，请读取继续并在轮回页领取传承、确认下一世；永久记录不会重置。")
	var number: int = base.get("run_number", 1)
	var run_seed: Variant = Time.get_ticks_usec() if seed_value == null else seed_value
	if not run_seed is int:
		return Result.failure("INVALID_SEED", "随机种子必须为整数。")
	if permanent.is_empty():
		permanent = _profiles.empty_meta()
	var created := _profiles.create_run(run_seed, number, base.get("equipped_inheritances", []), base.get("world_modifiers", []), permanent.legacy_insight)
	if created.ok:
		_state = created.result.state.duplicate(true)
		_meta = _profiles.sync(_state, permanent)
		_history.clear()
	return _after_action(created)


func state() -> Dictionary:
	return _state.duplicate(true)


func history() -> Array[Dictionary]:
	return _history.duplicate(true)


func preview(recipe_id: String, setup: Dictionary) -> Dictionary:
	return _alchemy.preview_alchemy(_state, recipe_id, setup)


func begin_brew(recipe_id: String, setup: Dictionary) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	var outcome := _alchemy.execute_alchemy(_state, recipe_id, setup, _next_id())
	if outcome.ok:
		_pending = outcome.duplicate(true)
	return _after_action(outcome)


func finish_brew() -> Dictionary:
	if _pending.is_empty():
		return Result.failure("NO_PENDING_RESULT", "没有待揭晓的丹药。")
	var outcome := _pending.duplicate(true)
	_pending.clear()
	_history.push_front(outcome.result.duplicate(true))
	if _history.size() > 20:
		_history.pop_back()
	return outcome


func quote_materials(recipe_id: String, batches: int) -> Dictionary:
	return _shop.quote_buy(_state, _material_cart(recipe_id, batches))


func buy_materials(recipe_id: String, batches: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	return _after_action(_shop.buy_batch(_state, _material_cart(recipe_id, batches), _next_id()))


func _material_cart(recipe_id: String, batches: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if batches < 1 or batches > 10 or recipe_id not in _state.get("unlocked_recipes", []):
		return lines
	var recipe: Dictionary = content.get_item(recipe_id)
	for id in recipe.materials:
		lines.append({"item_id": id, "quantity": recipe.materials[id] * batches})
	return lines


func quote_item(id: String) -> Dictionary:
	return _shop.quote_buy(_state, [{"item_id": id, "quantity": 1}])


func buy_item(id: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	return _after_action(_shop.buy_item(_state, id, 1, _next_id()))


func quote_products() -> Dictionary:
	var lines := _product_cart()
	if lines.is_empty():
		return Result.failure("NO_PRODUCTS", "尚无可出售的丹药或丹渣。")
	return _shop.quote_sell(_state, lines)


func sell_products() -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	var lines := _product_cart()
	if lines.is_empty():
		return Result.failure("NO_PRODUCTS", "尚无可出售的丹药或丹渣。")
	return _after_action(_shop.sell_batch(_state, lines, _next_id()))


func _product_cart() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for pill in _state.get("pills", {}).values():
		lines.append({"recipe_id": pill.recipe_id, "quality": pill.quality, "mutation_id": pill.mutation_id, "quantity": pill.quantity})
	var residue: int = _state.get("inventory", {}).get("material_danzha", 0)
	if residue > 0:
		lines.append({"item_id": "material_danzha", "quantity": residue})
	return lines


func _next_id() -> String:
	# Derive from committed state: rejected commands cannot create an unsaved gap
	# in the coordinator counter and change the next action ID after reload.
	var sequence: int = _state.get("completed_actions", []).size() + 1
	while _state.get("completed_actions", []).has("session-%d" % sequence):
		sequence += 1
	return "session-%d" % sequence


func quote_shop(id: String, quantity: int) -> Dictionary:
	return _shop.quote_buy(_state, [{"item_id": id, "quantity": quantity}])


func buy_shop(id: String, quantity: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	return _after_action(_shop.buy_item(_state, id, quantity, _next_id()))


func quote_sell_item(id: String, quantity: int) -> Dictionary:
	return _shop.quote_sell(_state, [{"item_id": id, "quantity": quantity}])


func sell_shop(id: String, quantity: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_shop.sell_item(_state, id, quantity, _next_id()))


func quest_board() -> Dictionary:
	return _quests.board(_state)


func accept_quest(id: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_quests.accept(_state, id, _next_id()))


func deliver_quest(id: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_quests.deliver(_state, id, _next_id()))


func forage_status() -> Dictionary:
	return _forage.preview(_state)


func forage() -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_forage.forage(_state, _next_id()))


func rest() -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_forage.rest(_state, _next_id()))


func destinations() -> Dictionary:
	return _exploration.destinations(_state)


func material_sources(item_id: String) -> Array[Dictionary]:
	return MaterialSources.entries(content, _state, item_id)


func enter_event(event_id: String = "") -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_exploration.enter(_state, _next_id(), event_id))


func preview_event_option(option_id: String) -> Dictionary:
	return _exploration.preview_option(_state, _state.pending_exploration.get("instance_id", ""), option_id)


func resolve_event(instance_id: String, option_id: String) -> Dictionary:
	if not _pending.is_empty():
		return Result.failure("BUSY", "丹炉正在炼制。")
	return _after_action(_exploration.resolve(_state, instance_id, option_id, _next_id()))


func leave_event() -> Dictionary:
	return _after_action(_exploration.leave(_state, _state.pending_exploration.get("instance_id", ""), _next_id()))


func progression() -> Dictionary:
	return _progression.preview(_state)


func study_preview() -> Dictionary:
	return _progression.preview_study(_state)


func promote(target_rank: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_progression.promote(_state, target_rank, _next_id()))


func study_exam(target_rank: int) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_progression.study_exam(_state, target_rank, _next_id()))


func choose_talent(id: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _after_action(_progression.choose_talent(_state, id, _next_id()))


func collection() -> Dictionary:
	var run := state()
	var permanent := meta()
	if not has_run() and _saves != null:
		var saved := _saves.load_run()
		if saved.ok:
			run = saved.result.state
			permanent = saved.result.meta
	if not run.is_empty():
		run.alchemy_discoveries = permanent.discovered_pills.duplicate()
	return _progression.collection(run)


func meta() -> Dictionary:
	return _meta.duplicate(true)


func saved_run() -> Dictionary:
	return _saves.load_run() if _saves != null else Result.failure("NO_SAVE", "此会话未启用磁盘存档。")


func load_run() -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或事件，再读取存档。")
	var loaded := saved_run()
	if not loaded.ok:
		return loaded
	_meta = loaded.result.meta.duplicate(true)
	_state = loaded.result.state.duplicate(true)
	_state.needs_save = false
	_history.assign(loaded.result.history.duplicate(true))
	_pending.clear()
	save_status = loaded.duplicate(true)
	return loaded


func save_run() -> Dictionary:
	if _saves == null:
		return Result.failure("NO_SAVE_PATH", "此会话未启用磁盘存档。")
	if not has_run():
		return Result.failure("NO_RUN", "请先开始修行。")
	# Brewing settles before the animation. Save that result as an already-revealed
	# history row, so quitting/reloading can never re-roll or lose paid materials.
	var records: Array = _history.duplicate(true)
	if not _pending.is_empty():
		records.push_front(_pending.result.duplicate(true))
		if records.size() > 20:
			records.resize(20)
	save_status = _saves.save_run(_state, records, _meta)
	if save_status.ok:
		_state.needs_save = false
	return save_status.duplicate(true)


func _after_action(outcome: Dictionary) -> Dictionary:
	if outcome.ok:
		_meta = _profiles.sync(_state, _meta)
		if _saves != null:
			save_run()
	return outcome


func rebirth_status() -> Dictionary:
	return _rebirth.preview(_state, _meta)


func ending_trial() -> Dictionary:
	return _ending_trial.preview(_state, _meta)


func ending_study_preview(recipe_id: String) -> Dictionary:
	return _ending_trial.preview_study(_state, _meta, recipe_id)


func study_ending(source_run: int, recipe_id: String) -> Dictionary:
	if is_busy(): return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _commit_profile_plan(_ending_trial.plan_study(_state, _meta, source_run, recipe_id, _next_id()))


func certify_ending(source_run: int) -> Dictionary:
	if is_busy(): return Result.failure("BUSY", "请先结束当前炼制或事件。")
	return _commit_profile_plan(_ending_trial.plan_certify(_state, _meta, source_run, _next_id()))


func preview_rebirth(loadout: Variant) -> Dictionary:
	return _rebirth.preview_next(_state, _meta, loadout)


func claim_inheritance(source_run: int, choice: String) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	return _commit_profile_plan(_rebirth.plan_claim(_state, _meta, source_run, choice, _next_id()))


func begin_rebirth(source_run: int, loadout: Variant) -> Dictionary:
	if is_busy():
		return Result.failure("BUSY", "请先结束当前炼制或秘境事件。")
	return _commit_profile_plan(_rebirth.plan_rebirth(_state, _meta, source_run, loadout, _next_id()))


func _commit_profile_plan(plan: Dictionary) -> Dictionary:
	if not plan.ok:
		return plan
	var next: Dictionary = plan.result.state.duplicate(true)
	var permanent: Dictionary = plan.result.meta.duplicate(true)
	var records: Array = [] if plan.result.reset_history else _history.duplicate(true)
	if _saves != null:
		save_status = _saves.save_run(next, records, permanent)
		if not save_status.ok:
			return Result.failure(save_status.error_code, "进度事务尚未提交：" + save_status.message + " 原周目与永久记录仍保留，可重试。")
		next.needs_save = false
	_state = next
	_meta = permanent
	_history.assign(records)
	_pending.clear()
	return plan
