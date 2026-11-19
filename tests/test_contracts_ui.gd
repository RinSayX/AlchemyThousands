extends RefCounted
const Route := preload("res://tests/helpers/contracts_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func run(tree: SceneTree, check: Callable) -> bool:
	var report := Route.new().run()
	if not report.ok: return false
	var path := "res://test-output/p8-contracts-ui-%d.json" % OS.get_process_id()
	var point: Dictionary = report.before_delivery
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
	room.open_resources(1)
	var hub: Control = room.resource_hub
	check.call(hub.quest_buttons.size() == 20 and not hub.quest_buttons.quest_huiling_order.disabled, "P8 contracts UI: Twenty commissions render and real brewed side pills enable delivery")
	var before: Dictionary = main.session.state()
	var deliver: Button = hub.quest_buttons.quest_huiling_order
	deliver.pressed.emit()
	deliver.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().spirit_stones == before.spirit_stones + 61 and main.session.state().resource_stats.quests_completed == before.resource_stats.quests_completed + 1 and hub.quest_buttons.quest_huiling_order.text == "再接一单", "P8 contracts UI: Repeated delivery signals pay once and reopen repeatable offer")
	hub.tabs.current_tab = 2
	await tree.process_frame
	check.call(hub.option_buttons.size() == 20 and not hub.option_buttons.event_misty_pass.disabled and hub.option_buttons.event_thunder_stall.disabled, "P8 contracts UI: Twenty destinations render with new encounter rank gates")
	hub.close_hub()
	main.queue_free()
	await tree.process_frame
	Saves.new(report.session.content, path).save_run(report.session.state(), report.session.history(), report.session.meta())
	main = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = path
	tree.root.add_child(main)
	await tree.process_frame
	main.session.load_run()
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	room = main.room
	check.call(room.selectors.consumable_id.item_count == 9, "P8 contracts UI: Eight consumables plus empty slot are selectable")
	for token in ["consumable_yanjiu", "consumable_shuangsheng"]:
		for index in range(room.selectors.consumable_id.item_count):
			if room.selectors.consumable_id.get_item_metadata(index) == token:
				room.selectors.consumable_id.select(index)
				room.selectors.consumable_id.item_selected.emit(index)
		check.call(room.costs.text.contains("基础心得 +3") if token == "consumable_yanjiu" else room.costs.text.contains("25.0%"), "P8 contracts UI: Preview discloses active consumable benefit " + token)
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		check.call(Rect2(Vector2.ZERO, room.size).encloses(room.brew_button.get_global_rect()), "P8 contracts UI: Extended consumable preview preserves brew action at " + str(size))
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
