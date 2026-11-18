class_name ContentValidator
extends RefCounted
## Pure validation of schema-v1 content. Never changes input or game state.

const CATEGORIES := ["recipes", "materials", "furnaces", "flames", "consumables"]
const QUALITIES := ["common", "good", "superior", "legendary"]
const MAX_INTEGER := 2147483647
const COMMON_FIELDS := ["id", "name", "description", "tier", "tags", "unlock"]
const EQUIPMENT_FIELDS := ["success_bonus", "quality_transfers", "material_refund_bonus", "extra_pill_chance", "effect_tags", "effect_ids"]
const CATEGORY_FIELDS := {
	"recipes": ["required_rank", "base_success_rate", "materials", "quality_weights", "base_sell_price", "special_rules"],
	"materials": ["category", "buy_price", "sell_price", "shop_available", "sources", "repeatable"],
	"furnaces": EQUIPMENT_FIELDS,
	"flames": EQUIPMENT_FIELDS,
	"consumables": ["success_bonus", "quality_transfers", "material_refund_bonus", "extra_pill_chance", "effect_tags", "effect_ids", "effect_category", "shop_available", "sell_price"],
}
const MATERIAL_CATEGORIES := ["herb", "mineral", "beast", "spirit"]
const MATERIAL_SOURCES := ["shop", "forage", "exploration", "quest", "research"]
const UNLOCK_TYPES := ["initial", "shop", "rank", "exploration"]

var _id_pattern := RegEx.create_from_string("^[a-z][a-z0-9]*(_[a-z0-9]+)+$")
var _tag_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


