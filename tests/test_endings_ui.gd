extends RefCounted
const Route := preload("res://tests/helpers/ending_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func run(tree: SceneTree, check: Callable) -> bool:
	var report := Route.new().run()
	if not report.ok: return false
	var path := "res://test-output/p8-ending-ui-%d.json" % OS.get_process_id()
	var point: Dictionary = report.checkpoints.before_study
	Saves.new(report.session.content, path).save_run(point.state, point.history, point.meta)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.session.load_run()
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	room.open_resources(4)
	var hub: Control = room.resource_hub
	check.call(hub.ending_button.disabled and hub.ending_study_buttons.size() == 2 and not hub.ending_study_buttons.recipe_taichu.disabled, "P8 ending UI: Post-game page discloses study and missing proof before certification")
	var before: Dictionary = main.session.state()
	var study: Button = hub.ending_study_buttons.recipe_taichu
	study.pressed.emit()
	study.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().research_points == before.research_points - 180 and main.session.state().research_crafts == before.research_crafts + 1 and main.session.state().rng_states == before.rng_states, "P8 ending UI: Duplicate study signals charge once without drawing RNG")
	hub.ending_study_buttons.recipe_jiuzhuan.pressed.emit()
	await tree.process_frame
	check.call(not hub.ending_button.disabled, "P8 ending UI: Both real studied pills enable certification")
	before = main.session.state()
	hub.ending_button.pressed.emit()
	await tree.process_frame
	check.call(hub._confirm_ending and before == main.session.state(), "P8 ending UI: Preparation shows explicit consume/save confirmation without spending")
	var cancel: Button
	for child in hub.body.get_children():
		if child is Button and child.text.contains("取消 · 保留丹药"): cancel = child
	cancel.pressed.emit()
	await tree.process_frame
	check.call(not hub._confirm_ending and before == main.session.state(), "P8 ending UI: Cancelling preserves both proof pills")
	hub.ending_button.pressed.emit()
	await tree.process_frame
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		var panel: Control = hub.close_button.get_parent().get_parent()
		check.call(Rect2(Vector2.ZERO, room.size).encloses(panel.get_global_rect()), "P8 ending UI: Optional-ending confirmation scroll panel fits " + str(size))
	var confirm: Button = hub.confirm_ending_button
	confirm.pressed.emit()
	confirm.pressed.emit()
	await tree.process_frame
	check.call(main.session.meta().unlocked_endings.has("ending_jiuzhuan") and main.session.meta().records[0].optional_endings.size() == 1 and main.session.state().action_count == before.action_count + 1 and main.session.state().ending == before.ending, "P8 ending UI: Repeated confirmation consumes once and preserves standard ending")
	hub.tabs.current_tab = 7
	await tree.process_frame
	var text := ""
	for child in hub.body.get_children():
		if child is Label: text += child.text
	check.call(text.contains("九转丹圣已归档") and text.contains("/100") and hub.inheritance_buttons.size() == 3, "P8 ending UI: Rebirth page shows special archive, dynamic collection capacity and the original three-choice single reward")
	hub.close_hub()
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
