extends Control
## Presentation and input only. All resource changes go through GameSession.

signal back_requested

const Session := preload("res://scripts/core/game_session.gd")
const FurnaceArt := preload("res://scripts/ui/furnace_art.gd")
const ResourceHub := preload("res://scripts/ui/resource_hub.gd")
const GOLD := Color("d4c28e")
const MUTED := Color("92a394")
const QUALITY_NAMES := {"common": "凡品", "good": "良品", "superior": "上品", "legendary": "极品"}
const STRATEGIES := ["normal", "stable", "rush"]
var session: Session
var selected_recipe := "recipe_juling"
var phase := "idle"
var recipe_list: ItemList
var search: LineEdit
var tier_filter: OptionButton
var description: Label
var materials: Label
var recipe_details: ScrollContainer
var batches: SpinBox
var buy_button: Button
var unlock_button: Button
var selectors: Dictionary = {}
var token_button: Button
var brew_button: Button
var back_button: Button
var sell_button: Button
var skip_button: Button
var quick: CheckButton
var status: Label
var notice: Label
var rate: Label
var legendary: Label
var quality_labels: Dictionary = {}
var costs: Label
var refunds: Label
var furnace_title: Label
var flame_title: Label
var phase_label: Label
var art: Control
var progress: ProgressBar
var recent: ItemList
var result_overlay: ColorRect
var result_title: Label
var result_body: Label
var result_sell: Button
var result_close: Button
var reveal_timer: Timer
var chapter: Label
var save_hint: Label
var resource_hub: Control
var resource_buttons: Array[Button] = []
var _refreshing := false
var _trade_lock := false
var _focus_modes: Array[Dictionary] = []
var _current_result: Dictionary = {}
var _brewing_state: Dictionary = {}
var _brewing_preview: Dictionary = {}
var _brewing_products: Dictionary = {}


func _ready() -> void:
	_compact_theme()
	_build()
	reveal_timer = Timer.new()
	reveal_timer.one_shot = true
	reveal_timer.wait_time = 5.0
	reveal_timer.timeout.connect(finish_brew)
	add_child(reveal_timer)
	_build_result()
	resource_hub = Control.new()
	resource_hub.set_script(ResourceHub)
	resource_hub.session = session
	add_child(resource_hub)
	resource_hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resource_hub.closed.connect(_close_resources)
	resource_hub.changed.connect(refresh)
	resource_hub.reborn.connect(_reset_run_view)
	quick.button_pressed = session.meta().get("quality_of_life_unlocks", []).has("quick_reveal")
	refresh()


