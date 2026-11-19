extends RefCounted
const Route := preload("res://tests/helpers/catalog_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func run(tree: SceneTree, check: Callable) -> bool:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = ""
	tree.root.add_child(main)
	await tree.process_frame
	main.session.new_run(1)
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	room.search.text = "回灵"
	room.search.text_changed.emit("回灵")
	check.call(room.recipe_list.item_count == 1 and room.recipe_list.get_item_metadata(0) == "recipe_huiling", "P8 catalog UI: Search exposes the new entry recipe")
	room.recipe_list.item_selected.emit(0)
	check.call(room.unlock_button.visible and not room.unlock_button.disabled, "P8 catalog UI: Side recipe purchase path is usable at its rank")
	var before: Dictionary = main.session.state()
	room.unlock_button.pressed.emit()
	room.unlock_button.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().spirit_stones == before.spirit_stones - 50 and main.session.state().unlocked_recipes.has("recipe_huiling"), "P8 catalog UI: Learning new recipe charges once under repeated signals")
	main.queue_free()
	await tree.process_frame
	var report := Route.new().run(8)
	if not report.ok: return false
	var path := "res://test-output/p8-catalog-ui-%d.json" % OS.get_process_id()
	var point: Dictionary = report.checkpoints.before_gushen
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
	room.search.text = "固神"
	room.search.text_changed.emit("固神")
	room.recipe_list.item_selected.emit(0)
	check.call(room.materials.text.contains("来源：月华泽 · 2品") and not room.brew_button.disabled, "P8 catalog UI: Rare ingredient lists a rank-appropriate source and prepared recipe can brew")
	room.open_resources(0)
	var hub: Control = room.resource_hub
	check.call(hub.shop_buttons.essence_yuelu.disabled and hub._material_source("essence_yuelu").contains("20灵石") and hub._material_source("essence_yuelu").contains("月华露×1"), "P8 catalog UI: Material market distinguishes unavailable purchase from fixed source cost/yield")
	hub.tabs.current_tab = 2
	await tree.process_frame
	check.call(not hub.option_buttons.event_moon_marsh.disabled and hub.option_buttons.event_ancient_terrace.disabled, "P8 catalog UI: New supply destinations respect rank gates")
	hub.close_hub()
	room.quick.button_pressed = true
	before = main.session.state()
	room.brew_button.pressed.emit()
	room.brew_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	check.call(room.phase == "result" and main.session.state().statistics.alchemy_attempts == before.statistics.alchemy_attempts + 1 and main.session.history()[0].snapshot.recipe_id == "recipe_gushen", "P8 catalog UI: New recipe executes and reveals one authoritative furnace receipt")
	room.close_result()
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
	room.search.text = "九转还真"
	room.search.text_changed.emit("九转还真")
	room.recipe_list.item_selected.emit(0)
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		var bounds := Rect2(Vector2.ZERO, room.size)
		check.call(bounds.encloses(room.buy_button.get_global_rect()) and bounds.encloses(room.brew_button.get_global_rect()) and bounds.encloses(room.recipe_details.get_global_rect()) and room.materials.text.contains("太古灵台"), "P8 catalog UI: Four-ingredient detail scrolls while action buttons fit " + str(size))
		check.call(room.recipe_details.get_v_scroll_bar().max_value > room.recipe_details.size.y, "P8 catalog UI: Long recipe details remain reachable by scrolling " + str(size))
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true
