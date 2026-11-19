extends SceneTree
## Dependency-free content and UI integration checks. Never writes preferences.

const ContentTests := preload("res://tests/test_content.gd")
const EconomyTests := preload("res://tests/test_economy.gd")
const AlchemyTests := preload("res://tests/test_alchemy.gd")
const AlchemyUITests := preload("res://tests/test_alchemy_ui.gd")

const ResourceTests := preload("res://tests/test_resources.gd")
const ResourceUITests := preload("res://tests/test_resources_ui.gd")

const ProgressionTests := preload("res://tests/test_progression.gd")
const ProgressionUITests := preload("res://tests/test_progression_ui.gd")
const SaveTests := preload("res://tests/test_save_load.gd")

const RebirthUITests := preload("res://tests/test_rebirth_ui.gd")
const RebirthTests := preload("res://tests/test_rebirth.gd")
const BalanceTests := preload("res://tests/test_balance.gd")
const TuningTests := preload("res://tests/test_tuning.gd")
const EquipmentTests := preload("res://tests/test_equipment.gd")
const EquipmentUITests := preload("res://tests/test_equipment_ui.gd")
const CatalogTests := preload("res://tests/test_catalog.gd")
const CatalogUITests := preload("res://tests/test_catalog_ui.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := ""
	for flag in ["--content-only", "--economy-only", "--alchemy-only", "--resources-only", "--progression-only", "--rebirth-only", "--balance-only", "--equipment-only", "--catalog-only", "--ui-only"]:
		if args.has(flag):
			if not selected.is_empty():
				_check(false, "Choose one focused test suite at a time")
				_finish()
				return
			selected = flag
	if selected.is_empty() or selected == "--content-only":
		ContentTests.new().run(_check)
	if selected.is_empty() or selected == "--economy-only":
		_check(EconomyTests.new().run(_check), "P2: Economy suite completed")
	if selected.is_empty() or selected == "--alchemy-only":
		_check(AlchemyTests.new().run(_check), "P3: Alchemy suite completed")
	if selected.is_empty() or selected == "--resources-only":
		_check(ResourceTests.new().run(_check), "P5: Resource suite completed")
	if selected.is_empty() or selected == "--progression-only":
		_check(ProgressionTests.new().run(_check), "P6: Progression suite completed")
		_check(SaveTests.new().run(_check), "P6: Save/load suite completed")
	if selected.is_empty() or selected == "--rebirth-only":
		_check(RebirthTests.new().run(_check), "P7: Rebirth suite completed")
	if selected.is_empty() or selected == "--balance-only":
		_check(BalanceTests.new().run(_check), "P8: Balance analysis suite completed")
		_check(TuningTests.new().run(_check), "P8: Tuning suite completed")
	if selected.is_empty() or selected == "--equipment-only":
		_check(EquipmentTests.new().run(_check), "P8: Equipment suite completed")
	if selected.is_empty() or selected == "--catalog-only":
		_check(CatalogTests.new().run(_check), "P8: Catalog suite completed")
	if not selected.is_empty() and selected != "--ui-only":
		_finish()
		return
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_check(packed != null, "Main scene loads")
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	main.save_path = ""
	root.add_child(main)
	await process_frame
	await process_frame
	var menu := main.get_node("MainMenu")
	_check(menu.new_game_button.is_visible_in_tree(), "New game entry is visible")
	_check(menu.continue_button.disabled, "Continue unavailable without a gameplay save")
	_check(root.gui_get_focus_owner() == menu.new_game_button, "Keyboard starts on new game")
	_check(not menu.overlay.visible, "No modal obscures startup")
	menu.new_game_button.pressed.emit()
	await process_frame
	_check(menu.overlay.visible and menu.modal_title.text == "第一章 · 破炉丹童", "New game opens chapter prologue")
	_check(menu.new_game_button.focus_mode == Control.FOCUS_NONE, "Modal blocks background keyboard focus")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel)
	await process_frame
	_check(not menu.overlay.visible, "Escape dismisses the modal")
	_check(root.gui_get_focus_owner() == menu.new_game_button, "Dismiss restores keyboard focus")
	_check(menu.continue_button.focus_mode == Control.FOCUS_NONE, "Unavailable continue stays outside keyboard navigation")
	menu.show_collection()
	_check(menu.modal_title.text == "丹道图鉴", "Collection opens with actual run provider")
	menu.close_modal()
	menu.show_settings()
	_check(menu.modal_content.has_node("ReducedMotion"), "Settings exposes reduced motion")
	var settings := root.get_node("AppSettings")
	var original: bool = settings.reduced_motion
	_check(settings.set_reduced_motion(true, false) == OK, "Motion preference can be changed without writing disk")
	_check(not menu.get_node("InkLandscape").is_processing(), "Reduced motion stops decorative animation")
	settings.set_reduced_motion(original, false)
	menu.close_modal()
	# Window stretch keeps the 1280x720 design usable at the 960x540 minimum.
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var rect: Rect2 = menu.new_game_button.get_global_rect()
		_check(rect.position.x >= 0 and rect.end.y <= menu.size.y, "Menu fits viewport %s" % viewport_size)
		menu.show_prologue()
		await process_frame
		await process_frame
		var modal_rect: Rect2 = menu.modal_content.get_parent().get_global_rect()
		_check(Rect2(Vector2.ZERO, menu.size).encloses(modal_rect), "Prologue fits viewport %s" % viewport_size)
		menu.close_modal()
	main.queue_free()
	await process_frame
	_check(await AlchemyUITests.new().run(self, _check), "P4: Alchemy UI suite completed")
	_check(await ResourceUITests.new().run(self, _check), "P5: Resource UI suite completed")
	_check(await ProgressionUITests.new().run(self, _check), "P6: Progression UI suite completed")
	_check(await RebirthUITests.new().run(self, _check), "P7: Rebirth UI suite completed")
	_check(await EquipmentUITests.new().run(self, _check), "P8: Equipment UI suite completed")
	_check(await CatalogUITests.new().run(self, _check), "P8: Catalog UI suite completed")
	_finish()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		printerr("FAIL: ", description)


func _finish() -> void:
	print("Project checks: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
