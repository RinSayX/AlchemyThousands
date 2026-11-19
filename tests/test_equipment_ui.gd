extends RefCounted
const Route := preload("res://tests/helpers/equipment_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func run(tree: SceneTree, check: Callable) -> bool:
	var report := Route.new().run(8)
	if not report.ok: return false
	var path := "res://test-output/p8-equipment-ui-%d.json" % OS.get_process_id()
	var point: Dictionary = report.checkpoints.before_ice
	if not Saves.new(report.session.content, path).save_run(point.state, point.history, point.meta).ok: return false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.session.load_run()
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	var hub: Control = room.resource_hub
	room.open_resources(0)
	hub.shop_filter.select(3)
	hub.refresh()
	check.call(hub.shop_buttons.furnace_xuanbing.disabled and hub._equipment_source("furnace_xuanbing").contains("4品 · 霜渊试炼"), "P8 UI: Exploration equipment displays rank and stable acquisition source")
	hub.tabs.current_tab = 2
	await tree.process_frame
	check.call(not hub.option_buttons.event_xuanbing_trial.disabled and hub.option_buttons.event_qinglian_trial.text == "试炼已完成", "P8 UI: Available and completed trials have distinct actions")
	hub.scroll.scroll_vertical = 80
	hub.option_buttons.event_xuanbing_trial.pressed.emit()
	await tree.process_frame
	check.call(hub.scroll.scroll_vertical == 0, "P8 UI: Entering a destination reveals event heading and costs from the top")
	var before: Dictionary = main.session.state()
	var choose: Button = hub.option_buttons.choice_forge_xuanbing
	check.call(not choose.disabled, "P8 UI: Public-route materials enable the ice furnace trial")
	choose.pressed.emit()
	choose.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().owned_furnaces.has("furnace_xuanbing") and main.session.state().spirit_stones == before.spirit_stones - 1200, "P8 UI: Duplicate trial signals charge and grant exactly once")
	hub.option_buttons.event_xuanbing_trial.pressed.emit()
	await tree.process_frame
	check.call(hub.option_buttons.choice_forge_xuanbing.disabled and hub.option_buttons.choice_forge_xuanbing.text == "已取得" and hub.option_buttons.has("choice_attune_hansui"), "P8 UI: Partially completed trial retains an explicit claimed row")
	hub.close_hub()
	await tree.process_frame
	main.queue_free()
	await tree.process_frame
	point = report.checkpoints[8]
	Saves.new(report.session.content, path).save_run(point.state, point.history, point.meta)
	main = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.session.load_run()
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	room = main.room
	hub = room.resource_hub
	check.call(room.selectors.furnace_id.item_count == 6 and room.selectors.flame_id.item_count == 5, "P8 UI: All owned equipment is selectable after loading")
	room.open_resources(2)
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		var panel: Control = hub.close_button.get_parent().get_parent()
		check.call(Rect2(Vector2.ZERO, room.size).encloses(panel.get_global_rect()) and hub.option_buttons.event_jiulong_trial.disabled and hub.option_buttons.event_jiulong_trial.text == "试炼已完成", "P8 UI: Completed trial and scroll panel fit " + str(size))
	hub.close_hub()
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
