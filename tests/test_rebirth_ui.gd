extends RefCounted
const Route := preload("res://tests/helpers/progression_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Faults := preload("res://tests/test_save_load.gd")
var _check: Callable


func _snapshot(session: RefCounted) -> PackedByteArray:
	return var_to_bytes({"run": session.state(), "meta": session.meta()})


func run(tree: SceneTree, check: Callable) -> bool:
	_check = check
	var report := Route.new().run()
	if not report.ok:
		return false
	var path := "res://test-output/p7-ui-%d.json" % OS.get_process_id()
	var manager := Saves.new(report.session.content, path)
	if not manager.save_run(report.session.state(), report.session.history(), report.session.meta()).ok:
		return false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.get_node("MainMenu").continue_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	var session: RefCounted = main.session
	room.search.text = "太初"
	room.search.text_changed.emit("太初")
	room.recipe_list.select(0)
	room.recipe_list.item_selected.emit(0)
	room.selectors.consumable_id.select(1)
	room.selectors.strategy.select(2)
	room.resource_buttons[7].pressed.emit()
	await tree.process_frame
	var hub: Control = room.resource_hub
	_check.call(hub.tabs.current_tab == 7 and hub.inheritance_buttons.size() == 3 and session.state().rank == 10 and room.brew_button.focus_mode == Control.FOCUS_NONE, "P7 UI: Completed life exposes three real inheritance rewards in an isolated modal")
	var before := _snapshot(session)
	hub.refresh()
	_check.call(before == _snapshot(session) and session.meta().unlocked_inheritances.is_empty(), "P7 UI: Opening and refreshing the rebirth page cannot unlock or reset anything")
	var choose: Button = hub.inheritance_buttons.heritage_baicao
	choose.pressed.emit()
	choose.pressed.emit()
	await tree.process_frame
	_check.call(session.meta().unlocked_inheritances == ["heritage_baicao"] and session.state().heritage_reward == "heritage_baicao" and hub.inheritance_buttons.is_empty(), "P7 UI: Repeated reward click grants one permanent unlock and removes the offer")
	_check.call(hub.loadout_buttons.heritage_baicao.button_pressed and session.saved_run().result.meta.unlocked_inheritances == ["heritage_baicao"], "P7 UI: Newly unlocked inheritance is visibly preselected and persisted before transition")
	before = _snapshot(session)
	var worlds: Array = session.preview_rebirth(["heritage_baicao"]).result.state.world_modifiers
	hub.loadout_buttons.heritage_baicao.button_pressed = false
	await tree.process_frame
	_check.call(before == _snapshot(session) and hub._loadout.is_empty() and session.preview_rebirth([]).result.state.world_modifiers == worlds, "P7 UI: Equipment checkbox changes only the next-life plan; world preview and live RNG are unchanged")
	hub.loadout_buttons.heritage_baicao.button_pressed = true
	await tree.process_frame
	_check.call(tree.root.gui_get_focus_owner() == hub.loadout_buttons.heritage_baicao, "P7 UI: Rebuilding equipment choices preserves keyboard focus on the selected checkbox")
	hub.rebirth_button.pressed.emit()
	await tree.process_frame
	_check.call(hub._confirm_rebirth and session.state().run_number == 1 and session.state().rank == 10 and hub.confirm_rebirth_button.text.contains("保存"), "P7 UI: Prepare displays explicit reset/save confirmation without starting another life")
	var cancel: Button
	for child in hub.body.get_children():
		if child is Button and child.text.contains("取消 · 留在本世"):
			cancel = child
	_check.call(cancel != null, "P7 UI: Player can explicitly cancel and stay in the completed life")
	cancel.pressed.emit()
	await tree.process_frame
	_check.call(not hub._confirm_rebirth and before == _snapshot(session), "P7 UI: Cancel preserves resources, permanent records and random streams")
	hub.rebirth_button.pressed.emit()
	await tree.process_frame
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = window_size
		await tree.process_frame
		await tree.process_frame
		var panel: Control = hub.close_button.get_parent().get_parent()
		_check.call(Rect2(Vector2.ZERO, room.size).encloses(panel.get_global_rect()) and Rect2(Vector2.ZERO, room.size).encloses(room.resource_buttons[7].get_global_rect()), "P7 UI: Rebirth confirmation and eighth footer entry fit " + str(window_size))
	var faulty := Faults.FaultSave.new(session.content, path)
	faulty.fail_write = true
	session._saves = faulty
	var disk := FileAccess.get_file_as_bytes(path)
	hub.confirm_rebirth_button.pressed.emit()
	await tree.process_frame
	_check.call(before == _snapshot(session) and disk == FileAccess.get_file_as_bytes(path) and hub._confirm_rebirth and hub.message.text.contains("尚未提交"), "P7 UI: Failed composite save keeps the old life and confirmation available with a readable retry error")
	faulty.fail_write = false
	var confirm: Button = hub.confirm_rebirth_button
	confirm.pressed.emit()
	confirm.pressed.emit()
	await tree.process_frame
	_check.call(session.state().run_number == 2 and session.state().rank == 0 and session.meta().records.size() == 1 and session.meta().records[0].next_run == 2, "P7 UI: Confirm/retry starts exactly one new life and keeps the archived ending")
	_check.call(room.selected_recipe == "recipe_juling" and room.search.text.is_empty() and room.tier_filter.selected == 0 and session.history().is_empty() and room.recent.get_item_text(0).contains("开炉后") and room.current_setup().consumable_id.is_empty() and room.current_setup().strategy == "normal" and room.status.text.contains("第2世") and room.quick.button_pressed, "P7 UI: Rebirth resets stale recipe filters/history and applies permanent quick-reveal convenience")
	_check.call(session.state().equipped_inheritances == ["heritage_baicao"] and session.state().world_modifiers == worlds and session.collection().result.discovered == report.session.collection().result.discovered, "P7 UI: Displayed loadout/worlds become the live plan while permanent collection survives")
	hub.close_button.pressed.emit()
	_check.call(room.phase == "idle" and not hub.visible and not room.brew_button.disabled, "P7 UI: New life returns directly to playable alchemy without repeating the prologue")
	room.brew_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check.call(room.phase == "result" and session.state().statistics.alchemy_attempts == 1 and session.meta().records[0].ending == report.session.state().ending, "P7 UI: First second-life furnace really settles without modifying the first-life result")
	var saved_state: Dictionary = session.state()
	var saved_meta: Dictionary = session.meta()
	main.queue_free()
	await tree.process_frame
	main = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.get_node("MainMenu").continue_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check.call(main.session.state() == saved_state and main.session.meta() == saved_meta and main.room.recent.item_count == 1, "P7 UI: Restart restores the second-life furnace, permanent archive and recent result without a second grant")
	main.room.open_resources(7)
	await tree.process_frame
	_check.call(main.room.resource_hub.inheritance_buttons.is_empty() and not main.session.rebirth_status().result.can_rebirth and main.session.state().run_number == 2, "P7 UI: Active second life displays permanent history but cannot reclaim the prior reward or skip to a third life")
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".restore.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
