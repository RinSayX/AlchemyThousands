extends RefCounted
## Dedicated post-ending rule document; common content tables remain reproducible.
const Result := preload("res://scripts/core/transaction_result.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const ID := "ending_jiuzhuan"
const PATH := "res://data/ending_trials.json"

static func read(db: RefCounted) -> Dictionary:
	return validate(db, JSON.parse_string(FileAccess.get_file_as_string(PATH)))

static func validate(db: RefCounted, source: Variant) -> Dictionary:
	if not _shape(source, ["schema_version", "id", "name", "description", "required_rank", "requirements", "study"]): return _bad()
	if not _integer(source.schema_version, 1, 1) or not source.id is String or source.id != ID or not _integer(source.required_rank, 10, 10): return _bad()
	for field in ["name", "description"]:
		if not source[field] is String or source[field].strip_edges().is_empty(): return _bad()
	if not source.requirements is Array or source.requirements.size() != 2 or not source.study is Array or source.study.size() != source.requirements.size(): return _bad()
	var ids: Array = []
	for row in source.requirements:
		if not _shape(row, ["recipe_id", "quality", "quantity"]): return _bad()
		if not row.recipe_id is String or row.recipe_id not in db.get_ids("recipes") or row.recipe_id in ids or not row.quality is String or row.quality != "legendary" or not _integer(row.quantity, 1, 2): return _bad()
		if db.get_item(row.recipe_id).tier != 9: return _bad()
		ids.append(row.recipe_id)
	var studied: Array = []
	for row in source.study:
		if not _shape(row, ["recipe_id", "research_cost", "material_multiplier"]): return _bad()
		if not row.recipe_id is String or row.recipe_id not in ids or row.recipe_id in studied or not _integer(row.research_cost, 1, 10000) or not _integer(row.material_multiplier, 1, 4): return _bad()
		for amount in db.get_item(row.recipe_id).materials.values():
			if amount * row.material_multiplier > Economy.MAX_VALUE: return _bad()
		studied.append(row.recipe_id)
	var definition: Dictionary = source.duplicate(true)
	definition.schema_version = 1
	definition.required_rank = 10
	for row in definition.requirements: row.quantity = int(row.quantity)
	for row in definition.study:
		row.research_cost = int(row.research_cost)
		row.material_multiplier = int(row.material_multiplier)
	return Result.success({}, {"definition": definition})

static func _shape(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

static func _bad() -> Dictionary:
	return Result.failure("INVALID_ENDING_CONTENT", "data/ending_trials.json 的字段、引用或精研费用不合法。")
