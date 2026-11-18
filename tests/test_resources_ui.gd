extends RefCounted
## Real scene signals exercise all four resource tabs and shared session locks.

const Inventory := preload("res://scripts/services/inventory_service.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
var _check: Callable


func run(tree: SceneTree, check: Callable) -> bool:
	_check = check
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.save_path = ""
	tree.root.add_child(main)
	await tree.process_frame
	main.session.new_run(1)
	main._enter_room()
	await tree.process_frame
	await tree.process_frame
	var room: Control = main.room
	var session: RefCounted = main.session
	var hub: Control = room.resource_hub
	room.resource_buttons[0].pressed.emit()
	await tree.process_frame
	_check.call(room.phase == "hub" and hub.visible and hub.tabs.current_tab == 0 and room.brew_button.focus_mode == Control.FOCUS_NONE and tree.root.gui_get_focus_owner() == hub.tabs, "P5 UI: Market opens with keyboard focus isolated from alchemy room")
	var before: Dictionary = session.state()
	var buy: Button = hub.shop_buttons.herb_lingcao
	buy.pressed.emit()
	buy.pressed.emit()
	_check.call(session.state().spirit_stones == before.spirit_stones - 4 and session.state().inventory.herb_lingcao == before.inventory.herb_lingcao + 1, "P5 UI: Duplicate shop signals charge and grant once")
	await tree.process_frame
	hub.quantity.value = 3
	await tree.process_frame
	before = session.state()
	hub.shop_buttons.herb_qinghua.pressed.emit()
	await tree.process_frame
	_check.call(session.state().spirit_stones == before.spirit_stones - 18 and session.state().inventory.herb_qinghua == before.inventory.herb_qinghua + 3, "P5 UI: Market quantity uses authoritative batch quote")
	hub.shop_filter.select(3)
	hub.shop_filter.item_selected.emit(3)
	_check.call(hub.shop_buttons.furnace_qingmu.disabled and hub.shop_buttons.furnace_basic.disabled, "P5 UI: Rank-locked and already-owned permanent goods cannot be bought")
	hub.tabs.current_tab = 1
	await tree.process_frame
	_check.call(not hub.quest_buttons.quest_juling_supply.disabled and hub.quest_buttons.quest_ningshen_supply.disabled, "P5 UI: Quest board exposes initial repeatable and rank/recipe gates")
	var accept: Button = hub.quest_buttons.quest_juling_supply
	accept.pressed.emit()
	accept.pressed.emit()
	await tree.process_frame
	_check.call(session.state().quest_instances.size() == 1 and hub.quest_buttons.quest_juling_supply.disabled, "P5 UI: Repeated acceptance creates one instance and missing pills disable delivery")
	hub.close_button.pressed.emit()
	_check.call(room.phase == "idle" and not hub.visible and room.brew_button.focus_mode != Control.FOCUS_NONE, "P5 UI: Closing hub restores room interaction and focus modes")
	# A real successful seed-one furnace, keeping its output for a commission.
	room.quick.button_pressed = true
	room.begin_brew()
	_check.call(room.resource_buttons[0].disabled and room.resource_buttons[1].disabled, "P5 UI: Brewing disables all resource entry points")
	room.open_resources(1)
	_check.call(room.phase == "brewing" and not hub.visible, "P5 UI: Direct resource callback cannot bypass the brewing lock")
	await tree.process_frame
	await tree.process_frame
	_check.call(room.phase == "result" and not session.state().pills.is_empty(), "P5 UI: Actual furnace produces pills available for a commission")
	room.close_result()
	room.open_resources(1)
	await tree.process_frame
	before = session.state()
	var deliver: Button = hub.quest_buttons.quest_juling_supply
	_check.call(not deliver.disabled, "P5 UI: Kept qualifying pills enable delivery")
	deliver.pressed.emit()
	deliver.pressed.emit()
	await tree.process_frame
	_check.call(session.state().spirit_stones == before.spirit_stones + 40 and session.state().resource_stats.quests_completed == 1 and hub.quest_buttons.quest_juling_supply.text == "再接一单", "P5 UI: Delivery grants one reward and refreshes repeatable offer")
	hub.tabs.current_tab = 2
	await tree.process_frame
	_check.call(hub.option_buttons.event_earth_fire.disabled and not hub.option_buttons.event_old_grove.disabled, "P5 UI: Exploration destinations display rank gates")
	hub.option_buttons.event_old_grove.pressed.emit()
	await tree.process_frame
	_check.call(session.is_busy() and hub.tabs.is_tab_disabled(0) and hub.option_buttons.has("choice_trade"), "P5 UI: Entered event locks other tabs and displays choices")
	var snapshot := var_to_bytes(session.state())
	_check.call(not session.begin_brew("recipe_juling", {}).ok and not session.buy_shop("herb_lingcao", 1).ok and not session.forage().ok and not session.new_run(5).ok and snapshot == var_to_bytes(session.state()), "P5 UI: Pending event blocks brewing, market, forage and reset at session boundary")
	before = session.state()
	var choice: Button = hub.option_buttons.choice_trade
	choice.pressed.emit()
	choice.pressed.emit()
	await tree.process_frame
	_check.call(session.state().inventory.herb_lingzhi == 1 and session.state().spirit_stones == before.spirit_stones - 10 and not session.is_busy() and hub.option_buttons.has("event_old_grove"), "P5 UI: Deterministic exploration choice grants rare herb and charges once")
	hub.option_buttons.event_qinglan.pressed.emit()
	await tree.process_frame
	var rng_before: Dictionary = session.state().rng_states
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	tree.root.push_input(cancel)
	await tree.process_frame
	_check.call(room.phase == "idle" and not hub.visible and not session.is_busy() and session.state().pending_exploration.is_empty() and session.state().rng_states == rng_before, "P5 UI: Escape leaves pending event safely and restores room")
	# Deplete resources through existing services; UI itself never writes inventory.
	var inventory := Inventory.new(session.content)
	var economy := Economy.new(session.content)
	var state: Dictionary = session.state()
	inventory.consume_items(session._state, state.inventory, "empty-inventory")
	economy.change_stones(session._state, -state.spirit_stones, "empty-wallet")
	room.open_resources(3)
	await tree.process_frame
	_check.call(hub.message.text.contains("免费休整") and not hub.message.text.contains("已进入秘境"), "P5 UI: Switching tabs clears stale event feedback")
	_check.call(not hub.forage_button.disabled and hub.rest_button.disabled and hub.status.text.contains("灵石 0"), "P5 UI: Zero-wallet and empty inventory expose free recovery")
	var gather: Button = hub.forage_button
	gather.pressed.emit()
	gather.pressed.emit()
	await tree.process_frame
	_check.call(session.state().inventory == {"herb_lingcao": 2, "herb_qinghua": 1} and session.state().forage_uses == 1 and hub.forage_button.disabled and session.state().spirit_stones == 0, "P5 UI: Free forage grants exactly one furnace once without charging")
	for i in range(2):
		inventory.consume_items(session._state, session.state().inventory, "consume-%d" % i)
		hub.refresh()
		hub.forage_button.pressed.emit()
		await tree.process_frame
	_check.call(hub.forage_button.disabled and not hub.rest_button.disabled, "P5 UI: Exhausted forage exposes free rest")
	hub.rest_button.pressed.emit()
	await tree.process_frame
	_check.call(session.state().forage_uses == 0 and session.state().resource_stats.rests == 1 and session.state().spirit_stones == 0, "P5 UI: Rest refreshes three charges with no time or money gate")
	# All content tabs fit the design area, including the minimum window.
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 720)]:
		tree.root.size = window_size
		for tab in range(4):
			hub.tabs.current_tab = tab
			await tree.process_frame
			await tree.process_frame
			var panel: Control = hub.close_button.get_parent().get_parent()
			_check.call(Rect2(Vector2.ZERO, room.size).encloses(panel.get_global_rect()) and Rect2(Vector2.ZERO, room.size).encloses(hub.close_button.get_global_rect()), "P5 UI: Resource tab %d fits %s" % [tab, window_size])
	hub.close_hub()
	main.queue_free()
	await tree.process_frame
	return true
