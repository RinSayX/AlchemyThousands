extends Node

const Session := preload("res://scripts/core/game_session.gd")
const Room := preload("res://scenes/screens/alchemy_screen.tscn")
@export var save_path := "user://run_save.json"
var session: Session
var room: Control
@onready var menu: Control = $MainMenu


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--save-path")
	if index >= 0 and index + 1 < args.size():
		save_path = args[index + 1]
	session = Session.new(save_path)
	get_tree().auto_accept_quit = false
	menu.collection_provider = session.collection
	menu.quit_requested.connect(_request_quit)
	menu.new_run_requested.connect(_new_run)
	menu.continue_requested.connect(_continue_run)
	var saved := session.saved_run()
	menu.configure_session(false, saved.ok)
	if saved.ok:
		menu.continue_button.grab_focus()
	elif saved.error_code != "NO_SAVE":
		menu.show_notice("存档暂不可用", saved.message + " 可重新入宗；只有确认新修行后才会替换存档。")
	if not session.startup.ok:
		menu.new_game_button.disabled = true
		menu.show_notice("游戏文件未能读取", "请检查 data 目录中的配置文件后重新启动。")


func _new_run() -> void:
	var created := session.new_run()
	if not created.ok:
		menu.show_notice("暂时无法入宗", created.message)
		return
	if is_instance_valid(room):
		remove_child(room)
		room.queue_free()
	room = null
	menu.close_modal()
	menu.configure_session(true, session.saved_run().ok)
	_enter_room()


func _enter_room() -> void:
	if not session.has_run():
		return
	menu.hide()
	menu.process_mode = Node.PROCESS_MODE_DISABLED
	if not is_instance_valid(room):
		room = Room.instantiate()
		room.session = session
		room.back_requested.connect(_back_to_menu)
		add_child(room)
	room.process_mode = Node.PROCESS_MODE_INHERIT
	room.show()
	room.refresh()
	match room.phase:
		"result": room.result_close.grab_focus()
		"hub": room.resource_hub.tabs.grab_focus()
		"brewing": room.skip_button.grab_focus()
		_: room.brew_button.grab_focus()
	if not session.state().pending_exploration.is_empty() and room.phase == "idle":
		room.open_resources(2)


func _back_to_menu() -> void:
	if session.is_busy():
		return
	room.hide()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	menu.show()
	menu.process_mode = Node.PROCESS_MODE_INHERIT
	menu.configure_session(true, session.saved_run().ok)
	menu.continue_button.grab_focus()


func _continue_run() -> void:
	if not session.has_run():
		var loaded := session.load_run()
		if not loaded.ok:
			menu.show_notice("无法继续修行", loaded.message)
			return
	_enter_room()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()


func _request_quit() -> void:
	if session != null and session.has_run() and not session.save_path.is_empty():
		var saved := session.save_run()
		if not saved.ok:
			if is_instance_valid(room):
				room.hide()
			menu.show()
			menu.process_mode = Node.PROCESS_MODE_INHERIT
			menu.show_notice("退出前保存失败", saved.message + " 可返回修行后重试保存，或选择放弃未存进度。")
			var exit_button := Button.new()
			exit_button.text = "仍然退出 · 放弃未存进度"
			exit_button.pressed.connect(func() -> void: get_tree().quit())
			menu.modal_content.add_child(exit_button)
			menu.configure_session(true, session.saved_run().ok)
			return
	get_tree().quit()
