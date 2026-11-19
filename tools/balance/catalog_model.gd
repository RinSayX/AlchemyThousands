extends RefCounted
const Previous := preload("res://tools/balance/equipment_model.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const Sources := preload("res://scripts/core/material_sources.gd")
const PROPOSAL := "res://tests/fixtures/p8_catalog_proposal.json"
const WORLDS := [[], ["world_kucao", "world_yiji"], ["world_yiji", "world_jinhuo"]]

static func proposal() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROPOSAL))

static func documents() -> Dictionary:
	var docs := Previous.documents()
	var added := proposal()
	for category in added: docs[category].items.append_array(added[category])
	return docs

static func database() -> RefCounted:
	var db := Database.new()
	var loaded := db.load_documents(documents())
	if not loaded.ok: printerr(loaded.errors)
	return db if loaded.ok else null

static func fixture(db: RefCounted, recipe: Dictionary, style: String, worlds: Array = []) -> Dictionary:
	var state := Probe.fixture(db, recipe.required_rank + 1, style, [], worlds)
	state.owned_furnaces = db.get_ids("furnaces")
	state.owned_flames = db.get_ids("flames")
	for id in db.get_ids("materials") + db.get_ids("consumables"): state.inventory[id] = 100
	return state

static func setup(state: Dictionary, recipe: Dictionary, style: String) -> Dictionary:
	var selected := {"strategy": "rush" if style == "rush" else "stable", "furnace_id": "furnace_basic", "flame_id": "flame_normal", "consumable_id": ""}
	if state.rank >= 1:
		selected.furnace_id = "furnace_chiyan" if style == "rush" and "fire" in recipe.tags else "furnace_qingmu"
		selected.flame_id = "flame_earth"
	if style == "stable" and state.rank >= 3 and "wood" in recipe.tags: selected.flame_id = "flame_qinglian"
	if style == "stable" and state.rank >= 8 and ("soul" in recipe.tags or "fire" in recipe.tags): selected.furnace_id = "furnace_jiulong"
	if style == "rush" and state.rank >= 6:
		selected.furnace_id = "furnace_zixiao"
		selected.flame_id = "flame_zixiao"
	if style == "recycle":
		if state.rank >= 1: selected.consumable_id = "consumable_hulu"
		if state.rank >= 4:
			selected.furnace_id = "furnace_xuanbing"
			selected.flame_id = "flame_hansui"
	return selected

static func run(progress: Callable = Callable()) -> Dictionary:
	var db: RefCounted = database()
	if db == null: return {"ok": false, "errors": ["Invalid proposal"]}
	var audit: Array = []
	var errors: Array = []
	# New materials cannot be a buy/resell or deterministic source/resell shortcut.
	for item in proposal().materials:
		for worlds in WORLDS:
			var state := fixture(db, {"required_rank": 8}, "stable", worlds)
			var basis := Probe.unit_basis(db, state, item.id)
			var no_arbitrage: bool = basis.stones != null and item.sell_price <= basis.stones
			audit.append({"item": item.id, "worlds": worlds, "unit_cost": basis.stones, "sell_price": item.sell_price, "passed": no_arbitrage})
			if not no_arbitrage: errors.append("Material source arbitrage: " + item.id)
	var economy: Array = []
	var probability: Array = []
	var index := 0
	for source in proposal().recipes:
		var recipe: Dictionary = db.get_item(source.id)
		for worlds in WORLDS:
			for style in ["stable", "rush", "recycle"]:
				var state := fixture(db, recipe, style, worlds)
				var selected := setup(state, recipe, style)
				var row := Probe.analyze(db, state, recipe.id, style, "good", 100000, 181001 + index, selected)
				row["worlds"] = worlds
				economy.append(row)
				if not row.ok or not row.mean_within_bound or not row.frequencies_within_bounds: errors.append(recipe.id + "/" + style + "/" + str(worlds))
				if worlds.is_empty():
					var preview: Dictionary = Alchemy.new(db).preview_alchemy(state, recipe.id, selected)
					var sampled: Dictionary = Statistics.new()._sample(recipe.id + "/" + style, preview.result, 181001 + index)
					probability.append(sampled)
					if not sampled.passed: errors.append(sampled.name)
					if style == "stable" and row.expected_net <= 0: errors.append("Nonpositive first-world stable margin: " + recipe.id)
				index += 1
		if progress.is_valid(): progress.call(recipe.id)
	return {"ok": errors.is_empty(), "errors": errors, "engine": "4.5.stable.official.876b29033", "baseline": "db412f6 equipment candidate", "proposal_sha256": FileAccess.get_sha256(PROPOSAL), "content_sha256": JSON.stringify(documents()).sha256_text(), "counts": db.get_counts(), "samples_per_group": 100000, "economy": economy, "probability": probability, "material_audit": audit, "scope": "Conditioned ownership at recipe rank, three declared policies and three world conditions; recurring ingredient cost only, recipe/equipment investment excluded. Public-command reachability tested separately."}
