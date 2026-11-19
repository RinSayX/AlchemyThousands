extends RefCounted
## P1 data, invalid-input and transactional loading regressions.

const Database := preload("res://scripts/core/content_db.gd")
const Validator := preload("res://scripts/core/content_validator.gd")
var _check: Callable
var _baseline: Dictionary


func run(check: Callable) -> void:
	_check = check
	_baseline = _read_documents()
	var db := Database.new()
	var result := db.load_directory()
	_check.call(result.ok, "P1: Shipped JSON loads and validates")
	if not result.ok:
		printerr(result.errors)
		return
	_check.call(result.counts == {"recipes": 25, "materials": 25, "furnaces": 6, "flames": 5, "consumables": 3, "quests": 5, "exploration_events": 13, "ranks": 11, "talents": 9, "inheritances": 9, "world_modifiers": 6}, "P8: Content counts include 25 recipes, 25 materials and thirteen destinations")
	_check.call(db.get_item("recipe_juling").name == "聚灵丹", "P1: Stable ID resolves Chinese content")
	_check.call(db.get_item("recipe_juling").materials == {"herb_lingcao": 2, "herb_qinghua": 1}, "P1: Juling material baseline is preserved")
	_check.call(typeof(db.get_item("recipe_juling").tier) == TYPE_INT and typeof(db.get_item("recipe_juling").base_sell_price) == TYPE_INT and typeof(db.get_item("consumable_wendan").unlock.price) == TYPE_INT, "P1: Validated integral JSON values become runtime integers")
	_check.call(db.get_item("recipe_juling").base_success_rate == 0.8, "P1: Juling base probability remains 80 percent")
	_check.call(not db.has_item("recipe_missing") and db.get_item("recipe_missing").is_empty(), "P1: Unknown IDs return empty without altering content")
	_check.call(db.get_ids("unknown").is_empty() and db.get_items("unknown").is_empty(), "P1: Unknown categories return empty")
	_test_isolation(db)
	_test_invalid_content(db)
	_test_reload(db)
	_test_files(db)


func _test_isolation(db: RefCounted) -> void:
	var original := JSON.stringify(_baseline)
	Validator.new().validate_documents(_baseline)
	_check.call(JSON.stringify(_baseline) == original, "P1: Validation never changes its input")
	var documents := _baseline.duplicate(true)
	db.load_documents(documents)
	documents.recipes.items[0].materials.herb_lingcao = 999
	_check.call(db.get_item("recipe_juling").materials.herb_lingcao == 2, "P1: Loading isolates caller-owned documents")
	var item: Dictionary = db.get_item("recipe_juling")
	item.materials.herb_lingcao = 888
	item.tags.append("injected")
	_check.call(db.get_item("recipe_juling").materials.herb_lingcao == 2 and not db.get_item("recipe_juling").tags.has("injected"), "P1: Item queries return deep copies")
	var items: Array = db.get_items("recipes")
	items[0].quality_weights.common = 0
	items.clear()
	_check.call(db.get_items("recipes").size() == 25 and db.get_item("recipe_juling").quality_weights.common == 65, "P1: Category queries isolate nested values")
	var ids: Array = db.get_ids("recipes")
	ids.clear()
	var counts: Dictionary = db.get_counts()
	counts.recipes = 900
	_check.call(db.get_ids("recipes").size() == 25 and db.get_counts().recipes == 25, "P1: Index/count queries cannot mutate the cache")
	_check.call(db.get_ids("recipes")[0] == "recipe_juling", "P1: Content order matches the JSON table")


