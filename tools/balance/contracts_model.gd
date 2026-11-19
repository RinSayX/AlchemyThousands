extends RefCounted
const Previous := preload("res://tools/balance/catalog_model.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const PROPOSAL := "res://tests/fixtures/p8_contracts_proposal.json"
const RECIPES := ["recipe_gushen", "recipe_leijie", "recipe_gushen", "recipe_bingxin", "recipe_bingxin"]

static func proposal() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROPOSAL))

static func documents() -> Dictionary:
	var docs := Previous.documents()
	var added := proposal()
	for category in added: docs[category].items.append_array(added[category])
	return docs

static func database() -> RefCounted:
	var db := Database.new()
	var checked := db.load_documents(documents())
	if not checked.ok: printerr(checked.errors)
	return db if checked.ok else null

static func run(progress: Callable = Callable()) -> Dictionary:
	var db: RefCounted = database()
	if db == null: return {"ok": false, "errors": ["Invalid contracts proposal"]}
	var errors: Array = []
	var events: Array = []
	var quests: Array = []
	var economy: Array = []
	var probability: Array = []
	var pair_index := 0
	for worlds in Previous.WORLDS + [["world_huoling", "world_dansheng"]]:
		var state := Probe.fixture(db, 10, "stable", [], worlds)
		for source in proposal().exploration_events:
			for original in source.options:
				var option := Lineage.option(db, state, source.id, original)
				var win := 0.0
				var lose := 0.0
				for id in option.success_items: win += option.success_items[id] * Lineage.sell_price(db, state, id, db.get_item(id).sell_price)
				for id in option.failure_items: lose += option.failure_items[id] * Lineage.sell_price(db, state, id, db.get_item(id).sell_price)
				var net: float = option.success_rate * win + (1-option.success_rate) * lose - option.cost_stones
				events.append({"event": source.id, "option": option.id, "worlds": worlds, "expected_resale_net": net, "passed": net <= 0})
				if net > 0: errors.append("Repeatable event resale gain: " + source.id)
		for original in proposal().quests:
			var quest := Lineage.quest(db, state, db.get_item(original.id))
			var direct: int = Probe.price(db, quest.required_recipe_id, quest.min_quality) * quest.quantity
			quests.append({"quest": quest.id, "worlds": worlds, "required_quality": quest.min_quality, "quantity": quest.quantity, "direct_minimum_sale": direct, "cash_reward": quest.reward_spirit_stones, "cash_premium": quest.reward_spirit_stones - direct, "repeatable": quest.repeatable})
	for i in range(proposal().consumables.size()):
		var item: Dictionary = db.get_item(proposal().consumables[i].id)
		var recipe: Dictionary = db.get_item(RECIPES[i])
		for worlds in Previous.WORLDS:
			for style in ["stable", "rush", "recycle"]:
				var state := Previous.fixture(db, recipe, style, worlds)
				state.rank = maxi(state.rank, item.unlock.required_rank)
				# Rebuild milestone talents after conditioning on the consumable's purchase rank.
				state.talent_choices = []
				for milestone in [3, 6, 9]:
					if milestone <= state.rank: state.talent_choices.append("talent_%s_%d" % ["stable" if style == "recycle" else style, milestone])
				var selected := Previous.setup(state, recipe, style)
				selected.consumable_id = ""
				var plain := Probe.analyze(db, state, recipe.id, style, "good", 100000, 221001 + pair_index, selected)
				selected.consumable_id = item.id
				var aided := Probe.analyze(db, state, recipe.id, style, "good", 100000, 221001 + pair_index, selected)
				economy.append({"consumable": item.id, "worlds": worlds, "style": style, "without": plain, "with": aided, "expected_net_delta": aided.expected_net - plain.expected_net})
				if not plain.mean_within_bound or not aided.mean_within_bound or not plain.frequencies_within_bounds or not aided.frequencies_within_bounds: errors.append(item.id + style)
				if worlds.is_empty() and style == ("rush" if item.id == "consumable_jiuzhuan" else "stable"):
					var preview: Dictionary = Alchemy.new(db).preview_alchemy(state, recipe.id, selected)
					var sampled: Dictionary = Statistics.new()._sample(item.id, preview.result, 221001 + pair_index)
					probability.append(sampled)
					if not sampled.passed: errors.append(sampled.name)
				pair_index += 1
		if progress.is_valid(): progress.call(item.id)
	return {"ok": errors.is_empty(), "errors": errors, "engine": "4.5.stable.official.876b29033", "baseline": "da25c8b", "proposal_sha256": FileAccess.get_sha256(PROPOSAL), "content_sha256": JSON.stringify(documents()).sha256_text(), "counts": db.get_counts(), "samples_per_group": 100000, "economy_pairs": economy, "probability": probability, "event_resale": events, "quest_opportunity_cost": quests, "scope": "Conditioned builds compare one consumable against none; recurring costs, no equipment investment or time value. Event audit uses liquid resale, not utility. Quest comparison at minimum eligible quality only."}
