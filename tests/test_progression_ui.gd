extends RefCounted
const Route := preload("res://tests/helpers/progression_route.gd")
const SaveTests := preload("res://tests/test_save_load.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
var _check: Callable


func run(tree: SceneTree, check: Callable) -> bool:
	_check = check
	var driver := Route.new()
	var report := driver.run("research", 3, false)
	if not report.ok:
		return false
	var path := "res://test-output/p6-ui-%d.json" % OS.get_process_id()
	var manager := Saves.new(report.session.content, path)
	manager.save_run(report.session.state(), report.session.history())
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	var menu: Control = main.get_node("MainMenu")
	_check.call(not main.session.has_run() and not menu.continue_button.disabled and menu.continue_button.text == "读取修行存档", "P6 UI: Saved run enables disk continue without creating a new run")
	menu.show_collection()
	_check.call(menu.modal_content.get_child_count() > 3 and menu.modal_content.get_child(1).text.contains("永久发现"), "P6 UI: Menu collection reads actual saved discoveries")
	menu.close_modal()
	menu.new_game_button.pressed.emit()
	var snapshot := FileAccess.get_file_as_bytes(path)
	_check.call(menu.modal_content.get_child(3).text.contains("重新修行") and snapshot == FileAccess.get_file_as_bytes(path), "P6 UI: Existing disk progress gets an explicit replacement warning before new-run confirmation")
	menu.close_modal()
	menu.continue_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	var session: RefCounted = main.session
	var hub: Control = room.resource_hub
	_check.call(session.state().rank == 3 and session.state().pending_talent_rank == 3 and room.status.text.contains("3品丹师"), "P6 UI: Continue restores reached third rank and the pending milestone")
	room.resource_buttons[4].pressed.emit()
	await tree.process_frame
	_check.call(hub.tabs.current_tab == 4 and hub.talent_buttons.size() == 3 and room.brew_button.focus_mode == Control.FOCUS_NONE, "P6 UI: Growth panel offers exactly three talents with background focus blocked")
	var choose: Button = hub.talent_buttons.talent_research_3
	choose.pressed.emit()
	choose.pressed.emit()
	await tree.process_frame
	_check.call(session.state().talent_choices == ["talent_research_3"] and session.state().pending_talent_rank == 0 and hub.talent_buttons.is_empty(), "P6 UI: Double choice signal selects one talent and removes the choice offer")
	_check.call(session.saved_run().result.state.talent_choices == ["talent_research_3"], "P6 UI: Selected talent immediately survives a disk read")
	# Earn points and buy the displayed costs through the same normal commands used
	# by the route driver, then exercise the actual study and exam buttons.
	driver.session = session
	while session.state().research_points < session.study_preview().result.research_cost:
		if not driver._earn():
			return false
	if not driver._ensure_items(session.study_preview().result.cost_items):
		return false
	hub.refresh()
	await tree.process_frame
	_check.call(not hub.study_button.disabled and not session.progression().result.can_promote, "P6 UI: Study enables when exact costs are held while missing exam pill still blocks promotion")
	var before: Dictionary = session.state()
	var study: Button = hub.study_button
	study.pressed.emit()
	study.pressed.emit()
	await tree.process_frame
	_check.call(session.state().research_crafts == before.research_crafts + 1 and session.state().research_points == before.research_points - 20 and not hub.promote_button.disabled, "P6 UI: Study button creates one guaranteed exam pill at quoted cost")
	var promotion: Button = hub.promote_button
	promotion.pressed.emit()
	promotion.pressed.emit()
	await tree.process_frame
	_check.call(session.state().rank == 4 and session.state().unlocked_recipes.has("recipe_pojing") and room.status.text.contains("4品丹师"), "P6 UI: Certification signal advances one rank and refreshes recipe access and room status")
	hub.tabs.current_tab = 5
	await tree.process_frame
	_check.call(hub.body.get_child(0).text.contains("丹道图鉴") and session.collection().result.discovered >= 4, "P6 UI: Collection page lists actual production/research discoveries")
	hub.tabs.current_tab = 6
	await tree.process_frame
	_check.call(not hub.save_button.disabled and not hub.load_button.disabled, "P6 UI: Save page provides actual manual save and load commands")
	hub.save_button.pressed.emit()
	await tree.process_frame
	_check.call(hub.message.text.contains("已保存") and session.save_status.ok, "P6 UI: Save success feedback comes from actual verified disk write")
	var state_bytes := var_to_bytes(session.state())
	hub.load_button.pressed.emit()
	await tree.process_frame
	_check.call(hub._confirm_load and var_to_bytes(session.state()) == state_bytes and hub.confirm_load_button.text.contains("覆盖"), "P6 UI: Opening load confirmation cannot overwrite current state")
	hub.confirm_load_button.pressed.emit()
	await tree.process_frame
	_check.call(not hub._confirm_load and hub.message.text.contains("已读取") and session.state().rank == 4 and not session.is_busy(), "P6 UI: Confirmed load restores the saved run without starter resources or talent reset")
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = window_size
		for index in [4, 5, 6]:
			hub.tabs.current_tab = index
			await tree.process_frame
			await tree.process_frame
			var panel: Control = hub.close_button.get_parent().get_parent()
			_check.call(Rect2(Vector2.ZERO, room.size).encloses(panel.get_global_rect()) and Rect2(Vector2.ZERO, room.size).encloses(room.resource_buttons[6].get_global_rect()), "P6 UI: Progression tab %d and new footer fit %s" % [index, window_size])
	var saved_bytes := FileAccess.get_file_as_bytes(path)
	var faulty := SaveTests.FaultSave.new(session.content, path)
	faulty.fail_write = true
	session._saves = faulty
	session.buy_shop("herb_lingcao", 1)
	var dirty_state := var_to_bytes(session.state())
	main._request_quit()
	_check.call(menu.overlay.visible and menu.modal_title.text == "退出前保存失败" and session.state().needs_save and var_to_bytes(session.state()) == dirty_state and FileAccess.get_file_as_bytes(path) == saved_bytes, "P6 UI: Failed exit save keeps the app and dirty run available without replacing good disk progress")
	menu.close_modal()
	menu.continue_button.pressed.emit()
	faulty.fail_write = false
	hub.tabs.current_tab = 6
	hub.refresh()
	hub.save_button.pressed.emit()
	await tree.process_frame
	_check.call(session.save_status.ok and not session.state().needs_save and room.visible and tree.root.gui_get_focus_owner() == hub.tabs, "P6 UI: Player can return after failed exit and retry saving with modal focus restored")
	hub.close_hub()
	session.enter_event("event_qinglan")
	main.queue_free()
	await tree.process_frame
	main = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.get_node("MainMenu").continue_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check.call(main.session.is_busy() and main.room.phase == "hub" and main.room.resource_hub.tabs.current_tab == 2 and main.room.resource_hub.option_buttons.has("choice_gather"), "P6 UI: Restart at a pending event reopens its existing card without another entry action")
	main.room.resource_hub.close_hub()
	main.queue_free()
	await tree.process_frame
	report = Route.new().run()
	manager.save_run(report.session.state(), report.session.history())
	main = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.get_node("MainMenu").continue_button.pressed.emit()
	await tree.process_frame
	main.room.open_resources(4)
	await tree.process_frame
	hub = main.room.resource_hub
	var ending_visible := false
	for child in hub.body.get_children():
		if child is Label and child.text.contains("道成大宗师"):
			ending_visible = true
	_check.call(ending_visible and main.session.state().ending.id == "ending_grandmaster", "P6 UI: Completed run displays the standard ending and immutable run summary after restart")
	hub.close_button.pressed.emit()
	_check.call(main.room.phase == "idle" and main.room.visible, "P6 UI: Ending review can return to the same run for collection play")
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
