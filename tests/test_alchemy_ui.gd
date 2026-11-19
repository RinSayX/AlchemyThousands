extends RefCounted
## Actual scene signals, deferred callbacks, focus and service-backed state.

const Session := preload("res://scripts/core/game_session.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
var _check: Callable


func run(tree: SceneTree, check: Callable) -> bool:
	_check = check
	var settings := tree.root.get_node("AppSettings")
	var motion_before: bool = settings.reduced_motion
	settings.set_reduced_motion(false, false)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = ""
	tree.root.add_child(main)
	await tree.process_frame
	var menu: Control = main.get_node("MainMenu")
	menu.new_game_button.pressed.emit()
	_check.call(menu.modal_content.has_node("EnterAlchemy") and not main.session.has_run(), "P4: Prologue offers entry without creating state prematurely")
	menu.modal_content.get_node("EnterAlchemy").pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	_check.call(room != null and room.is_visible_in_tree() and not menu.visible and main.session.has_run(), "P4: Entering the alchemy room creates one session")
	var session: Session = main.session
	_check.call(room.brew_button.disabled == false and room.recipe_list.item_count == 25 and room.rate.text == "80.0%", "P4: First recipe and engine probability are ready at startup")
	var before: Dictionary = session.state()
	room.buy_button.pressed.emit()
	room.buy_button.pressed.emit()
	_check.call(session.state().spirit_stones == before.spirit_stones - 14 and session.state().inventory.herb_lingcao == before.inventory.herb_lingcao + 2, "P4: Same-frame repeated buy signals charge and grant only once")
	await tree.process_frame
	var snapshot := var_to_bytes(session.state())
	for index in range(3):
		room.selectors.strategy.select(index)
		room.selectors.strategy.item_selected.emit(index)
		var expected: Dictionary = session.preview(room.selected_recipe, room.current_setup()).result
		_check.call(room.rate.text == "%.1f%%" % (expected.success_rate * 100) and room.legendary.text.contains("%.2f%%" % (expected.legendary_per_attempt * 100)), "P4: Strategy preview displays service probabilities " + str(index))
	_check.call(snapshot == var_to_bytes(session.state()), "P4: UI configuration and refresh do not mutate state or RNG")
	room.selectors.strategy.select(0)
	room.selectors.strategy.item_selected.emit(0)
	room.quick.button_pressed = false
	before = session.state()
	room.brew_button.pressed.emit()
	room.brew_button.pressed.emit()
	_check.call(room.phase == "brewing" and session.is_busy() and session.state().statistics.alchemy_attempts == before.statistics.alchemy_attempts + 1, "P4: Repeated brew clicks produce exactly one furnace")
	_check.call(room.brew_button.disabled and room.buy_button.disabled and room.back_button.disabled, "P4: Actions lock immediately while the animation is running")
	_check.call(room.status.text.contains("历练%d" % before.exp) and room.status.text.contains("心得%d" % before.research_points) and room.sell_button.text == "暂无丹药或丹渣可售", "P4: Brewing presentation does not reveal rewards or future sale prices early")
	var after_brew := var_to_bytes(session.state())
	room.buy_materials()
	_check.call(after_brew == var_to_bytes(session.state()), "P4: Trading callback cannot bypass the brewing lock")
	room.skip_button.pressed.emit()
	room.skip_button.pressed.emit()
	room.reveal_timer.timeout.emit()
	_check.call(room.phase == "result" and room.result_overlay.visible and not session.is_busy() and session.history().size() == 1 and after_brew == var_to_bytes(session.state()), "P4: Skip and timer race reveal one receipt without re-awarding")
	_check.call(room.brew_button.focus_mode == Control.FOCUS_NONE and tree.root.gui_get_focus_owner() == room.result_close, "P4: Result modal keeps keyboard focus off background controls")
	room.begin_brew()
	_check.call(after_brew == var_to_bytes(session.state()), "P4: Result modal blocks an extra furnace")
	var sale: Dictionary = session.quote_products()
	before = session.state()
	room.result_sell.pressed.emit()
	room.result_sell.pressed.emit()
	_check.call(sale.ok and session.state().spirit_stones == before.spirit_stones + sale.result.total and session.state().pills.is_empty() and not session.state().inventory.has("material_danzha"), "P4: Result sale credits the authoritative quote once")
	await tree.process_frame
	_check.call(room.result_sell.disabled and room.brew_button.focus_mode == Control.FOCUS_NONE, "P4: Sale refresh preserves modal focus lock and disables empty resale")
	_check.call(tree.root.gui_get_focus_owner() == room.result_close and room.result_body.text.contains("收入 %d 灵石" % sale.result.total), "P4: Sale confirms income and moves focus to the remaining action")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	tree.root.push_input(cancel)
	await tree.process_frame
	_check.call(room.phase == "idle" and not room.result_overlay.visible and room.recent.item_count == 1, "P4: Escape closes the result and keeps one history entry")
	room.search.text = "止血"
	room.search.text_changed.emit("止血")
	_check.call(room.recipe_list.item_count == 1 and room.recipe_list.get_item_metadata(0) == "recipe_zhixue", "P4: Search filters recipes by name")
	room.recipe_list.item_selected.emit(0)
	_check.call(room.unlock_button.visible and not room.unlock_button.disabled and room.brew_button.disabled, "P4: Locked shop recipe shows its purchase path")
	before = session.state()
	room.unlock_button.pressed.emit()
	room.unlock_button.pressed.emit()
	_check.call(session.state().unlocked_recipes.has("recipe_zhixue") and session.state().spirit_stones == before.spirit_stones - 40, "P4: Learning a recipe charges once and unlocks through the shop service")
	await tree.process_frame
	room.search.text = ""
	room.search.text_changed.emit("")
	room.tier_filter.select(2)
	room.tier_filter.item_selected.emit(2)
	_check.call(room.recipe_list.item_count == 4, "P4: Tier filter selects the four second-tier recipes")
	room.tier_filter.select(0)
	room.tier_filter.item_selected.emit(0)
	_select_recipe(room, "recipe_cuiti")
	_check.call(room.brew_button.disabled and room.unlock_button.disabled, "P4: Rank-locked recipe cannot be bought or brewed")
	_select_recipe(room, "recipe_juling")
	room.selectors.consumable_id.select(1)
	room.selectors.consumable_id.item_selected.emit(1)
	_check.call(room.brew_button.disabled and not room.token_button.disabled and room.costs.text.contains("稳丹符"), "P4: Missing token blocks brewing and exposes purchase")
	room.token_button.pressed.emit()
	await tree.process_frame
	_check.call(session.state().inventory.get("consumable_wendan", 0) == 1 and not room.brew_button.disabled, "P4: Buying the selected token refreshes stock and brew availability")
	room.selectors.consumable_id.select(0)
	room.selectors.consumable_id.item_selected.emit(0)
	var room_id := room.get_instance_id()
	snapshot = var_to_bytes(session.state())
	room.back_button.pressed.emit()
	_check.call(menu.visible and not menu.continue_button.disabled and not room.visible, "P4: Returning to the menu enables in-memory continuation")
	menu.new_game_button.pressed.emit()
	_check.call(snapshot == var_to_bytes(session.state()) and menu.modal_content.has_node("EnterAlchemy"), "P4: Opening a new-run confirmation does not reset the current run")
	menu.close_modal()
	menu.continue_button.pressed.emit()
	_check.call(room.visible and room.get_instance_id() == room_id and snapshot == var_to_bytes(session.state()), "P4: Continue restores the same screen/session without starter rewards")
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 720)]:
		tree.root.size = window_size
		await tree.process_frame
		await tree.process_frame
		var fits := true
		for control in [room.brew_button, room.back_button, room.buy_button, room.recipe_list, room.sell_button]:
			fits = fits and Rect2(Vector2.ZERO, room.size).encloses(control.get_global_rect())
		_check.call(fits, "P4: Primary controls fit viewport " + str(window_size))
	room.quick.button_pressed = true
	room.begin_brew()
	await tree.process_frame
	await tree.process_frame
	_check.call(room.phase == "result" and room.result_overlay.visible, "P4: Quick reveal uses the same execution and skips waiting")
	_check.call(Rect2(Vector2.ZERO, room.size).encloses(room.result_body.get_global_rect()), "P4: Result text fits the viewport")
	room.close_result()
	before = session.state()
	var economy := Economy.new(session.content)
	if before.spirit_stones > 0:
		economy.change_stones(session._state, -before.spirit_stones, "zero-money-fixture")
	room.refresh()
	_check.call(room.buy_button.disabled and room.token_button.disabled, "P4: Insufficient funds disable unaffordable purchases")
	snapshot = var_to_bytes(session.state())
	room.buy_materials()
	_check.call(snapshot == var_to_bytes(session.state()), "P4: Failed purchase preserves the complete live state")
	await tree.process_frame
	# A real fixed-seed failure checks the failure presentation, not a fake receipt.
	session.new_run(2)
	Inventory.new(session.content).add_items(session._state, {"consumable_hulu": 1}, "refund-ui-fixture")
	room.refresh()
	room.selectors.consumable_id.select(3)
	room.selectors.consumable_id.item_selected.emit(3)
	room.begin_brew()
	await tree.process_frame
	await tree.process_frame
	_check.call(room.phase == "result" and room.result_title.text.contains("火候未成") and room.result_body.text.contains("返还：灵草×1") and session.state().inventory.herb_lingcao == 4, "P4: Real failed furnace presents returned materials and residue without a success banner")
	room.result_sell.pressed.emit()
	await tree.process_frame
	_check.call(session.state().spirit_stones == 203 and room.result_body.text.contains("收入 3 灵石"), "P4: Failure residue can be sold from the result dialog")
	main.queue_free()
	await tree.process_frame
	settings.set_reduced_motion(motion_before, false)
	_check.call(_test_session(), "P4: Session coordination group completed")
	return true


