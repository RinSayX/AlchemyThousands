extends SceneTree
## Dependency-free content and UI integration checks. Never writes preferences.

const ContentTests := preload("res://tests/test_content.gd")
const EconomyTests := preload("res://tests/test_economy.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--content-only") and args.has("--economy-only"):
		_check(false, "Choose one focused test suite at a time")
		_finish()
		return
	if not args.has("--economy-only"):
		ContentTests.new().run(_check)
	if args.has("--content-only"):
		_finish()
		return
	_check(EconomyTests.new().run(_check), "P2: Economy suite completed")
	if args.has("--economy-only"):
		_finish()
		return
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_check(packed != null, "Main scene loads")
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
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
	_check(menu.overlay.visible and menu.modal_title.text == "第一章 · 破炉丹童", "New game opens prologue placeholder")
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
	_check(menu.modal_title.text == "丹道图鉴", "Collection placeholder opens")
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
