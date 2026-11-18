extends Control
## Navigation view. The main scene owns the session and all business state.

signal new_run_requested
signal continue_requested
signal quit_requested

const Landscape := preload("res://scripts/ui/ink_landscape.gd")
const GOLD := Color("d4c28e")
const MUTED := Color("92a394")

var new_game_button: Button
var continue_button: Button
var overlay: ColorRect
var modal_content: VBoxContainer
var modal_title: Label
var status_label: Label
var _return_focus: Control
var _serif := SystemFont.new()
var _has_session := false
var _has_save := false
var collection_provider: Callable


func _ready() -> void:
	_serif.font_names = PackedStringArray(["Songti SC", "SimSun", "Noto Serif CJK SC", "serif"])
	var landscape := Control.new()
	landscape.name = "InkLandscape"
	landscape.set_script(Landscape)
	add_child(landscape)
	landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	_build_overlay()
	new_game_button.grab_focus()


func _build_menu() -> void:
	var margin := MarginContainer.new()
	margin.name = "MenuLayout"
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 42)
	var page := VBoxContainer.new()
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	_label(header, "青岚宗  /  丹道手记", 16, GOLD)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_label(header, "序 章     ·     初 见 青 岚", 14, MUTED)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 440
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_label(left, "ALCHEMY  /  THOUSANDS", 12, MUTED)
	var title := _label(left, "百炼成丹", 76, GOLD)
	title.add_theme_font_override("font", _serif)
	var subtitle := _label(left, "我要成为天阶炼丹宗师", 22, Color("b9c8b5"))
	subtitle.add_theme_font_override("font", _serif)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	left.add_child(gap)
	_label(left, "一座旧炉，半卷丹经。\n于草木间求真，在烟火里证道。", 17, MUTED)
	var buttons := VBoxContainer.new()
	buttons.name = "MenuButtons"
	buttons.custom_minimum_size = Vector2(312, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buttons.add_theme_constant_override("separation", 9)
	left.add_child(buttons)
	new_game_button = _button(buttons, "启程入宗     →", show_prologue)
	new_game_button.name = "NewGame"
	new_game_button.add_theme_color_override("font_color", GOLD)
	continue_button = _button(buttons, "继续修行", func() -> void: continue_requested.emit())
	continue_button.name = "Continue"
	continue_button.disabled = true
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.tooltip_text = "暂无修行记录"
	var minor := HBoxContainer.new()
	buttons.add_child(minor)
	_button(minor, "图鉴", show_collection).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(minor, "设置", show_settings).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(minor, "退出", _quit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer := HBoxContainer.new()
	page.add_child(footer)
	_label(footer, "草木有灵  ·  丹心无尽", 14, MUTED)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	_label(footer, "初始版本  0.1     /     离线单人", 13, MUTED)
	var caption := Label.new()
	caption.text = "凡 铁 丹 炉   /   万 般 丹 道 ， 始 于 此 炉"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	caption.anchor_left = 0.5
	caption.anchor_right = 1.0
	caption.anchor_top = 0.81
	caption.anchor_bottom = 0.81
	caption.offset_left = 0
	caption.offset_right = -40


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.name = "ModalOverlay"
	overlay.color = Color(0.015, 0.035, 0.03, 0.88)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 600
	center.add_child(panel)
	modal_content = VBoxContainer.new()
	modal_content.name = "ModalContent"
	modal_content.add_theme_constant_override("separation", 18)
	panel.add_child(modal_content)
	overlay.hide()


func _open_modal(title: String) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	# Prevent keyboard navigation from reaching controls behind the overlay.
	_set_menu_focus(false)
	for child in modal_content.get_children():
		modal_content.remove_child(child)
		child.queue_free()
	modal_title = _label(modal_content, title, 28, GOLD)
	modal_title.add_theme_font_override("font", _serif)
	overlay.show()


func show_prologue() -> void:
	_open_modal("第一章 · 破炉丹童")
	_label(modal_content, "青岚山下，晨雾初散。", 20, Color("b9c8b5"))
	_wrapped_label("你原是边陲宗门的一名丹童。师父留下一座旧丹炉，\n还有半部被烟火熏黄的炼丹手记。\n\n“草木各有性，成丹先修心。”\n\n从一株灵草、一缕凡火开始，你的丹道将由此写下。")
	if _has_session or _has_save:
		_wrapped_label("重新入宗将重置本次修行并替换已保存的进度；灵石、背包、境界和天赋重新开始。")
	else:
		_label(modal_content, "行动后自动保存，可关闭游戏后继续修行。", 15, MUTED)
	var enter := _button(modal_content, "重新入宗" if _has_session or _has_save else "入丹房 · 点燃凡火", func() -> void: new_run_requested.emit())
	enter.name = "EnterAlchemy"
	_close_button()
	enter.grab_focus()


func configure_session(has_session: bool, has_save: bool = false) -> void:
	_has_session = has_session
	_has_save = has_save
	var available := has_session or has_save
	continue_button.disabled = not available
	continue_button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	continue_button.text = "继续本次修行" if has_session else ("读取修行存档" if has_save else "继续修行")
	continue_button.tooltip_text = "返回当前修行。" if has_session else ("读取最近有效存档；损坏时尝试备份。" if has_save else "暂无修行记录")


func show_notice(title: String, message: String) -> void:
	_open_modal(title)
	_wrapped_label(message)
	_close_button()


func show_collection() -> void:
	_open_modal("丹道图鉴")
	if collection_provider.is_valid():
		var result: Dictionary = collection_provider.call()
		if result.ok:
			_wrapped_label("已发现 %d / %d 个丹方品质。出售或交付不会抹去发现记录。" % [result.result.discovered, result.result.total])
			var scroll := ScrollContainer.new()
			scroll.custom_minimum_size = Vector2(540, 250)
			modal_content.add_child(scroll)
			var rows := VBoxContainer.new()
			rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(rows)
			for row in result.result.rows:
				var names: Array[String] = []
				for quality in row.qualities:
					if row.qualities[quality]:
						names.append({"common": "凡品", "good": "良品", "superior": "上品", "legendary": "极品"}[quality])
				_label(rows, row.recipe.name + " · " + (" / ".join(names) if not names.is_empty() else "未发现"), 16, MUTED)
		else:
			_wrapped_label(result.message)
	else:
		_wrapped_label("尚未开始修行，丹经静候第一缕丹香。")
	_close_button()


func show_settings() -> void:
	_open_modal("设置")
	var motion := CheckButton.new()
	motion.name = "ReducedMotion"
	motion.text = "沉静模式 · 停用烟雾与流光动效"
	motion.button_pressed = AppSettings.reduced_motion
	modal_content.add_child(motion)
	motion.toggled.connect(_set_reduced_motion)
	if DisplayServer.get_name() != "headless":
		var fullscreen := CheckButton.new()
		fullscreen.text = "全屏显示"
		fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		modal_content.add_child(fullscreen)
		fullscreen.toggled.connect(func(enabled: bool) -> void:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		)
	status_label = _label(modal_content, "沉静模式偏好自动保存于本机。", 15, MUTED)
	_close_button()
	motion.grab_focus()


func _set_reduced_motion(enabled: bool) -> void:
	var error := AppSettings.set_reduced_motion(enabled)
	if error == OK:
		status_label.text = "偏好已保存。"
	else:
		status_label.text = "设置保存失败，请检查本机目录权限。"
		var motion := modal_content.get_node("ReducedMotion") as CheckButton
		motion.set_pressed_no_signal(AppSettings.reduced_motion)


func close_modal() -> void:
	overlay.hide()
	_set_menu_focus(true)
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	else:
		new_game_button.grab_focus()


func _set_menu_focus(enabled: bool) -> void:
	for button in find_children("*", "Button", true, false):
		if not overlay.is_ancestor_of(button):
			button.focus_mode = Control.FOCUS_ALL if enabled and not button.disabled else Control.FOCUS_NONE


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and overlay.visible:
		close_modal()
		get_viewport().set_input_as_handled()


func _close_button() -> void:
	var button := _button(modal_content, "返回山门", close_modal)
	button.name = "CloseModal"
	button.grab_focus()


func _wrapped_label(text: String) -> Label:
	var label := _label(modal_content, text, 18, Color("d5ddcb"))
	label.custom_minimum_size.x = 540
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _quit() -> void:
	get_tree().quit()
