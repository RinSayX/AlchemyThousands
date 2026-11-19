extends RefCounted

func run(tree: SceneTree, check: Callable) -> bool:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = ""
	tree.root.add_child(main)
	await tree.process_frame
	main.session.new_run(618)
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	check.call(room.selectors.consumable_id_2.item_count == 9 and not room.current_setup().has("consumable_ids"), "P8 dual UI: Second slot is optional and defaults empty")
	var frozen := var_to_bytes([main.session.state(), main.session.meta()])
	_select(room, "consumable_id", "consumable_wendan")
	_select(room, "consumable_id_2", "consumable_juling")
	check.call(room.current_setup().consumable_ids.size() == 2 and room.costs.text.contains("稳丹符") and room.costs.text.contains("聚灵符") and room.costs.text.contains("16") and room.brew_button.disabled and not room.token_button.disabled and frozen == var_to_bytes([main.session.state(), main.session.meta()]), "P8 dual UI: Two missing items expose aggregate costs without spending or RNG")
	var first: OptionButton = room.selectors.consumable_id
	var second: OptionButton = room.selectors.consumable_id_2
	var category_blocked := true
	for i in range(1, second.item_count):
		var id: String = second.get_item_metadata(i)
		if main.session.content.get_item(id).effect_category == "success": category_blocked = category_blocked and second.is_item_disabled(i)
	check.call(category_blocked, "P8 dual UI: Same-category secondary options are visibly disabled")
	var stones: int = main.session.state().spirit_stones
	room.token_button.pressed.emit()
	room.token_button.pressed.emit()
	await tree.process_frame
	check.call(main.session.state().spirit_stones == stones - 16 and main.session.state().inventory.consumable_wendan == 1 and main.session.state().inventory.consumable_juling == 1 and not room.brew_button.disabled, "P8 dual UI: Repeated purchase signals buy each item once as one cart")
	room.quick.button_pressed = false
	room.brew_button.pressed.emit()
	room.brew_button.pressed.emit()
	check.call(room.phase == "brewing" and first.disabled and second.disabled and room.token_button.disabled and main.session.state().statistics.alchemy_attempts == 1, "P8 dual UI: Both slots lock immediately and duplicate brew settles once")
	room.finish_brew()
	await tree.process_frame
	var receipt: Dictionary = main.session.history()[0]
	check.call(room.phase == "result" and receipt.consumed.consumable_wendan == 1 and receipt.consumed.consumable_juling == 1 and not main.session.state().inventory.has("consumable_wendan") and not main.session.state().inventory.has("consumable_juling") and room.result_body.text.contains("稳丹符") and room.result_body.text.contains("聚灵符"), "P8 dual UI: Actual result and frozen history show both consumed items")
	room.close_result()
	_select(room, "consumable_id", "consumable_juling")
	check.call(second.selected == 0 and not room.current_setup().has("consumable_ids"), "P8 dual UI: Changing the first slot clears an incompatible second slot")
	_select(room, "consumable_id", "")
	_select(room, "consumable_id_2", "consumable_wendan")
	check.call(room.current_setup().consumable_ids == ["consumable_wendan"] and room.token_button.visible, "P8 dual UI: Second slot works by itself")
	_select(room, "consumable_id_2", "")
	check.call(not room.token_button.visible and room.current_setup().consumable_id == "", "P8 dual UI: Clearing both restores the legacy empty setup")
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = size
		await tree.process_frame
		await tree.process_frame
		check.call(Rect2(Vector2.ZERO, room.size).encloses(room.brew_button.get_global_rect()) and room.selectors.consumable_id_2.get_global_rect().size.x > 0, "P8 dual UI: Double-slot controls retain the brew action at " + str(size))
	main.queue_free()
	await tree.process_frame
	return true

func _select(room: Control, field: String, id: String) -> void:
	var option: OptionButton = room.selectors[field]
	for i in range(option.item_count):
		if option.get_item_metadata(i) == id:
			option.select(i)
			option.item_selected.emit(i)
			return