func _test_invalid_content(db: RefCounted) -> void:
	# name, nested field path, invalid value, expected code, exact diagnostic path.
	var cases := [
		["Non-object document", ["recipes"], [], "INVALID_TYPE", "recipes"],
		["Unsupported schema", ["recipes", "schema_version"], 2, "OUT_OF_RANGE", "recipes.schema_version"],
		["Boolean schema", ["recipes", "schema_version"], true, "INVALID_TYPE", "recipes.schema_version"],
		["Non-array items", ["recipes", "items"], {}, "INVALID_TYPE", "recipes.items"],
		["Empty items", ["recipes", "items"], [], "EMPTY_ITEMS", "recipes.items"],
		["Non-object item", ["recipes", "items", 0], "recipe", "INVALID_TYPE", "recipes.items[0]"],
		["Duplicate recipe ID", ["recipes", "items", 1, "id"], "recipe_juling", "DUPLICATE_ID", "recipes.items[1].id"],
		["Cross-category duplicate ID", ["flames", "items", 0, "id"], "recipe_juling", "DUPLICATE_ID", "flames.items[0].id"],
		["Localized ID", ["recipes", "items", 0, "id"], "聚灵丹", "INVALID_ID", "recipes.items[0].id"],
		["Malformed ID", ["recipes", "items", 0, "id"], "recipe__juling", "INVALID_ID", "recipes.items[0].id"],
		["Empty name", ["recipes", "items", 0, "name"], "  ", "INVALID_TEXT", "recipes.items[0].name"],
		["Non-string description", ["recipes", "items", 0, "description"], 5, "INVALID_TEXT", "recipes.items[0].description"],
		["Zero tier", ["recipes", "items", 0, "tier"], 0, "OUT_OF_RANGE", "recipes.items[0].tier"],
		["Tier above nine", ["furnaces", "items", 0, "tier"], 10, "OUT_OF_RANGE", "furnaces.items[0].tier"],
		["Fractional tier", ["recipes", "items", 0, "tier"], 1.5, "INVALID_INTEGER", "recipes.items[0].tier"],
		["Boolean tier", ["recipes", "items", 0, "tier"], true, "INVALID_TYPE", "recipes.items[0].tier"],
		["Negative rank", ["recipes", "items", 0, "required_rank"], -1, "OUT_OF_RANGE", "recipes.items[0].required_rank"],
		["Rank above grandmaster", ["recipes", "items", 0, "required_rank"], 11, "OUT_OF_RANGE", "recipes.items[0].required_rank"],
		["Non-array tags", ["recipes", "items", 0, "tags"], "wood", "INVALID_TYPE", "recipes.items[0].tags"],
		["Duplicate tags", ["recipes", "items", 0, "tags"], ["wood", "wood"], "DUPLICATE_VALUE", "recipes.items[0].tags[1]"],
		["Malformed tag", ["recipes", "items", 0, "tags"], ["Wood"], "INVALID_TAG", "recipes.items[0].tags[0]"],
		["Non-string tag", ["recipes", "items", 0, "tags"], [true], "INVALID_TEXT", "recipes.items[0].tags[0]"],
		["Null unlock", ["recipes", "items", 0, "unlock"], null, "INVALID_TYPE", "recipes.items[0].unlock"],
		["Unknown unlock type", ["recipes", "items", 0, "unlock"], {"type": "script"}, "INVALID_ENUM", "recipes.items[0].unlock.type"],
		["Missing unlock rank", ["recipes", "items", 0, "unlock"], {"type": "rank"}, "MISSING_FIELD", "recipes.items[0].unlock.required_rank"],
		["Negative shop price", ["recipes", "items", 1, "unlock", "price"], -1, "OUT_OF_RANGE", "recipes.items[1].unlock.price"],
		["Probability below zero", ["recipes", "items", 0, "base_success_rate"], -0.01, "OUT_OF_RANGE", "recipes.items[0].base_success_rate"],
		["Probability above one", ["recipes", "items", 0, "base_success_rate"], 1.01, "OUT_OF_RANGE", "recipes.items[0].base_success_rate"],
		["Probability as string", ["recipes", "items", 0, "base_success_rate"], "0.8", "INVALID_TYPE", "recipes.items[0].base_success_rate"],
		["Probability NaN", ["recipes", "items", 0, "base_success_rate"], NAN, "INVALID_TYPE", "recipes.items[0].base_success_rate"],
		["Probability infinity", ["recipes", "items", 0, "base_success_rate"], INF, "INVALID_TYPE", "recipes.items[0].base_success_rate"],
		["Non-object materials", ["recipes", "items", 0, "materials"], [], "INVALID_TYPE", "recipes.items[0].materials"],
		["Empty materials", ["recipes", "items", 0, "materials"], {}, "EMPTY_MATERIALS", "recipes.items[0].materials"],
		["Missing material reference", ["recipes", "items", 0, "materials"], {"herb_missing": 1}, "MISSING_REFERENCE", "recipes.items[0].materials.herb_missing"],
		["Zero quantity", ["recipes", "items", 0, "materials", "herb_lingcao"], 0, "OUT_OF_RANGE", "recipes.items[0].materials.herb_lingcao"],
		["Negative quantity", ["recipes", "items", 0, "materials", "herb_lingcao"], -2, "OUT_OF_RANGE", "recipes.items[0].materials.herb_lingcao"],
		["Fractional quantity", ["recipes", "items", 0, "materials", "herb_lingcao"], 1.5, "INVALID_INTEGER", "recipes.items[0].materials.herb_lingcao"],
		["Oversized quantity", ["recipes", "items", 0, "materials", "herb_lingcao"], 2147483648.0, "OUT_OF_RANGE", "recipes.items[0].materials.herb_lingcao"],
		["Negative weight", ["recipes", "items", 0, "quality_weights", "common"], -1, "OUT_OF_RANGE", "recipes.items[0].quality_weights.common"],
		["Null weights", ["recipes", "items", 0, "quality_weights"], null, "INVALID_TYPE", "recipes.items[0].quality_weights"],
		["Zero weights", ["recipes", "items", 0, "quality_weights"], {"common": 0, "good": 0, "superior": 0, "legendary": 0}, "INVALID_WEIGHTS", "recipes.items[0].quality_weights"],
		["Weight sum overflow", ["recipes", "items", 0, "quality_weights"], {"common": 1e308, "good": 1e308, "superior": 0, "legendary": 0}, "INVALID_WEIGHTS", "recipes.items[0].quality_weights"],
		["Missing quality", ["recipes", "items", 0, "quality_weights"], {"common": 65, "good": 25, "superior": 9}, "MISSING_FIELD", "recipes.items[0].quality_weights.legendary"],
		["Unknown quality", ["recipes", "items", 0, "quality_weights"], {"common": 65, "good": 25, "superior": 9, "legendary": 1, "mythic": 1}, "UNKNOWN_FIELD", "recipes.items[0].quality_weights.mythic"],
		["Unregistered special rule", ["recipes", "items", 0, "special_rules"], ["unsafe_rule"], "UNKNOWN_EFFECT", "recipes.items[0].special_rules[0]"],
		["Negative pill sale price", ["recipes", "items", 0, "base_sell_price"], -1, "OUT_OF_RANGE", "recipes.items[0].base_sell_price"],
		["Boolean material price", ["materials", "items", 0, "buy_price"], false, "INVALID_TYPE", "materials.items[0].buy_price"],
		["Negative material price", ["materials", "items", 0, "sell_price"], -1, "OUT_OF_RANGE", "materials.items[0].sell_price"],
		["Material resale arbitrage", ["materials", "items", 0, "sell_price"], 5, "ARBITRAGE_PRICE", "materials.items[0].sell_price"],
		["Unknown material category", ["materials", "items", 0, "category"], "seed", "INVALID_ENUM", "materials.items[0].category"],
		["Non-boolean availability", ["materials", "items", 0, "shop_available"], [], "INVALID_TYPE", "materials.items[0].shop_available"],
		["Non-boolean repeatability", ["materials", "items", 0, "repeatable"], 1, "INVALID_TYPE", "materials.items[0].repeatable"],
		["Empty material sources", ["materials", "items", 0, "sources"], [], "EMPTY_SOURCES", "materials.items[0].sources"],
		["Unknown material source", ["materials", "items", 0, "sources"], ["garden"], "INVALID_ENUM", "materials.items[0].sources[0]"],
		["Inconsistent material shop source", ["materials", "items", 0, "sources"], ["forage"], "INCONSISTENT_SHOP", "materials.items[0].shop_available"],
		["Success bonus too large", ["furnaces", "items", 0, "success_bonus"], 1.1, "OUT_OF_RANGE", "furnaces.items[0].success_bonus"],
		["Refund above one", ["consumables", "items", 2, "material_refund_bonus"], 1.01, "OUT_OF_RANGE", "consumables.items[2].material_refund_bonus"],
		["Extra pill chance below zero", ["flames", "items", 0, "extra_pill_chance"], -0.1, "OUT_OF_RANGE", "flames.items[0].extra_pill_chance"],
		["Non-object transfers", ["furnaces", "items", 0, "quality_transfers"], [], "INVALID_TYPE", "furnaces.items[0].quality_transfers"],
		["Unknown transfer target", ["furnaces", "items", 0, "quality_transfers"], {"mythic": 5}, "INVALID_ENUM", "furnaces.items[0].quality_transfers.mythic"],
		["Negative transfer amount", ["furnaces", "items", 0, "quality_transfers"], {"superior": -5}, "OUT_OF_RANGE", "furnaces.items[0].quality_transfers.superior"],
		["Transfer sum overflow", ["furnaces", "items", 0, "quality_transfers"], {"good": 1e308, "superior": 1e308}, "INVALID_TRANSFERS", "furnaces.items[0].quality_transfers"],
		["Unregistered equipment effect", ["flames", "items", 0, "effect_ids"], ["execute_script"], "UNKNOWN_EFFECT", "flames.items[0].effect_ids[0]"],
		["Unknown consumable category", ["consumables", "items", 0, "effect_category"], "infinite", "INVALID_ENUM", "consumables.items[0].effect_category"],
		["Consumable resale arbitrage", ["consumables", "items", 0, "sell_price"], 9, "ARBITRAGE_PRICE", "consumables.items[0].sell_price"],
		["Inconsistent consumable shop", ["consumables", "items", 0, "shop_available"], false, "INCONSISTENT_SHOP", "consumables.items[0].shop_available"],
	]
	for case in cases:
		var documents := _baseline.duplicate(true)
		_replace(documents, case[1], case[2])
		_expect_rejected(db, documents, case[3], case[4], case[0])
	var missing := _baseline.duplicate(true)
	missing.erase("materials")
	_expect_rejected(db, missing, "MISSING_CATEGORY", "materials", "Missing table")
	var unknown := _baseline.duplicate(true)
	unknown["recpies"] = {}
	_expect_rejected(db, unknown, "UNKNOWN_CATEGORY", "recpies", "Misspelled table")
	var missing_field := _baseline.duplicate(true)
	missing_field.recipes.items[0].erase("tier")
	_expect_rejected(db, missing_field, "MISSING_FIELD", "recipes.items[0].tier", "Missing common field")
	var typo := _baseline.duplicate(true)
	typo.recipes.items[0]["base_sucess_rate"] = 0.99
	_expect_rejected(db, typo, "UNKNOWN_FIELD", "recipes.items[0].base_sucess_rate", "Misspelled field")
	var changed: Dictionary = db.get_counts()
	_check.call(changed.recipes == 25 and db.get_item("recipe_juling").materials.herb_lingcao == 2, "P1: Invalid loads never replace the validated cache")
	var boundary := _baseline.duplicate(true)
	boundary.recipes.items[0].base_success_rate = 0
	boundary.recipes.items[1].base_success_rate = 1
	boundary.recipes.items[0].quality_weights = {"common": 0, "good": 0, "superior": 0, "legendary": 0.5}
	boundary.recipes.items[1].required_rank = 10
	boundary.materials.items[0].buy_price = 2147483647
	boundary.furnaces.items[0].success_bonus = -1
	boundary.flames.items[0].success_bonus = 1
	boundary.flames.items[0].extra_pill_chance = 1
	boundary.consumables.items[2].material_refund_bonus = 1
	_check.call(Validator.new().validate_documents(boundary).is_empty(), "P1: Inclusive numeric limits and unnormalized fractional weights are accepted")
	var multiple := _baseline.duplicate(true)
	multiple.recipes.items[0].tier = 0
	multiple.materials.items[0].sell_price = -1
	var errors := Validator.new().validate_documents(multiple)
	_check.call(_has_error(errors, "OUT_OF_RANGE", "recipes.items[0].tier") and _has_error(errors, "OUT_OF_RANGE", "materials.items[0].sell_price"), "P1: Validation collects errors across multiple tables")


