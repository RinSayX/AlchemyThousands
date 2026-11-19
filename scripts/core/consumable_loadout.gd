extends RefCounted
## Pure selection validation shared by brewing and atomic purchase commands.
const Result := preload("res://scripts/core/transaction_result.gd")

static func resolve(db: RefCounted, setup: Dictionary) -> Dictionary:
	if setup.has("consumable_id") and setup.has("consumable_ids"):
		return _bad("单件与双件配置不能同时提供。")
	var ids: Array = []
	if setup.has("consumable_ids"):
		var value: Variant = setup.consumable_ids
		if not value is Array or value.size() > 2: return _bad("每炉最多选择两件消耗品。")
		ids = value.duplicate()
	else:
		var id: Variant = setup.get("consumable_id", "")
		if not id is String: return _bad("消耗品必须为单个 ID 或 consumable_ids 列表。")
		if not id.is_empty(): ids.append(id)
	var categories: Array = []
	for id in ids:
		if not id is String or id not in db.get_ids("consumables"): return _bad("所选消耗品不存在。")
		var category: String = db.get_item(id).effect_category
		if category in categories: return _bad("同一效果类别每炉只能选择一件消耗品。")
		categories.append(category)
	ids.sort()
	return Result.success({}, {"ids": ids})

static func _bad(message: String) -> Dictionary:
	return Result.failure("INVALID_SETUP", message)
