extends RefCounted
const Base := preload("res://scripts/core/ending_trial_definition.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const ID := "ending_baicao"
const PATH := "res://data/baicao_trial.json"

static func read(db: RefCounted) -> Dictionary:
	return validate(db, JSON.parse_string(FileAccess.get_file_as_string(PATH)))

static func validate(db: RefCounted, data: Variant) -> Dictionary:
	if not Base._shape(data, ["schema_version", "mutation", "ending"]) or not Base._integer(data.schema_version, 1, 1): return _bad()
	if not Base._shape(data.mutation, ["id", "name", "recipe_id", "flame_id", "strategy", "required_rank", "chance"]): return _bad()
	if not Base._shape(data.ending, ["id", "name", "required_rank", "material_count", "research_crafts", "research_cost", "study_research_cost", "study_material_multiplier"]): return _bad()
	var m: Dictionary = data.mutation
	for pair in [["id", Pills.MUTATION_ID], ["recipe_id", Pills.MUTATION_RECIPE], ["flame_id", "flame_zixiao"], ["strategy", "rush"]]:
		if not m[pair[0]] is String or m[pair[0]] != pair[1]: return _bad()
	if m.recipe_id not in db.get_ids("recipes") or m.flame_id not in db.get_ids("flames") or not Base._integer(m.required_rank, 6, 6): return _bad()
	if not (m.chance is int or m.chance is float) or not is_finite(m.chance) or m.chance <= 0 or m.chance > 1: return _bad()
	var e: Dictionary = data.ending
	if not e.id is String or e.id != ID or not Base._integer(e.required_rank, 10, 10) or not Base._integer(e.material_count, 25, db.get_ids("materials").size()): return _bad()
	for field in ["research_crafts", "research_cost", "study_research_cost"]:
		if not Base._integer(e[field], 1, 10000): return _bad()
	if not Base._integer(e.study_material_multiplier, 1, 4): return _bad()
	for amount in db.get_item(Pills.MUTATION_RECIPE).materials.values():
		if amount * e.study_material_multiplier > 2147483647: return _bad()
	for text in [m.name, e.name]:
		if not text is String or text.strip_edges().is_empty(): return _bad()
	var definition: Dictionary = data.duplicate(true)
	definition.mutation.required_rank = 6
	for field in ["required_rank", "material_count", "research_crafts", "research_cost", "study_research_cost", "study_material_multiplier"]: definition.ending[field] = int(e[field])
	return Result.success({}, {"definition": definition})

static func available(db: RefCounted, state: Dictionary, recipe_id: String, setup: Dictionary, definition: Dictionary) -> bool:
	if definition.is_empty(): return false
	var m: Dictionary = definition.mutation
	return state.rank >= m.required_rank and recipe_id == m.recipe_id and setup.flame_id == m.flame_id and setup.strategy == m.strategy and not preload("res://scripts/core/lineage_rules.gd").world(db, state, "suppress_special_flames", false)

static func _bad() -> Dictionary:
	return Result.failure("INVALID_BAICAO_CONTENT", "data/baicao_trial.json 的变异或百草试炼规则不合法。")