func _compact_theme() -> void:
	theme = load("res://themes/alchemy_theme.tres").duplicate(true)
	theme.default_font_size = 16
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = theme.get_stylebox(state, "Button").duplicate(true)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		theme.set_stylebox(state, "Button", style)
		var option_style: StyleBoxFlat = style.duplicate(true)
		option_style.content_margin_top = 4
		option_style.content_margin_bottom = 4
		theme.set_stylebox(state, "OptionButton", option_style)
	var panel: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer").duplicate(true)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	panel.border_color = Color("354d40")
	theme.set_stylebox("panel", "PanelContainer", panel)
	var input_style: StyleBoxFlat = theme.get_stylebox("normal", "Button").duplicate(true)
	theme.set_stylebox("normal", "LineEdit", input_style)
	theme.set_color("font_color", "LineEdit", Color("d5ddcb"))
	theme.set_color("font_color", "OptionButton", Color("d5ddcb"))
	theme.set_color("font_color", "ItemList", Color("d5ddcb"))
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color("0d1b1b")
	list_style.content_margin_left = 8
	list_style.content_margin_top = 8
	list_style.content_margin_right = 8
	list_style.content_margin_bottom = 8
	theme.set_stylebox("panel", "ItemList", list_style)


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("0c1919")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	header.add_child(heading)
	_label(heading, "青岚丹房", 25, GOLD)
	chapter = _label(heading, "第一章  /  破炉丹童", 13, MUTED)
	status = _label(header, "", 17, Color("c4d3bf"))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_button = _button(header, "返回山门", _back)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	_build_recipes(_panel(columns, 286))
	var center := _panel(columns, 300)
	center.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_center(center)
	_build_configuration(_panel(columns, 344))
	var footer := HBoxContainer.new()
	page.add_child(footer)
	notice = _label(footer, "先选丹方，再配火候；初始药材已放入背包。", 13, MUTED)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in range(8):
		var button := _button(footer, ["坊市", "委托", "秘境", "采药", "丹师", "图鉴", "存档", "轮回"][index], open_resources.bind(index))
		resource_buttons.append(button)
	save_hint = _label(footer, "", 13, MUTED)
	save_hint.custom_minimum_size.x = 180
	save_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_recipes(column: VBoxContainer) -> void:
	_label(column, "丹方手记", 21, GOLD)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	search = LineEdit.new()
	search.placeholder_text = "搜索丹方"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	search.text_changed.connect(func(_text: String) -> void: _render_recipes(session.state()))
	tier_filter = OptionButton.new()
	tier_filter.add_item("全部")
	tier_filter.set_item_metadata(0, 0)
	var tiers: Array[int] = []
	for recipe in session.content.get_items("recipes"):
		if not tiers.has(recipe.tier):
			tiers.append(recipe.tier)
	tiers.sort()
	for tier in tiers:
		tier_filter.add_item(_tier_name(tier))
		tier_filter.set_item_metadata(tier_filter.item_count - 1, tier)
	filters.add_child(tier_filter)
	tier_filter.item_selected.connect(func(_index: int) -> void: _render_recipes(session.state()))
	recipe_list = ItemList.new()
	recipe_list.name = "RecipeList"
	recipe_list.custom_minimum_size.y = 136
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.allow_reselect = true
	recipe_list.add_theme_constant_override("v_separation", 8)
	column.add_child(recipe_list)
	recipe_list.item_selected.connect(func(index: int) -> void:
		if phase != "idle" or _trade_lock:
			return
		selected_recipe = recipe_list.get_item_metadata(index)
		recipe_details.scroll_vertical = 0
		refresh()
	)
	recipe_details = ScrollContainer.new()
	recipe_details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_details.custom_minimum_size.y = 120
	column.add_child(recipe_details)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	recipe_details.add_child(details)
	description = _label(details, "", 15, MUTED, true)
	_label(details, "药材  ·  持有 / 所需", 14, GOLD)
	materials = _label(details, "", 15, Color("d5ddcb"), true)
	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	column.add_child(buy_row)
	batches = SpinBox.new()
	batches.min_value = 1
	batches.max_value = 10
	batches.step = 1
	batches.value = 1
	batches.suffix = "炉"
	batches.custom_minimum_size.x = 68
	buy_row.add_child(batches)
	batches.value_changed.connect(func(_value: float) -> void: refresh())
	buy_button = _button(buy_row, "买药材", buy_materials)
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlock_button = _button(column, "研习丹方", buy_recipe)


func _build_center(column: VBoxContainer) -> void:
	column.add_theme_constant_override("separation", 8)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(title_row)
	furnace_title = _label(title_row, "凡铁丹炉", 21, GOLD)
	flame_title = _label(title_row, "凡火", 14, MUTED)
	art = Control.new()
	art.name = "FurnaceArt"
	art.set_script(FurnaceArt)
	art.custom_minimum_size.y = 164
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	phase_label = _label(column, "药材就绪，静候一缕丹香。", 16, GOLD)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 6
	column.add_child(progress)
	var animation_row := HBoxContainer.new()
	column.add_child(animation_row)
	quick = CheckButton.new()
	quick.text = "快速揭晓"
	quick.button_pressed = AppSettings.reduced_motion
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_row.add_child(quick)
	quick.toggled.connect(func(enabled: bool) -> void:
		if enabled and phase == "brewing":
			finish_brew()
	)
	skip_button = _button(animation_row, "跳过动画", finish_brew)
	skip_button.hide()
	_label(column, "炉火留痕  ·  最近二十炉", 15, MUTED)
	recent = ItemList.new()
	recent.custom_minimum_size.y = 76
	column.add_child(recent)
	sell_button = _button(column, "出售全部产物", sell_products)