func _test_session() -> bool:
	var session := Session.new()
	var created := session.new_run(1)
	_check.call(created.ok, "P4: Session can start from a fixed seed for testing")
	created.result.state.inventory.herb_lingcao = 888
	_check.call(session.state().inventory.herb_lingcao == 5, "P4: Session initialization result cannot alias live state")
	var before := session.state()
	var copy := session.state()
	copy.inventory.herb_lingcao = 999
	_check.call(session.state().inventory.herb_lingcao == before.inventory.herb_lingcao, "P4: Session snapshots cannot mutate owned resources")
	var first := session.begin_brew("recipe_juling", {})
	var after := var_to_bytes(session.state())
	var busy := session.begin_brew("recipe_juling", {})
	_check.call(first.ok and not busy.ok and busy.error_code == "BUSY" and after == var_to_bytes(session.state()), "P4: Session blocks duplicate starts before reveal")
	_check.call(not session.new_run(2).ok and not session.buy_materials("recipe_juling", 1).ok and not session.sell_products().ok, "P4: Pending result blocks session reset and trading")
	_check.call(session.finish_brew().ok and not session.finish_brew().ok and session.history().size() == 1, "P4: Session reveal is idempotent")
	var history := session.history()
	history[0].quantity = 999
	_check.call(session.history()[0].quantity != 999, "P4: History is returned as detached copies")
	var inventory := Inventory.new(session.content)
	inventory.add_items(session._state, {"herb_lingcao": 50, "herb_qinghua": 25}, "history-fixture")
	var all_ok := true
	for index in range(22):
		all_ok = all_ok and session.begin_brew("recipe_juling", {}).ok and session.finish_brew().ok
	_check.call(all_ok and session.history().size() == 20 and session.state().statistics.alchemy_attempts == 23, "P4: History keeps only twenty results without altering attempt totals")
	return true


func _select_recipe(room: Control, id: String) -> void:
	for index in range(room.recipe_list.item_count):
		if room.recipe_list.get_item_metadata(index) == id:
			room.recipe_list.select(index)
			room.recipe_list.item_selected.emit(index)
			return
	_check.call(false, "P4: Requested recipe is visible: " + id)