func _test_reload(db: RefCounted) -> void:
	var fresh := Database.new()
	var invalid := _baseline.duplicate(true)
	invalid.recipes.items[0].tier = 0
	_check.call(not fresh.load_documents(invalid).ok and not fresh.has_item("recipe_juling"), "P1: Failed first load leaves an empty repository")
	var replacement := _baseline.duplicate(true)
	replacement.recipes.items[1].id = "recipe_replacement"
	for quest in replacement.quests.items:
		if quest.required_recipe_id == "recipe_zhixue":
			quest.required_recipe_id = "recipe_replacement"
	var result: Dictionary = db.load_documents(replacement)
	_check.call(result.ok and db.has_item("recipe_replacement") and not db.has_item("recipe_zhixue"), "P1: Successful reload replaces obsolete index entries")
	db.load_documents(_baseline)


func _test_files(db: RefCounted) -> void:
	var directory := "res://test-output/p1-content-%d" % OS.get_process_id()
	var absolute := ProjectSettings.globalize_path(directory)
	var created := DirAccess.make_dir_recursive_absolute(absolute)
	_check.call(created == OK, "P1: Temporary file fixtures can be created")
	if created != OK:
		return
	var result: Dictionary = db.load_directory(directory)
	_check.call(not result.ok and result.errors.size() == 11 and result.errors[0].code == "FILE_NOT_FOUND", "P1: Missing files produce structured errors")
	for category in Validator.CATEGORIES:
		_write(directory.path_join(category + ".json"), JSON.stringify(_baseline[category]))
	result = db.load_directory(directory)
	_check.call(result.ok, "P1: Alternate content directories load")
	var bad_path := directory.path_join("recipes.json")
	_write(bad_path, "{\n  broken json\n}")
	result = db.load_directory(directory)
	_check.call(not result.ok and result.errors[0].code == "INVALID_JSON" and result.errors[0].path == bad_path and result.errors[0].has("line"), "P1: Malformed JSON reports the filename and parse line")
	_write(bad_path, "null")
	result = db.load_directory(directory)
	_check.call(not result.ok and _has_error(result.errors, "INVALID_TYPE", "recipes"), "P1: Valid JSON with an invalid root is rejected")
	_write(bad_path, JSON.stringify(_baseline.recipes))
	_write(directory.path_join("flames.json"), "[]")
	result = db.load_directory(directory)
	_check.call(not result.ok and _has_error(result.errors, "INVALID_TYPE", "flames"), "P1: Wrong table root types are rejected")
	_check.call(db.has_item("recipe_zhixue") and db.get_counts().recipes == 25, "P1: File/parse failures preserve the previous complete cache")
	for category in Validator.CATEGORIES:
		DirAccess.remove_absolute(absolute.path_join(category + ".json"))
	_check.call(DirAccess.remove_absolute(absolute) == OK, "P1: Temporary fixtures are removed")


func _expect_rejected(db: RefCounted, documents: Dictionary, code: String, path: String, name: String) -> void:
	var result: Dictionary = db.load_documents(documents)
	_check.call(not result.ok and _has_error(result.errors, code, path), "P1 rejects: " + name)


func _has_error(errors: Array, code: String, path: String) -> bool:
	for error in errors:
		if error.code == code and error.path == path and not error.message.is_empty():
			return true
	return false


func _replace(documents: Dictionary, path: Array, value: Variant) -> void:
	var target: Variant = documents
	for index in range(path.size() - 1):
		target = target[path[index]]
	target[path[-1]] = value


func _read_documents() -> Dictionary:
	var documents: Dictionary = {}
	for category in Validator.CATEGORIES:
		documents[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + category + ".json"))
	return documents


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check.call(file != null, "P1: Write fixture " + path.get_file())
	if file != null:
		file.store_string(text)
		file.close()
