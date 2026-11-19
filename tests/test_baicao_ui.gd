extends RefCounted
const Route := preload("res://tests/helpers/baicao_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")

func run(tree: SceneTree, check: Callable) -> bool:
	var report := Route.new().run()
	if not report.ok: return false
	var path := "res://test-output/p8-baicao-ui-%d.json" % OS.get_process_id()
	var point: Dictionary = report.checkpoints.before_mutation_study
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
	room.open_resources(5)
	var hub: Control = room.resource_hub
	var content := ""
	for child in hub.body.get_children():
		if child is Label: content += child.text
	check.call(content.contains("本世25/25") and content.contains("青灵异变图鉴"), "P8 baicao UI: Collection exposes actual current-life material contact and separate mutation discovery")
	hub.tabs.current_tab = 4
	await tree.process_frame
	check.call(not hub.mutation_study_button.disabled and hub.baicao_button.disabled, "P8 baicao UI: Prepared study is available while mutant proof is still missing")
	var before: Dictionary = main.session.state()
	var study: Button = hub.mutation_study_button
	study.pressed.emit()
	study.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().research_points == before.research_points - 180 and main.session.state().research_crafts == before.research_crafts + 1 and not hub.baicao_button.disabled and main.session.state().rng_states == before.rng_states, "P8 baicao UI: Duplicate study signals produce one proof, spend once and leave RNG unchanged")
	before = main.session.state()
	hub.baicao_button.pressed.emit()
	await tree.process_frame
	check.call(hub._confirm_baicao and before == main.session.state(), "P8 baicao UI: Certification preparation does not consume proof or research")
	var cancel: Button
	for child in hub.body.get_children():
		if child is Button and child.text.contains("取消 · 保留异变丹"): cancel = child
	cancel.pressed.emit()
	await tree.process_frame
	check.call(not hub._confirm_baicao and before == main.session.state(), "P8 baicao UI: Cancelling retains mutated proof")
	hub.baicao_button.pressed.emit()
	await tree.process_frame
	var confirm: Button = hub.baicao_confirm_button
	confirm.pressed.emit()
	confirm.pressed.emit()
	await tree.process_frame
	check.call(main.session.meta().unlocked_endings.size() == 3 and main.session.meta().records[0].optional_endings.size() == 2 and main.session.state().research_points == before.research_points - 120, "P8 baicao UI: Duplicate confirmation archives third ending once alongside Jiuzhuan")
	hub.close_hub()
	main._back_to_menu()
	main.menu.show_collection()
	var menu_text := ""
	for label in main.menu.modal_content.find_children("*", "Label", true, false): menu_text += label.text
	check.call(menu_text.contains("异变品质 1/4") and menu_text.contains("青灵异变涅槃丹"), "P8 baicao UI: Mountain-gate collection retains mutation discovery after proof delivery")
	main.queue_free()
	await tree.process_frame
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
	room.search.text = "涅槃"
	room.search.text_changed.emit("涅槃")
	room.recipe_list.item_selected.emit(0)
	_select(room, "furnace_id", "furnace_jiulong")
	_select(room, "flame_id", "flame_zixiao")
	_select(room, "strategy", "rush")
	check.call(not room.mutation_toggle.disabled and not room.mutation_toggle.button_pressed, "P8 baicao UI: Eligible build offers mutation as a default-off player choice")
	var frozen: Dictionary = main.session.state()
	room.mutation_toggle.button_pressed = true
	check.call(room.costs.text.contains("20.0%") and frozen == main.session.state(), "P8 baicao UI: Enabling mutation discloses chance without spending or RNG")
	room.quick.button_pressed = true
	room.brew_button.pressed.emit()
	room.brew_button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	check.call(room.phase == "result" and main.session.state().statistics.alchemy_attempts == frozen.statistics.alchemy_attempts + 1 and main.session.history()[0].snapshot.mutation_chance == 0.2, "P8 baicao UI: Opted-in actual brew settles one frozen mutation-enabled receipt")
	room.close_result()
	_select(room, "strategy", "normal")
	check.call(room.mutation_toggle.disabled and not room.mutation_toggle.button_pressed, "P8 baicao UI: Ineligible build turns off mutation choice")
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		check.call(Rect2(Vector2.ZERO, room.size).encloses(room.brew_button.get_global_rect()), "P8 baicao UI: Extra mutation control preserves brew action at " + str(size))
	main.queue_free()
	await tree.process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return true

func _select(room: Control, field: String, id: String) -> void:
	var option: OptionButton = room.selectors[field]
	for i in range(option.item_count):
		if option.get_item_metadata(i) == id:
			option.select(i)
			option.item_selected.emit(i)
			return
