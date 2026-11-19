class_name ContentDB
extends RefCounted
## Explicitly owned content repository; no UI or gameplay state dependencies.

const Validator := preload("res://scripts/core/content_validator.gd")

var _items: Dictionary = {}
var _category_ids: Dictionary = {}


func load_directory(directory: String = "res://data") -> Dictionary:
	var documents: Dictionary = {}
	var errors: Array[Dictionary] = []
	for category in Validator.CATEGORIES:
		var path := directory.path_join(category + ".json")
		if not FileAccess.file_exists(path):
			errors.append({"code": "FILE_NOT_FOUND", "path": path, "message": "内容文件不存在。"})
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append({"code": "FILE_READ_ERROR", "path": path, "message": "内容文件无法读取：%s" % error_string(FileAccess.get_open_error())})
			continue
		var source := file.get_as_text()
		var read_error := file.get_error()
		file.close()
		if read_error != OK:
			errors.append({"code": "FILE_READ_ERROR", "path": path, "message": "内容文件读取失败：%s" % error_string(read_error)})
			continue
		var json := JSON.new()
		if json.parse(source) != OK:
			errors.append({"code": "INVALID_JSON", "path": path, "line": json.get_error_line(), "message": "JSON 解析失败：%s" % json.get_error_message()})
			continue
		documents[category] = json.data
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return load_documents(documents)


func load_documents(documents: Dictionary) -> Dictionary:
	var errors := Validator.new().validate_documents(documents)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var next_items: Dictionary = {}
	var next_category_ids: Dictionary = {}
	for category in Validator.CATEGORIES:
		var ids: Array[String] = []
		for item in documents[category].items:
			ids.append(item.id)
			next_items[item.id] = _normalize_item(category, item)
		next_category_ids[category] = ids
	# Swap only after every file and reference has passed validation.
	_items = next_items
	_category_ids = next_category_ids
	return {"ok": true, "errors": [], "counts": get_counts()}


func _normalize_item(category: String, source: Dictionary) -> Dictionary:
	# Godot JSON decodes all numbers as floats. Convert only validated integers.
	var item := source.duplicate(true)
	for field in ["tier", "required_rank", "base_sell_price", "buy_price", "sell_price", "quantity", "reward_spirit_stones", "reward_exp", "rank_index", "exp_required", "research_cost", "choice_rank", "substitution_ratio", "min_completed_runs", "min_run_number"]:
		if item.has(field):
			item[field] = int(item[field])
	for field in ["required_rank", "price"]:
		if item.unlock.has(field):
			item.unlock[field] = int(item.unlock[field])
	if category == "recipes":
		for id in item.materials:
			item.materials[id] = int(item.materials[id])
	if category == "consumables" and item.has("research_bonus"):
		item.research_bonus = int(item.research_bonus)
	if category == "quests":
		_normalize_quantities(item.reward_items)
	if category == "exploration_events":
		for option in item.options:
			for field in ["cost_stones", "success_stones", "failure_stones"]:
				option[field] = int(option[field])
			for field in ["cost_items", "success_items", "failure_items"]:
				_normalize_quantities(option[field])
	return item


func _normalize_quantities(items: Dictionary) -> void:
	for id in items:
		items[id] = int(items[id])


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> Dictionary:
	return _items.get(id, {}).duplicate(true)


func get_ids(category: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_category_ids.get(category, []))
	return ids


func get_items(category: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for id in get_ids(category):
		items.append(get_item(id))
	return items


func get_counts() -> Dictionary:
	var counts: Dictionary = {}
	for category in Validator.CATEGORIES:
		counts[category] = _category_ids.get(category, []).size()
	return counts