func _build_configuration(column: VBoxContainer) -> void:
	_label(column, "配炉 · 控火", 21, GOLD)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 10)
	scroll.add_child(contents)
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.add_theme_constant_override("h_separation", 12)
	equipment_grid.add_theme_constant_override("v_separation", 8)
	contents.add_child(equipment_grid)
	for definition in [["furnace_id", "丹炉"], ["flame_id", "异火"], ["consumable_id", "符箓"], ["strategy", "策略"]]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equipment_grid.add_child(row)
		_label(row, definition[1], 13, MUTED)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.fit_to_longest_item = false
		option.custom_minimum_size.y = 32
		row.add_child(option)
		selectors[definition[0]] = option
		option.item_selected.connect(func(_index: int) -> void:
			if not _refreshing:
				refresh()
		)
	token_button = _button(contents, "购买所选符箓", buy_token)
	rate = _label(contents, "80.0%", 36, GOLD)
	rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var caption := _label(contents, "本炉成功率", 14, MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(contents, "成功后的品质分布", 14, GOLD)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	contents.add_child(grid)
	for quality in QUALITY_NAMES:
		quality_labels[quality] = _label(grid, "", 15, Color("c4d3bf"))
	legendary = _label(contents, "", 15, GOLD, true)
	costs = _label(contents, "", 14, MUTED, true)
	refunds = _label(contents, "", 14, MUTED, true)
	brew_button = _button(column, "开炉 · 聚灵丹", begin_brew)
	brew_button.name = "BrewButton"
	brew_button.custom_minimum_size.y = 48
	brew_button.add_theme_font_size_override("font_size", 20)
	brew_button.add_theme_color_override("font_color", GOLD)


func _build_result() -> void:
	result_overlay = ColorRect.new()
	result_overlay.name = "ResultOverlay"
	result_overlay.color = Color(0.015, 0.035, 0.03, 0.91)
	add_child(result_overlay)
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	result_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 620
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	result_title = _label(column, "", 30, GOLD)
	result_body = _label(column, "", 17, Color("d5ddcb"), true)
	result_body.custom_minimum_size.x = 580
	result_sell = _button(column, "出售全部产物", sell_products)
	result_close = _button(column, "收丹 · 继续修行", close_result)
	result_overlay.hide()


func refresh() -> void:
	if not is_node_ready() or session == null or not session.has_run():
		return
	_refreshing = true
	var state: Dictionary = _brewing_state.duplicate(true) if phase == "brewing" else session.state()
	var rank_name := "丹童" if state.rank == 0 else ("炼丹大宗师" if state.rank == 10 else "%d品丹师" % state.rank)
	chapter.text = ["第一章 / 破炉丹童", "第二章 / 初窥丹道", "第三章 / 丹会问道", "第四章 / 九品登极", "终章 / 道成宗师"][0 if state.rank == 0 else 1 if state.rank <= 3 else 2 if state.rank <= 6 else 3 if state.rank <= 9 else 4]
	save_hint.text = "未启用磁盘存档" if session.save_path.is_empty() else ("保存失败 · 请在存档页重试" if session.save_status.get("ok") == false else "已从备份恢复" if session.save_status.get("result", {}).get("recovered", false) else "行动后自动保存")
	save_hint.tooltip_text = session.save_status.get("message", "")
	status.text = "第%d世 · %s · 历练%d · 心得%d · 灵石%d" % [state.run_number, rank_name, state.exp, state.research_points, state.spirit_stones]
	_render_recipes(state)
	var recipe: Dictionary = session.content.get_item(selected_recipe)
	description.text = "%s  ·  %s\n%s" % [recipe.name, _tier_name(recipe.tier), recipe.description]
	var lines: Array[String] = []
	for id in recipe.materials:
		var owned: int = state.inventory.get(id, 0)
		var required: int = recipe.materials[id]
		lines.append("%s   %d / %d%s" % [session.content.get_item(id).name, owned, required, "  不足" if owned < required else ""])
		if not session.content.get_item(id).shop_available:
			var sources := session.material_sources(id)
			if not sources.is_empty():
				var source: Dictionary = sources[0]
				lines.append("  来源：%s · %d品" % [source.event_name, source.required_rank])
	materials.text = "\n".join(lines)
	_populate_equipment(state)
	var setup := current_setup()
	var preview: Dictionary = {"ok": true, "result": _brewing_preview} if phase == "brewing" else session.preview(selected_recipe, setup)
	var idle: bool = phase == "idle" and not _trade_lock
	if preview.ok:
		var view: Dictionary = preview.result
		rate.text = "%.1f%%" % (view.success_rate * 100)
		rate.tooltip_text = "引擎最终概率；成功后再独立判定品质。天赋%+.1f / 天地%+.1f / 传承%+.1f 个百分点" % [view.success_breakdown.get("talent", 0.0) * 100, view.success_breakdown.get("world", 0.0) * 100, view.success_breakdown.get("inheritance", 0.0) * 100]
		for quality in QUALITY_NAMES:
			quality_labels[quality].text = "%s  %.1f%%" % [QUALITY_NAMES[quality], view.quality_probabilities[quality] * 100]
		legendary.text = "单炉极品概率  %.2f%%" % (view.legendary_per_attempt * 100)
		costs.text = "本炉材料价值：%s\n符箓消耗：%s" % [_money(view.material_shop_cost), _names(view.consumables)]
		refunds.text = "失败返还：%s\n另得丹渣×1、历练+%d、心得+%d" % [_names(view.failure_returns), view.exp_rewards.failure, view.research_rewards.base]
		brew_button.disabled = not idle or not view.can_execute
		brew_button.tooltip_text = "材料或符箓不足，请先补充。" if not view.can_execute else "扣除本炉材料，按公开概率炼制。"
	else:
		rate.text = "—"
		legendary.text = preview.message
		for quality in QUALITY_NAMES:
			quality_labels[quality].text = QUALITY_NAMES[quality] + "  —"
		costs.text = "先习得丹方，再查看本炉概率。"
		refunds.text = ""
		brew_button.disabled = true
	brew_button.text = "炼制中…" if phase == "brewing" else "开炉 · " + recipe.name
	var quoted := session.quote_materials(selected_recipe, int(batches.value))
	buy_button.text = "购药 · %d" % quoted.result.total if quoted.ok else "买药材"
	buy_button.disabled = not idle or not quoted.ok
	buy_button.tooltip_text = "购入 %d 炉完整药材（不含符箓）。" % int(batches.value) if quoted.ok else quoted.message
	var unlocked: bool = state.unlocked_recipes.has(selected_recipe)
	unlock_button.visible = not unlocked
	var recipe_quote := session.quote_item(selected_recipe)
	unlock_button.text = "研习丹方 · %d" % recipe_quote.result.total if recipe_quote.ok else "尚未达到获取条件"
	unlock_button.disabled = not idle or not recipe_quote.ok
	unlock_button.tooltip_text = recipe_quote.message if not recipe_quote.ok else "花费灵石，习得本次修行可用的丹方。"
	var token: String = setup.consumable_id
	token_button.visible = not token.is_empty()
	var token_quote := session.quote_item(token)
	token_button.text = "购符 · %d 灵石" % token_quote.result.total if token_quote.ok else "购买所选符箓"
	token_button.disabled = not idle or token.is_empty() or not token_quote.ok
	token_button.tooltip_text = "先选择一件符箓。" if token.is_empty() else ("购入一件所选符箓。" if token_quote.ok else token_quote.message)
	furnace_title.text = session.content.get_item(setup.furnace_id).name
	flame_title.text = " / " + session.content.get_item(setup.flame_id).name
	for option in selectors.values():
		option.disabled = not idle
	search.editable = idle
	tier_filter.disabled = not idle
	recipe_list.mouse_filter = Control.MOUSE_FILTER_STOP if idle else Control.MOUSE_FILTER_IGNORE
	recipe_list.focus_mode = Control.FOCUS_ALL if idle else Control.FOCUS_NONE
	batches.editable = idle
	back_button.disabled = not idle
	for button in resource_buttons:
		button.disabled = not idle
	var products: Dictionary = _brewing_products if phase == "brewing" else session.quote_products()
	var sale_text := "出售全部产物 · %d 灵石" % products.result.total if products.ok else "暂无丹药或丹渣可售"
	sell_button.text = sale_text
	sell_button.disabled = not idle or not products.ok
	sell_button.tooltip_text = "出售背包内全部丹药与丹渣，不出售药材或符箓。"
	result_sell.text = sale_text
	result_sell.disabled = phase != "result" or _trade_lock or not products.ok
	recent.clear()
	var history := session.history()
	if history.is_empty():
		recent.add_item("开炉后，这里将留下丹道足迹。")
	for record in history:
		var pill_name: String = session.content.get_item(record.snapshot.recipe_id).name
		var summary := "%s · %s×%d" % [pill_name, QUALITY_NAMES[record.quality], record.quantity] if record.success else pill_name + " · 未成丹，丹渣×1"
		recent.add_item(summary)
		recent.set_item_tooltip(recent.item_count - 1, "消耗：%s\n返还：%s\n历练+%d / 心得+%d" % [_names(record.consumed), _names(record.returned), record.exp_gained, record.research_gained])
	_refreshing = false


func _render_recipes(state: Dictionary) -> void:
	recipe_list.clear()
	for recipe in session.content.get_items("recipes"):
		if not search.text.strip_edges().is_empty() and not recipe.name.contains(search.text.strip_edges()):
			continue
		var tier: int = tier_filter.get_item_metadata(tier_filter.selected)
		if tier > 0 and recipe.tier != tier:
			continue
		var learned: bool = state.get("unlocked_recipes", []).has(recipe.id)
		recipe_list.add_item("%s  %s" % [recipe.name, "· 未习得" if not learned else "· 已习得"])
		var index := recipe_list.item_count - 1
		recipe_list.set_item_metadata(index, recipe.id)
		recipe_list.set_item_tooltip(index, recipe.description)
		if not learned:
			recipe_list.set_item_custom_fg_color(index, MUTED)
		if recipe.id == selected_recipe:
			recipe_list.select(index)


func _populate_equipment(state: Dictionary) -> void:
	for field in ["furnace_id", "flame_id", "consumable_id", "strategy"]:
		var option: OptionButton = selectors[field]
		var old: String = str(option.get_item_metadata(option.selected)) if option.selected >= 0 else ""
		option.clear()
		if field == "strategy":
			for index in range(3):
				option.add_item(["正常炼制", "稳妥炼制", "冲击极品"][index])
				option.set_item_metadata(index, STRATEGIES[index])
		else:
			var category: String = {"furnace_id": "furnaces", "flame_id": "flames", "consumable_id": "consumables"}[field]
			if field == "consumable_id":
				option.add_item("不使用符箓")
				option.set_item_metadata(0, "")
			for item in session.content.get_items(category):
				var owned: bool = true
				var title: String = item.name
				if field == "consumable_id":
					title += " ×%d" % state.inventory.get(item.id, 0)
				else:
					owned = state["owned_furnaces" if field == "furnace_id" else "owned_flames"].has(item.id)
					if not owned:
						title += " · 未拥有"
				option.add_item(title)
				var index := option.item_count - 1
				option.set_item_metadata(index, item.id)
				option.set_item_disabled(index, not owned)
				option.get_popup().set_item_tooltip(index, item.description)
		var fallback: String = {"furnace_id": state.equipped_furnace, "flame_id": state.equipped_flame, "consumable_id": "", "strategy": "normal"}[field]
		var target := old if not old.is_empty() else fallback
		for index in range(option.item_count):
			if option.get_item_metadata(index) == target and not option.is_item_disabled(index):
				option.select(index)
				break


func current_setup() -> Dictionary:
	var setup: Dictionary = {}
	for field in selectors:
		var option: OptionButton = selectors[field]
		setup[field] = option.get_item_metadata(option.selected)
	return setup


func begin_brew() -> void:
	if phase != "idle" or _trade_lock:
		return
	_brewing_state = session.state()
	_brewing_products = session.quote_products()
	phase = "brewing"
	brew_button.disabled = true
	var outcome := session.begin_brew(selected_recipe, current_setup())
	if not outcome.ok:
		phase = "idle"
		notice.text = outcome.message
		refresh()
		return
	_brewing_preview = outcome.result.snapshot.duplicate(true)
	art.set_brewing(true)
	phase_label.text = "灵气入炉 · 火候渐成"
	skip_button.show()
	reveal_timer.start()
	refresh()
	if quick.button_pressed or AppSettings.reduced_motion:
		call_deferred("finish_brew")
	else:
		skip_button.grab_focus()


func _process(_delta: float) -> void:
	if phase == "brewing" and is_instance_valid(reveal_timer):
		progress.value = 100 * (1.0 - reveal_timer.time_left / reveal_timer.wait_time)


func finish_brew() -> void:
	if phase != "brewing":
		return
	phase = "result"
	reveal_timer.stop()
	art.set_brewing(false)
	skip_button.hide()
	progress.value = 100
	var outcome := session.finish_brew()
	if not outcome.ok:
		phase = "idle"
		notice.text = outcome.message
		refresh()
		return
	_current_result = outcome.result
	var record := _current_result
	var name_text: String = session.content.get_item(record.snapshot.recipe_id).name
	result_title.text = "%s · %s ×%d" % [name_text, QUALITY_NAMES[record.quality], record.quantity] if record.success else "火候未成 · 丹渣 ×1"
	result_body.text = "消耗：%s\n返还：%s\n\n历练 +%d     研究心得 +%d%s\n\n可留丹交付宗门委托，也可出售全部丹药与丹渣。" % [_names(record.consumed), _names(record.returned), record.exp_gained, record.research_gained, "\n首次发现此丹方与品质，额外心得已计入。" if record.new_quality else ""]
	phase_label.text = "丹成留香" if record.success else "失败亦有心得，再修一炉。"
	refresh()
	_lock_background()
	result_overlay.show()
	result_close.grab_focus()


func close_result() -> void:
	if phase != "result":
		return
	result_overlay.hide()
	for entry in _focus_modes:
		if is_instance_valid(entry.node):
			entry.node.focus_mode = entry.mode
	_focus_modes.clear()
	phase = "idle"
	progress.value = 0
	refresh()
	brew_button.grab_focus()


func _lock_background(modal: Control = null) -> void:
	if modal == null:
		modal = result_overlay
	_focus_modes.clear()
	for control in find_children("*", "Control", true, false):
		if control != modal and not modal.is_ancestor_of(control) and control.focus_mode != Control.FOCUS_NONE:
			_focus_modes.append({"node": control, "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE


func buy_materials() -> void:
	if phase == "idle":
		_trade(func() -> Dictionary: return session.buy_materials(selected_recipe, int(batches.value)), "药材已入背包。")


func buy_recipe() -> void:
	if phase == "idle":
		_trade(func() -> Dictionary: return session.buy_item(selected_recipe), "丹方已习得，可开始配药。")


func buy_token() -> void:
	if phase == "idle":
		_trade(func() -> Dictionary: return session.buy_item(current_setup().consumable_id), "符箓已入背包。")


func sell_products() -> void:
	if phase in ["idle", "result"]:
		_trade(func() -> Dictionary: return session.sell_products(), "丹药与丹渣已售出。")


func _trade(operation: Callable, message: String) -> void:
	if _trade_lock:
		return
	_trade_lock = true
	var outcome: Dictionary = operation.call()
	notice.text = message + (" 灵石 %+d" % outcome.result.spirit_stones_delta if outcome.result.has("spirit_stones_delta") else "") if outcome.ok else outcome.message
	if phase == "result":
		result_body.text += "\n\n已售出全部产物，收入 %d 灵石。" % outcome.result.total if outcome.ok else "\n\n" + outcome.message
	refresh()
	call_deferred("_release_trade")


func _release_trade() -> void:
	_trade_lock = false
	refresh()
	if phase == "result":
		# Refresh does not change modal state or re-enable background focus.
		for entry in _focus_modes:
			if is_instance_valid(entry.node):
				entry.node.focus_mode = Control.FOCUS_NONE
		if result_sell.disabled:
			result_close.grab_focus()


func _back() -> void:
	if phase == "idle" and not _trade_lock:
		back_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if phase == "hub":
			resource_hub.close_hub()
		elif phase == "brewing":
			finish_brew()
		elif phase == "result":
			close_result()
		else:
			_back()
		get_viewport().set_input_as_handled()


func open_resources(index: int) -> void:
	if phase != "idle" or _trade_lock:
		return
	phase = "hub"
	refresh()
	resource_hub.open_tab(index)
	_lock_background(resource_hub)
	resource_hub.tabs.grab_focus()


func _close_resources() -> void:
	for entry in _focus_modes:
		if is_instance_valid(entry.node):
			entry.node.focus_mode = entry.mode
	_focus_modes.clear()
	phase = "idle"
	refresh()
	resource_buttons[0].grab_focus()


func _panel(parent: Node, minimum_width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minimum_width
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return column


func _label(parent: Node, text: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _names(quantities: Dictionary) -> String:
	if quantities.is_empty():
		return "无"
	var parts: Array[String] = []
	for id in quantities:
		parts.append("%s×%d" % [session.content.get_item(id).name, quantities[id]])
	return "、".join(parts)


func _money(value: Variant) -> String:
	return "%d 灵石" % value if value is int else "含非卖素材，暂无商店总价"


func _tier_name(tier: int) -> String:
	return ["一品", "二品", "三品", "四品", "五品", "六品", "七品", "八品", "九品"][tier - 1]


func _reset_run_view() -> void:
	selected_recipe = "recipe_juling"
	search.text = ""
	tier_filter.select(0)
	batches.value = 1
	for option in selectors.values():
		option.select(0)
	phase_label.text = "新一世已启，药材就绪。"
	notice.text = "永久图鉴与传承已保留，可开始本世修行。"
	_current_result.clear()
	_brewing_state.clear()
	_brewing_preview.clear()
	_brewing_products.clear()
	reveal_timer.stop()
	quick.button_pressed = session.meta().quality_of_life_unlocks.has("quick_reveal")
	refresh()
