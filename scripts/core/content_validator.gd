class_name ContentValidator
extends RefCounted
## Pure validation of schema-v1 content. Never changes input or game state.

const CATEGORIES := ["recipes", "materials", "furnaces", "flames", "consumables", "quests", "exploration_events", "ranks", "talents"]
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
	"ranks": ["rank_index", "exp_required", "exam_recipe_id", "min_quality", "quantity", "research_cost", "required_quest_id", "required_flame"],
	"talents": ["choice_rank", "style", "success_bonus", "material_refund_bonus", "legendary_transfer", "research_discount", "substitution_ratio"],
	"quests": ["required_recipe_id", "min_quality", "quantity", "reward_spirit_stones", "reward_exp", "reward_items", "reward_flame", "repeatable"],
	"exploration_events": ["weight", "options"],
}
const MATERIAL_CATEGORIES := ["herb", "mineral", "beast", "spirit"]
const MATERIAL_SOURCES := ["shop", "forage", "exploration", "quest", "research", "alchemy"]
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
				"ranks":
					_validate_rank(item, path, errors)
				"talents":
					_validate_talent(item, path, errors)
				"quests":
					_validate_quest(item, path, errors)
				"exploration_events":
					_validate_event(item, path, errors)
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
	_validate_resource_references(documents, errors)
	_validate_progression_references(documents, errors)
	return errors


