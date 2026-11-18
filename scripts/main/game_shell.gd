extends Node

const Session := preload("res://scripts/core/game_session.gd")
const Room := preload("res://scenes/screens/alchemy_screen.tscn")
var session := Session.new()
var room: Control
@onready var menu: Control = $MainMenu


func _ready() -> void:
	menu.new_run_requested.connect(_new_run)
	menu.continue_requested.connect(_enter_room)
	menu.configure_session(false)
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
	menu.configure_session(true)
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
	room.brew_button.grab_focus()


func _back_to_menu() -> void:
	if session.is_busy():
		return
	room.hide()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	menu.show()
	menu.process_mode = Node.PROCESS_MODE_INHERIT
	menu.configure_session(true)
	menu.continue_button.grab_focus()