func validate_documents(documents: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var ids: Dictionary = {}
	var material_ids: Dictionary = {}
	for category in documents:
		if category not in CATEGORIES:
			_error(errors, "UNKNOWN_CATEGORY", str(category), "未知内容分类。")
	for category in CATEGORIES:
		if not documents.has(category):
			_error(errors, "MISSING_CATEGORY", category, "缺少内容表。")
			continue
		var document: Variant = documents[category]
		if not _shape(document, ["schema_version", "items"], category, errors):
			continue
		if not _integer(document.get("schema_version"), 1, 1, category + ".schema_version", errors):
			continue
		var items: Variant = document.get("items")
		if not items is Array:
			_error(errors, "INVALID_TYPE", category + ".items", "内容列表必须是数组。")
			continue
		if items.is_empty():
			_error(errors, "EMPTY_ITEMS", category + ".items", "内容表不能为空。")
		for index in range(items.size()):
			var path := "%s.items[%d]" % [category, index]
			var item: Variant = items[index]
			if not _shape(item, COMMON_FIELDS + CATEGORY_FIELDS[category], path, errors):
				continue
			_validate_common(item, path, errors)
			var id: Variant = item.get("id")
			if id is String and _id_pattern.search(id) != null:
				if ids.has(id):
					_error(errors, "DUPLICATE_ID", path + ".id", "ID 与 %s 重复。" % ids[id])
				else:
					ids[id] = path
				if category == "materials":
					material_ids[id] = true
			match category:
				"recipes":
					_validate_recipe(item, path, errors)
				"materials":
					_validate_material(item, path, errors)
				_:
					_validate_equipment(item, category, path, errors)
	# Resolve references only after every table has been inspected.
	var recipes: Variant = documents.get("recipes")
	if recipes is Dictionary and recipes.get("items") is Array:
		for index in range(recipes.items.size()):
			var recipe: Variant = recipes.items[index]
			if recipe is Dictionary and recipe.get("materials") is Dictionary:
				for material_id in recipe.materials:
					if not material_ids.has(material_id):
						_error(errors, "MISSING_REFERENCE", "recipes.items[%d].materials.%s" % [index, material_id], "丹方引用的材料不存在。")
	return errors


func _validate_common(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	for field in ["id", "name", "description"]:
		_text(item.get(field), path + "." + field, errors)
	if item.get("id") is String and _id_pattern.search(item.id) == null:
		_error(errors, "INVALID_ID", path + ".id", "ID 须使用英文小写下划线格式。")
	_integer(item.get("tier"), 1, 9, path + ".tier", errors)
	_string_list(item.get("tags"), path + ".tags", errors, true)
	_validate_unlock(item.get("unlock"), path + ".unlock", errors)


func _validate_unlock(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_error(errors, "INVALID_TYPE", path, "解锁条件必须是对象。")
		return
	var kind: Variant = value.get("type")
	if not _enum(kind, UNLOCK_TYPES, path + ".type", errors):
		return
	var fields := ["type"]
	if kind != "initial":
		fields.append("required_rank")
	if kind == "shop":
		fields.append("price")
	_shape(value, fields, path, errors)
	if kind != "initial":
		_integer(value.get("required_rank"), 0, 10, path + ".required_rank", errors)
	if kind == "shop":
		_integer(value.get("price"), 0, MAX_INTEGER, path + ".price", errors)


func _validate_recipe(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_integer(item.get("required_rank"), 0, 10, path + ".required_rank", errors)
	_number(item.get("base_success_rate"), 0, 1, path + ".base_success_rate", errors)
	_integer(item.get("base_sell_price"), 0, MAX_INTEGER, path + ".base_sell_price", errors)
	var materials: Variant = item.get("materials")
	if materials is Dictionary:
		if materials.is_empty():
			_error(errors, "EMPTY_MATERIALS", path + ".materials", "丹方必须消耗材料。")
		for id in materials:
			_integer(materials[id], 1, MAX_INTEGER, path + ".materials." + str(id), errors)
	else:
		_error(errors, "INVALID_TYPE", path + ".materials", "材料需求必须是 ID 到数量的对象。")
	var weights: Variant = item.get("quality_weights")
	if _shape(weights, QUALITIES, path + ".quality_weights", errors):
		var total := 0.0
		var valid := true
		for quality in QUALITIES:
			var weight: Variant = weights.get(quality)
			if _number(weight, 0, INF, path + ".quality_weights." + quality, errors):
				total += float(weight)
			else:
				valid = false
		if valid and (not is_finite(total) or total <= 0):
			_error(errors, "INVALID_WEIGHTS", path + ".quality_weights", "权重总和必须为有限正数。")
	_no_effects(item.get("special_rules"), path + ".special_rules", errors)


func _validate_material(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_enum(item.get("category"), MATERIAL_CATEGORIES, path + ".category", errors)
	_integer(item.get("buy_price"), 0, MAX_INTEGER, path + ".buy_price", errors)
	_integer(item.get("sell_price"), 0, MAX_INTEGER, path + ".sell_price", errors)
	_boolean(item.get("shop_available"), path + ".shop_available", errors)
	_boolean(item.get("repeatable"), path + ".repeatable", errors)
	var sources: Variant = item.get("sources")
	if _string_list(sources, path + ".sources", errors):
		if sources.is_empty():
			_error(errors, "EMPTY_SOURCES", path + ".sources", "材料必须有获取来源。")
		for index in range(sources.size()):
			_enum(sources[index], MATERIAL_SOURCES, "%s.sources[%d]" % [path, index], errors)
		if item.get("shop_available") is bool and item.shop_available != sources.has("shop"):
			_error(errors, "INCONSISTENT_SHOP", path + ".shop_available", "商店可购性与来源不一致。")
	if item.get("shop_available") is bool and item.shop_available:
		if _is_number(item.get("buy_price")) and _is_number(item.get("sell_price")) and item.sell_price > item.buy_price:
			_error(errors, "ARBITRAGE_PRICE", path + ".sell_price", "商店商品卖价不能高于买价。")


func _validate_equipment(item: Dictionary, category: String, path: String, errors: Array[Dictionary]) -> void:
	_number(item.get("success_bonus"), -1, 1, path + ".success_bonus", errors)
	_number(item.get("material_refund_bonus"), 0, 1, path + ".material_refund_bonus", errors)
	_number(item.get("extra_pill_chance"), 0, 1, path + ".extra_pill_chance", errors)
	_string_list(item.get("effect_tags"), path + ".effect_tags", errors, true)
	_no_effects(item.get("effect_ids"), path + ".effect_ids", errors)
	var transfers: Variant = item.get("quality_transfers")
	if transfers is Dictionary:
		var total := 0.0
		for target in transfers:
			_enum(target, ["good", "superior", "legendary"], path + ".quality_transfers." + str(target), errors)
			if _number(transfers[target], 0, INF, path + ".quality_transfers." + str(target), errors):
				total += float(transfers[target])
		if not is_finite(total):
			_error(errors, "INVALID_TRANSFERS", path + ".quality_transfers", "转移权重总和必须为有限数值。")
	else:
		_error(errors, "INVALID_TYPE", path + ".quality_transfers", "品质转移必须是目标品质到权重点数的对象。")
	if category == "consumables":
		_enum(item.get("effect_category"), ["success", "quality", "refund"], path + ".effect_category", errors)
		_boolean(item.get("shop_available"), path + ".shop_available", errors)
		_integer(item.get("sell_price"), 0, MAX_INTEGER, path + ".sell_price", errors)
		var unlock: Variant = item.get("unlock")
		if unlock is Dictionary and item.get("shop_available") is bool:
			if item.shop_available != (unlock.get("type") == "shop"):
				_error(errors, "INCONSISTENT_SHOP", path + ".shop_available", "消耗品商店标记与解锁类型不一致。")
			if item.shop_available and _is_number(unlock.get("price")) and _is_number(item.get("sell_price")) and item.sell_price > unlock.price:
				_error(errors, "ARBITRAGE_PRICE", path + ".sell_price", "商店商品卖价不能高于买价。")


func _shape(value: Variant, fields: Array, path: String, errors: Array[Dictionary]) -> bool:
	if not value is Dictionary:
		_error(errors, "INVALID_TYPE", path, "必须是对象。")
		return false
	for field in fields:
		if not value.has(field):
			_error(errors, "MISSING_FIELD", path + "." + field, "缺少必填字段。")
	for field in value:
		if field not in fields:
			_error(errors, "UNKNOWN_FIELD", path + "." + str(field), "未知字段，可能存在拼写错误。")
	return true


func _number(value: Variant, minimum: float, maximum: float, path: String, errors: Array[Dictionary]) -> bool:
	if not _is_number(value):
		_error(errors, "INVALID_TYPE", path, "必须是有限数值，不能使用字符串或布尔值。")
		return false
	if value < minimum or value > maximum:
		_error(errors, "OUT_OF_RANGE", path, "数值超出允许范围。")
		return false
	return true


func _integer(value: Variant, minimum: int, maximum: int, path: String, errors: Array[Dictionary]) -> bool:
	if not _number(value, minimum, maximum, path, errors):
		return false
	if float(value) != floor(float(value)):
		_error(errors, "INVALID_INTEGER", path, "必须是整数。")
		return false
	return true


func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _text(value: Variant, path: String, errors: Array[Dictionary]) -> bool:
	if not value is String or value.strip_edges().is_empty():
		_error(errors, "INVALID_TEXT", path, "必须是非空字符串。")
		return false
	return true


func _enum(value: Variant, allowed: Array, path: String, errors: Array[Dictionary]) -> bool:
	if value not in allowed:
		_error(errors, "INVALID_ENUM", path, "值不在允许的选项中。")
		return false
	return true


func _boolean(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is bool:
		_error(errors, "INVALID_TYPE", path, "必须是布尔值。")


func _string_list(value: Variant, path: String, errors: Array[Dictionary], tags: bool = false) -> bool:
	if not value is Array:
		_error(errors, "INVALID_TYPE", path, "必须是字符串数组。")
		return false
	var seen: Dictionary = {}
	for index in range(value.size()):
		var entry_path := "%s[%d]" % [path, index]
		var entry: Variant = value[index]
		if not _text(entry, entry_path, errors):
			continue
		if seen.has(entry):
			_error(errors, "DUPLICATE_VALUE", entry_path, "数组不允许重复值。")
		seen[entry] = true
		if tags and _tag_pattern.search(entry) == null:
			_error(errors, "INVALID_TAG", entry_path, "标签须使用英文小写格式。")
	return true


func _no_effects(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if _string_list(value, path, errors):
		for index in range(value.size()):
			_error(errors, "UNKNOWN_EFFECT", "%s[%d]" % [path, index], "尚未注册此效果；P1 不接受脚本或效果 ID。")


func _error(errors: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append({"code": code, "path": path, "message": message})
