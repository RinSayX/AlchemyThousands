extends Control
## P5 resource views: data/quotes in, explicit service commands out.

signal closed
signal changed

const Session := preload("res://scripts/core/game_session.gd")
const GOLD := Color("d4c28e")
const MUTED := Color("92a394")
const QUALITY := {"common": "凡品", "good": "良品", "superior": "上品", "legendary": "极品"}
const HINTS := ["按商品数量查看权威报价，永久物品每次一件。", "交付会消耗丹药并立即发奖；可重复委托需要重新接单。", "入境后查看选项消耗与奖励，也可免费离开。", "已有一炉基础药材时无需采集，机会耗尽可免费休整。", "考核与定式研制均公开消耗；天赋每个阶段只能选一次。", "炼制或研制均记录发现；交付、出售不会清除图鉴。", "行动后自动保存。读档会覆盖当前内存进度，请确认后执行。"]
const CATEGORIES := ["materials", "consumables", "recipes", "furnaces", "flames"]
var session: Session
var tabs: TabBar
var scroll: ScrollContainer
var body: VBoxContainer
var status: Label
var message: Label
var close_button: Button
var shop_filter: OptionButton
var quantity: SpinBox
var shop_tools: HBoxContainer
var forage_button: Button
var rest_button: Button
var quest_buttons: Dictionary = {}
var option_buttons: Dictionary = {}
var shop_buttons: Dictionary = {}
var promote_button: Button
var study_button: Button
var talent_buttons: Dictionary = {}
var save_button: Button
var load_button: Button
var confirm_load_button: Button
var _confirm_load := false
var _locked := false
var _building := false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.02, 0.94)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_label(heading, "宗门行记", 24, GOLD)
	status = _label(heading, "", 16, MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs = TabBar.new()
	for title in ["坊市", "宗门委托", "秘境", "免费采药", "丹师晋升", "丹道图鉴", "存档"]:
		tabs.add_tab(title)
	column.add_child(tabs)
	tabs.tab_changed.connect(_tab_changed)
	shop_tools = HBoxContainer.new()
	column.add_child(shop_tools)
	shop_filter = OptionButton.new()
	for title in ["材料", "符箓", "丹方", "丹炉", "异火"]:
		shop_filter.add_item(title)
	shop_tools.add_child(shop_filter)
	shop_filter.item_selected.connect(func(_index: int) -> void: refresh())
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 99
	quantity.step = 1
	quantity.value = 1
	quantity.prefix = "数量"
	quantity.custom_minimum_size.x = 120
	shop_tools.add_child(quantity)
	quantity.value_changed.connect(func(_value: float) -> void: refresh())
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	message = _label(column, "资源、消耗与概率均在行动前展示。", 14, MUTED)
	message.custom_minimum_size.x = 870
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	close_button = _button(column, "返回丹房", close_hub)
	hide()


func open_tab(index: int) -> void:
	_confirm_load = false
	scroll.scroll_vertical = 0
	_building = true
	tabs.current_tab = 2 if not session.state().pending_exploration.is_empty() else index
	_building = false
	message.text = HINTS[tabs.current_tab]
	show()
	refresh()
	tabs.grab_focus()


func _tab_changed(index: int) -> void:
	if _building:
		return
	if not session.state().pending_exploration.is_empty() and index != 2:
		tabs.current_tab = 2
		return
	_confirm_load = false
	scroll.scroll_vertical = 0
	message.text = HINTS[index]
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var state := session.state()
	status.text = "灵石 %d   ·   行动 %d   ·   已交委托 %d" % [state.spirit_stones, state.action_count, state.resource_stats.quests_completed]
	var pending: bool = not state.pending_exploration.is_empty()
	if pending and tabs.current_tab != 2:
		_building = true
		tabs.current_tab = 2
		_building = false
	for index in range(7):
		tabs.set_tab_disabled(index, pending and index != 2)
	shop_tools.visible = tabs.current_tab == 0
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	quest_buttons.clear()
	option_buttons.clear()
	shop_buttons.clear()
	talent_buttons.clear()
	match tabs.current_tab:
		0: _shop(state)
		1: _quests()
		2: _exploration(state)
		3: _forage()
		4: _progression(state)
		5: _collection()
		6: _saves()
	close_button.disabled = _locked


func _shop(state: Dictionary) -> void:
	var category: String = CATEGORIES[shop_filter.selected]
	var q := int(quantity.value) if category in ["materials", "consumables"] else 1
	_label(body, "常驻商品按境界开放；永久物品每次一件。", 14, MUTED)
	for item in session.content.get_items(category):
		var row := _row()
		var text := _text_column(row)
		var owned: int = state.inventory.get(item.id, 0)
		_label(text, item.name + ("  ·  持有 %d" % owned if category in ["materials", "consumables"] else ""), 17, GOLD)
		_label(text, item.description, 14, MUTED, true)
		var quote := session.quote_shop(item.id, q)
		var buy := _button(row, "购买 %d · %d 灵石" % [q, quote.result.total] if quote.ok else "不可购买", _buy.bind(item.id, q))
		buy.disabled = _locked or not quote.ok
		buy.tooltip_text = "" if quote.ok else quote.message
		shop_buttons[item.id] = buy
		if category in ["materials", "consumables"]:
			var sale := session.quote_sell_item(item.id, q)
			var sell := _button(row, "卖出 %d · %d" % [q, sale.result.total] if sale.ok else "无可售数量", _sell.bind(item.id, q))
			sell.disabled = _locked or not sale.ok
			sell.tooltip_text = "" if sale.ok else sale.message


func _quests() -> void:
	var board := session.quest_board()
	if not board.ok:
		_label(body, board.message, 16, GOLD)
		return
	_label(body, "交付会实际消耗丹药；高品质可代低品质，优先消耗达标中的低品质。", 14, MUTED, true)
	for offer in board.result.rows:
		var quest: Dictionary = offer.template
		var row := _row()
		var text := _text_column(row)
		_label(text, quest.name + (" · 可重复" if quest.repeatable else " · 一次性"), 17, GOLD)
		_label(text, "%s及以上 %s×%d\n奖励：灵石%d、历练%d；%s%s" % [QUALITY[quest.min_quality], session.content.get_item(quest.required_recipe_id).name, quest.quantity, quest.reward_spirit_stones, quest.reward_exp, _names(quest.reward_items), "；" + session.content.get_item(quest.reward_flame).name if not quest.reward_flame.is_empty() else ""], 14, MUTED, true)
		var action: Button
		if not offer.active_id.is_empty():
			_label(text, "尚缺符合品质丹药 %d 枚" % offer.delivery.missing, 14, MUTED)
			action = _button(row, "交付并领取", _deliver.bind(offer.active_id))
			action.disabled = _locked or not offer.delivery.can_deliver
		else:
			action = _button(row, "再接一单" if offer.completed and quest.repeatable else ("已完成" if offer.completed else "接取委托"), _accept.bind(quest.id))
			action.disabled = _locked or not offer.can_accept
			action.tooltip_text = "需要境界 %d，并习得对应丹方。" % quest.unlock.required_rank if not offer.can_accept else ""
		quest_buttons[quest.id] = action


func _exploration(state: Dictionary) -> void:
	var pending: Dictionary = state.pending_exploration
	if pending.is_empty():
		_label(body, "入境计 1 行动，不扣灵石；可随机寻访，也可直达开放地点。", 14, MUTED, true)
		var random_button := _button(body, "随缘寻访 · 按公开权重抽取地点", _enter.bind(""))
		random_button.disabled = _locked
		for offer in session.destinations().result.rows:
			var row := _row()
			var text := _text_column(row)
			_label(text, offer.event.name, 17, GOLD)
			_label(text, "%s\n随机寻访权重占比 %.1f%% · 需要境界 %d" % [offer.event.description, offer.encounter_probability * 100, offer.event.unlock.required_rank], 14, MUTED, true)
			var visit := _button(row, "前往" if offer.unlocked else "尚未开放", _enter.bind(offer.event.id))
			visit.disabled = _locked or not offer.unlocked
			option_buttons[offer.event.id] = visit
		return
	var event: Dictionary = session.content.get_item(pending.event_id)
	_label(body, event.name, 23, GOLD)
	_label(body, event.description, 16, MUTED, true)
	for option in event.options:
		var view := session.preview_event_option(option.id)
		var row := _row()
		var text := _text_column(row)
		_label(text, "%s · 成功率 %.1f%%" % [option.name, option.success_rate * 100], 17, GOLD)
		_label(text, "消耗：灵石%d；%s\n成功：%s%s\n失败：%s\n%s" % [option.cost_stones, _names(option.cost_items), _names(option.success_items), "；" + session.content.get_item(option.reward_flame).name if not option.reward_flame.is_empty() else "", _names(option.failure_items), option.description], 14, MUTED, true)
		var choose := _button(row, "选择此行动", _resolve.bind(pending.instance_id, option.id))
		choose.disabled = _locked or not view.ok or not view.result.can_execute
		choose.tooltip_text = "费用或所需物品不足。" if view.ok and not view.result.can_execute else ""
		option_buttons[option.id] = choose
	var leave := _button(body, "离开当前事件 · 无额外消耗", _leave)
	leave.disabled = _locked


func _forage() -> void:
	var view := session.forage_status()
	if not view.ok:
		_label(body, view.message, 16, GOLD)
		return
	_label(body, "青岚山径 · 基础补给", 23, GOLD)
	_label(body, "免费补齐一炉聚灵丹所需的基础药材，已有足量时不再发放。每趟最多三次，耗尽后可免费休整，无需灵石或实时等待。", 16, MUTED, true)
	_label(body, "本趟剩余 %d 次\n本次可得：%s" % [view.result.charges_left, _names(view.result.items)], 18, GOLD, true)
	forage_button = _button(body, "免费采药 · 补齐一炉", _forage_action)
	forage_button.disabled = _locked or not view.result.can_forage
	rest_button = _button(body, "归山休整 · 免费恢复三次机会", _rest_action)
	rest_button.disabled = _locked or not view.result.can_rest
	_label(body, "恢复路线：采药 → 基础炼丹 → 留丹交委托或出售产物。即使炼制失败，也能卖出丹渣。", 15, MUTED, true)


func _progression(state: Dictionary) -> void:
	var view := session.progression()
	if not view.ok:
		_label(body, view.message, 16, GOLD)
		return
	_label(body, view.result.current.name, 24, GOLD)
	_label(body, "历练 %d · 研究心得 %d · 定式研制 %d 次" % [state.exp, state.research_points, state.research_crafts], 16, MUTED, true)
	if not state.ending.is_empty():
		_label(body, "道成大宗师 · 标准结局", 25, GOLD)
		_label(body, "凡火起于微末，九品归于丹心。你已炼成太初造化丹，通过宗门认证。

本世结算：行动 %d 次，概率开炉 %d 次，定式研制 %d 次，交付委托 %d 单，历练 %d。

可返回丹房继续收集图鉴。轮回将在后续阶段开放。" % [state.ending.action_count, state.ending.alchemy_attempts, state.ending.research_crafts, state.ending.quests_completed, state.ending.exp], 17, MUTED, true)
		return
	if not view.result.talents.is_empty():
		_label(body, "%d品天赋抉择 · 三选一，不可重选" % state.pending_talent_rank, 20, GOLD)
		for talent in view.result.talents:
			var row := _row()
			var text := _text_column(row)
			_label(text, talent.name, 17, GOLD)
			_label(text, _talent_text(talent), 14, MUTED, true)
			var choose := _button(row, "选择此天赋", _choose_talent.bind(talent.id))
			choose.disabled = _locked
			talent_buttons[talent.id] = choose
	if not state.talent_choices.is_empty():
		var names: Array[String] = []
		for id in state.talent_choices:
			names.append(session.content.get_item(id).name)
		_label(body, "本世天赋：" + "、".join(names), 14, MUTED, true)
	var target: Dictionary = view.result.next
	_label(body, "下一考核 · " + target.name, 21, GOLD)
	_label(body, "历练要求 %d；交付 %s及以上 %s×%d。
需亲自炼成或定式研制该丹；晋升会消耗考核丹药。%s%s" % [target.exp_required, QUALITY[target.min_quality], session.content.get_item(target.exam_recipe_id).name, target.quantity, "
前置委托：" + session.content.get_item(target.required_quest_id).name if not target.required_quest_id.is_empty() else "", "
异火要求：" + session.content.get_item(target.required_flame).name if not target.required_flame.is_empty() else ""], 15, MUTED, true)
	_label(body, "条件已满足，可参加认证。" if view.result.can_promote else "尚缺：" + "；".join(view.result.missing), 15, GOLD, true)
	promote_button = _button(body, "交丹认证 · 晋升" + target.name, _promote.bind(target.rank_index))
	promote_button.disabled = _locked or not view.result.can_promote
	var study := session.study_preview()
	if study.ok:
		_label(body, "定式研制 · 确定性考核路线", 19, GOLD)
		_label(body, "不掷骰，消耗心得 %d；药材：%s。必得 %s %s×1，历练 +%d，不增加概率炼丹次数。%s
心得可通过任意开炉（失败也有 +1）积累，药材可从坊市及稳定秘境选项获得。" % [study.result.research_cost, _names(study.result.cost_items), QUALITY[study.result.quality], session.content.get_item(study.result.recipe_id).name, session.content.get_item(study.result.recipe_id).tier * 10, "
百草衍化替代：" + _names(study.result.substituted) if not study.result.substituted.is_empty() else ""], 14, MUTED, true)
		study_button = _button(body, "定式研制考核丹 · 心得 %d" % study.result.research_cost, _study.bind(target.rank_index))
		study_button.disabled = _locked or not study.result.can_execute
		study_button.tooltip_text = "尚缺药材：%s；心得 %d。请先习得丹方。" % [_names(study.result.missing_items), study.result.missing_points] if not study.result.can_execute else "消耗上述药材与心得，确定性获得考核所需丹药。"


func _talent_text(talent: Dictionary) -> String:
	if talent.style == "research":
		return "定式研制心得成本减少 %.0f%%（各层相加，最多75%%）；缺少的不可购素材每份可用灵草×%d替代。" % [talent.research_discount * 100, talent.substitution_ratio]
	return "仅在%s时生效：成功率 %+.0f 个百分点；失败材料返还率 +%.0f 个百分点；向极品转移 %.0f 点权重。" % ["稳妥炼制" if talent.style == "stable" else "冲击极品", talent.success_bonus * 100, talent.material_refund_bonus * 100, talent.legendary_transfer]


func _collection() -> void:
	var view := session.collection()
	if not view.ok:
		_label(body, view.message, 16, GOLD)
		return
	_label(body, "丹道图鉴 · %d / %d" % [view.result.discovered, view.result.total], 23, GOLD)
	for row in view.result.rows:
		_label(body, row.recipe.name + (" · 已习得" if row.learned else " · 未习得"), 17, GOLD)
		var names: Array[String] = []
		for quality in row.qualities:
			names.append(QUALITY[quality] + (" 已发现" if row.qualities[quality] else " 未发现"))
		_label(body, " / ".join(names), 14, MUTED, true)


func _saves() -> void:
	_label(body, "本世修行存档", 23, GOLD)
	_label(body, "炼丹、交易、委托、探索、研制、晋升和天赋确认后自动保存。关闭后可在山门读取继续；炼制动画中关闭也不会重掷或重复发奖。", 16, MUTED, true)
	var saved := session.saved_run()
	_label(body, "最近保存：%s（UTC）%s" % [saved.result.saved_at, " · 已使用备份" if saved.result.recovered else ""] if saved.ok else saved.message, 15, MUTED, true)
	if session.save_status.get("ok") == false:
		_label(body, "保存失败：" + session.save_status.message + " 请重试。", 16, GOLD, true)
	if saved.ok and saved.result.recovered:
		_label(body, saved.result.warning, 16, GOLD, true)
	save_button = _button(body, "立即保存当前修行", _save)
	save_button.disabled = _locked or session.save_path.is_empty()
	if _confirm_load:
		_label(body, "确认读取最近存档？当前内存中的未保存进度将被覆盖。", 17, GOLD, true)
		confirm_load_button = _button(body, "确认读取并覆盖当前进度", _load)
		confirm_load_button.disabled = _locked
		_button(body, "取消读取", func() -> void: _confirm_load = false; refresh())
	else:
		load_button = _button(body, "读取最近存档…", func() -> void: _confirm_load = true; refresh())
		load_button.disabled = _locked or not saved.ok


func _promote(target: int) -> void:
	_perform(func() -> Dictionary: return session.promote(target), "晋升认证完成，新内容已解锁。")


func _study(target: int) -> void:
	_perform(func() -> Dictionary: return session.study_exam(target), "定式研制完成，考核丹药与历练已入账。")


func _choose_talent(id: String) -> void:
	_perform(func() -> Dictionary: return session.choose_talent(id), "天赋已确认，本世不可重选。")


func _save() -> void:
	_perform(session.save_run, "当前修行已保存。")


func _load() -> void:
	_confirm_load = false
	_perform(session.load_run, "已读取有效存档，进度和随机流已恢复。")


func _perform(operation: Callable, success_message: String) -> void:
	if _locked:
		return
	_locked = true
	var result: Dictionary = operation.call()
	message.text = success_message if result.ok else result.message
	if result.ok and result.result.has("items"):
		message.text += " 收获：" + _names(result.result.items)
		if result.result.has("flame") and not result.result.flame.is_empty():
			message.text += "；异火：" + session.content.get_item(result.result.flame).name
		if result.result.has("success") and not result.result.success:
			message.text = "未获珍品，带回：" + _names(result.result.items)
	changed.emit()
	refresh()
	call_deferred("_release")


func _release() -> void:
	_locked = false
	refresh()
	tabs.grab_focus()


func _buy(id: String, count: int) -> void:
	_perform(func() -> Dictionary: return session.buy_shop(id, count), "商品已入背包。")


func _sell(id: String, count: int) -> void:
	_perform(func() -> Dictionary: return session.sell_shop(id, count), "物品已出售，灵石已入账。")


func _accept(id: String) -> void:
	_perform(func() -> Dictionary: return session.accept_quest(id), "委托已接受，可留丹后交付。")


func _deliver(id: String) -> void:
	_perform(func() -> Dictionary: return session.deliver_quest(id), "委托已交付，灵石与历练已入账。")


func _enter(id: String) -> void:
	_perform(func() -> Dictionary: return session.enter_event(id), "已进入秘境，请查看消耗与奖励后选择。")


func _resolve(instance_id: String, id: String) -> void:
	_perform(func() -> Dictionary: return session.resolve_event(instance_id, id), "秘境行动已完成。")


func _leave() -> void:
	_perform(func() -> Dictionary: return session.leave_event(), "已离开当前秘境。")


func _forage_action() -> void:
	_perform(func() -> Dictionary: return session.forage(), "基础补给已采回。")


func _rest_action() -> void:
	_perform(func() -> Dictionary: return session.rest(), "山径已休整，可以再次出发。")


func close_hub() -> void:
	if _locked:
		return
	if not session.state().pending_exploration.is_empty():
		var left := session.leave_event()
		if not left.ok:
			message.text = left.message
			return
	hide()
	changed.emit()
	closed.emit()


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	return row


func _text_column(row: HBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	return column


func _label(parent: Node, text: String, size_value: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	return button


func _names(items: Dictionary) -> String:
	var parts: Array[String] = []
	for id in items:
		parts.append("%s×%d" % [session.content.get_item(id).name, items[id]])
	return "、".join(parts) if not parts.is_empty() else "无"