func _validate_rank(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_validate_resource_unlock(item, path, errors)
	_integer(item.get("rank_index"), 0, 10, path + ".rank_index", errors)
	for field in ["exp_required", "quantity", "research_cost"]:
		_integer(item.get(field), 0, MAX_INTEGER, path + "." + field, errors)
	_enum(item.get("min_quality"), QUALITIES, path + ".min_quality", errors)
	for field in ["exam_recipe_id", "required_quest_id", "required_flame"]:
		if not item.get(field) is String:
			_error(errors, "INVALID_TYPE", path + "." + field, "引用须为 ID 或空字符串。")
	if _is_number(item.get("rank_index")) and item.rank_index != 0 and ((_is_number(item.get("quantity")) and item.quantity == 0) or (_is_number(item.get("research_cost")) and item.research_cost == 0)):
		_error(errors, "INVALID_EXAM", path, "晋升须有交付数量与正数研制成本。")


func _validate_talent(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_validate_resource_unlock(item, path, errors)
	if _integer(item.get("choice_rank"), 3, 9, path + ".choice_rank", errors) and int(item.choice_rank) not in [3, 6, 9]:
		_error(errors, "INVALID_ENUM", path + ".choice_rank", "天赋阶段只允许三、六、九品。")
	_enum(item.get("style"), ["stable", "rush", "research"], path + ".style", errors)
	_number(item.get("success_bonus"), -1, 1, path + ".success_bonus", errors)
	_number(item.get("material_refund_bonus"), 0, 1, path + ".material_refund_bonus", errors)
	_number(item.get("legendary_transfer"), 0, 100, path + ".legendary_transfer", errors)
	_number(item.get("research_discount"), 0, 0.5, path + ".research_discount", errors)
	_integer(item.get("substitution_ratio"), 0, 10, path + ".substitution_ratio", errors)
	if item.get("unlock") is Dictionary and _is_number(item.unlock.get("required_rank")) and _is_number(item.get("choice_rank")) and item.unlock.required_rank != item.choice_rank:
		_error(errors, "INVALID_TALENT", path + ".unlock", "天赋境界必须与抉择阶段一致。")


func _validate_progression_references(documents: Dictionary, errors: Array[Dictionary]) -> void:
	var known: Dictionary = {}
	for category in CATEGORIES:
		known[category] = {}
		var doc: Variant = documents.get(category)
		if doc is Dictionary and doc.get("items") is Array:
			for item in doc.items:
				if item is Dictionary and item.get("id") is String:
					known[category][item.id] = item
	var ranks: Dictionary = {}
	var rank_doc: Variant = documents.get("ranks")
	if rank_doc is Dictionary and rank_doc.get("items") is Array:
		for i in range(rank_doc.items.size()):
			var rank: Variant = rank_doc.items[i]
			if not rank is Dictionary:
				continue
			var path := "ranks.items[%d]" % i
			var n: Variant = rank.get("rank_index")
			if _is_number(n) and n == floor(n) and n >= 0 and n <= 10:
				n = int(n)
				if ranks.has(n):
					_error(errors, "DUPLICATE_RANK", path + ".rank_index", "品阶序号重复。")
				ranks[n] = rank
			for pair in [["exam_recipe_id", "recipes"], ["required_quest_id", "quests"], ["required_flame", "flames"]]:
				var id: Variant = rank.get(pair[0])
				if (not _is_number(n) or n != 0 or pair[0] != "exam_recipe_id") and id is String and (not id.is_empty() or pair[0] == "exam_recipe_id") and not known[pair[1]].has(id):
					_error(errors, "MISSING_REFERENCE", path + "." + pair[0], "晋升引用不存在。")
			if known.recipes.has(rank.get("exam_recipe_id")) and _is_number(n):
				var recipe: Dictionary = known.recipes[rank.exam_recipe_id]
				var unlock: Variant = recipe.get("unlock")
				var needed: Variant = recipe.get("required_rank")
				var unlocked_rank: Variant = unlock.get("required_rank", 0) if unlock is Dictionary else null
				if _is_number(needed) and _is_number(unlocked_rank) and (needed > n - 1 or unlocked_rank > n - 1):
					_error(errors, "UNREACHABLE_EXAM", path + ".exam_recipe_id", "考核丹方必须可在晋升前使用。")
		for n in range(11):
			if not ranks.has(n):
				_error(errors, "MISSING_RANK", "ranks.items", "缺少品阶 %d。" % n)
			elif n > 0 and ranks.has(n - 1) and _is_number(ranks[n].get("exp_required")) and _is_number(ranks[n - 1].get("exp_required")) and ranks[n].exp_required < ranks[n - 1].exp_required:
				_error(errors, "INVALID_RANK_ORDER", "ranks.items", "历练门槛必须递增。")
	var talent_doc: Variant = documents.get("talents")
	if talent_doc is Dictionary and talent_doc.get("items") is Array:
		var groups := {3: [], 6: [], 9: []}
		for talent in talent_doc.items:
			if talent is Dictionary and _is_number(talent.get("choice_rank")) and groups.has(int(talent.choice_rank)):
				groups[int(talent.choice_rank)].append(talent.get("style"))
		for group in groups:
			if groups[group].size() != 3 or not groups[group].has("stable") or not groups[group].has("rush") or not groups[group].has("research"):
				_error(errors, "INVALID_TALENT_GROUP", "talents.items", "每次抉择须有稳丹、冲品、研究各一项。")


func _validate_quest(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_validate_resource_unlock(item, path, errors)
	_text(item.get("required_recipe_id"), path + ".required_recipe_id", errors)
	_enum(item.get("min_quality"), QUALITIES, path + ".min_quality", errors)
	_integer(item.get("quantity"), 1, MAX_INTEGER, path + ".quantity", errors)
	_integer(item.get("reward_spirit_stones"), 0, MAX_INTEGER, path + ".reward_spirit_stones", errors)
	_integer(item.get("reward_exp"), 0, MAX_INTEGER, path + ".reward_exp", errors)
	_quantities(item.get("reward_items"), path + ".reward_items", errors)
	_boolean(item.get("repeatable"), path + ".repeatable", errors)
	if not item.get("reward_flame") is String:
		_error(errors, "INVALID_TYPE", path + ".reward_flame", "异火奖励必须为 ID 或空字符串。")


func _validate_event(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	_validate_resource_unlock(item, path, errors)
	_number(item.get("weight"), 0.000001, MAX_INTEGER, path + ".weight", errors)
	var options: Variant = item.get("options")
	if not options is Array or options.is_empty():
		_error(errors, "INVALID_TYPE", path + ".options", "事件选项必须为非空数组。")
		return
	var seen: Dictionary = {}
	for i in range(options.size()):
		var option: Variant = options[i]
		var p := "%s.options[%d]" % [path, i]
		if not _shape(option, ["id", "name", "description", "cost_stones", "cost_items", "success_rate", "success_items", "failure_items", "success_stones", "failure_stones", "reward_flame"], p, errors):
			continue
		for field in ["id", "name", "description"]:
			_text(option.get(field), p + "." + field, errors)
		if option.get("id") is String:
			if _id_pattern.search(option.id) == null:
				_error(errors, "INVALID_ID", p + ".id", "选项 ID 必须为英文下划线格式。")
			if seen.has(option.id):
				_error(errors, "DUPLICATE_ID", p + ".id", "同一事件选项 ID 重复。")
			seen[option.id] = true
		for field in ["cost_stones", "success_stones", "failure_stones"]:
			_integer(option.get(field), 0, MAX_INTEGER, p + "." + field, errors)
		_number(option.get("success_rate"), 0, 1, p + ".success_rate", errors)
		for field in ["cost_items", "success_items", "failure_items"]:
			_quantities(option.get(field), p + "." + field, errors)
		if not option.get("reward_flame") is String:
			_error(errors, "INVALID_TYPE", p + ".reward_flame", "异火奖励必须为 ID 或空字符串。")


func _validate_resource_unlock(item: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	if item.get("unlock") is Dictionary:
		_enum(item.unlock.get("type"), ["rank"], path + ".unlock.type", errors)


func _quantities(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_error(errors, "INVALID_TYPE", path, "物品表必须为对象。")
		return
	for id in value:
		_integer(value[id], 1, MAX_INTEGER, path + "." + str(id), errors)


func _validate_resource_references(documents: Dictionary, errors: Array[Dictionary]) -> void:
	var known: Dictionary = {}
	for category in CATEGORIES:
		known[category] = []
		var doc: Variant = documents.get(category)
		if doc is Dictionary and doc.get("items") is Array:
			for item in doc.items:
				if item is Dictionary and item.get("id") is String:
					known[category].append(item.id)
	for category in ["quests", "exploration_events"]:
		var doc: Variant = documents.get(category)
		if not doc is Dictionary or not doc.get("items") is Array:
			continue
		for i in range(doc.items.size()):
			var item: Variant = doc.items[i]
			if not item is Dictionary:
				continue
			var path := "%s.items[%d]" % [category, i]
			var rewards: Array = []
			if category == "quests":
				if item.get("required_recipe_id") not in known.recipes:
					_error(errors, "MISSING_REFERENCE", path + ".required_recipe_id", "委托丹方不存在。")
				rewards.append({"item": item, "path": path, "maps": ["reward_items"]})
			elif item.get("options") is Array:
				for j in range(item.options.size()):
					if item.options[j] is Dictionary:
						rewards.append({"item": item.options[j], "path": "%s.options[%d]" % [path, j], "maps": ["cost_items", "success_items", "failure_items"]})
			for row in rewards:
				var flame: Variant = row.item.get("reward_flame")
				if flame is String and not flame.is_empty() and flame not in known.flames:
					_error(errors, "MISSING_REFERENCE", row.path + ".reward_flame", "奖励异火不存在。")
				for field in row.maps:
					var map: Variant = row.item.get(field)
					if map is Dictionary:
						for id in map:
							if id not in known.materials and id not in known.consumables:
								_error(errors, "MISSING_REFERENCE", row.path + "." + field + "." + str(id), "物品引用不存在或不可堆叠。")


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
