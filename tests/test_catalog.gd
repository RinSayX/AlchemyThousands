extends RefCounted
const Model := preload("res://tools/balance/catalog_model.gd")
const Previous := preload("res://tools/balance/equipment_model.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Sources := preload("res://scripts/core/material_sources.gd")
const Explore := preload("res://scripts/services/exploration_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Statistics := preload("res://tests/alchemy_probability.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tests/helpers/catalog_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Equivalent := preload("res://tests/test_tuning.gd")
var db := Database.new()
var check: Callable

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	_content()
	_sources()
	_recipes()
	_compatibility()
	_route()
	return true

func ok(value: bool, message: String) -> void:
	check.call(value, "P8 catalog: " + message)

func _content() -> void:
	var candidate: RefCounted = Model.database()
	var matches := candidate != null
	for category in Model.documents():
		matches = matches and Equivalent.new()._equivalent(db.get_items(category), candidate.get_items(category))
	ok(matches, "All 117 live definitions match the independently analyzed proposal")
	var used: Array = []
	for recipe in Model.proposal().recipes:
		for id in recipe.materials:
			if id not in used: used.append(id)
			var item: Dictionary = db.get_item(id)
			var state := Model.fixture(db, db.get_item(recipe.id), "stable")
			ok(item.shop_available and item.unlock.required_rank <= recipe.required_rank or not Sources.cheapest(db, state, id).is_empty(), "Ingredient reachable at recipe gate: " + recipe.id + "/" + id)
	for item in Model.proposal().materials: ok(item.id in used, "New material has a shipping recipe use: " + item.id)

func _reject(state: Dictionary, operation: Callable, code: String, message: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = operation.call()
	ok(not result.ok and result.error_code == code and before == var_to_bytes(state), message)

func _sources() -> void:
	var service := Explore.new(db)
	for item in Model.proposal().materials:
		if item.shop_available: continue
		var state := Probe.fixture(db, item.unlock.required_rank + 1, "stable", [], [])
		state.spirit_stones = 1000
		var before := var_to_bytes(state)
		var rows := Sources.entries(db, state, item.id)
		var source := Sources.cheapest(db, state, item.id)
		ok(rows.size() == 1 and source.quantity == 1 and before == var_to_bytes(state), "Guaranteed source preview is pure: " + item.id)
		rows[0].quantity = 999
		ok(Sources.cheapest(db, state, item.id).quantity == 1, "Source results cannot alias content: " + item.id)
		var low := Probe.fixture(db, item.unlock.required_rank, "stable", [], [])
		_reject(low, func(): return service.enter(low, "locked", source.event_id), "RANK_LOCKED", "Source rank gate: " + item.id)
		var instance: String = service.enter(state, "enter", source.event_id).result.instance_id
		var original := state.duplicate(true)
		state.spirit_stones = 0
		_reject(state, func(): return service.resolve(state, instance, source.option_id, "poor"), "NOT_ENOUGH_STONES", "Source cannot grant unpaid material: " + item.id)
		state.spirit_stones = original.spirit_stones
		var result := service.resolve(state, instance, source.option_id, "obtain")
		ok(result.ok and state.inventory.get(item.id) == 1 and state.spirit_stones == original.spirit_stones - source.cost_stones and state.rng_states == original.rng_states, "Exact source fee/yield without RNG: " + item.id)
		_reject(state, func(): return service.resolve(state, instance, source.option_id, "obtain"), "ACTION_DUPLICATE", "Source action replay: " + item.id)
		Shop.new(db).sell_item(state, item.id, 1, "sell")
		instance = service.enter(state, "enter-again", source.event_id).result.instance_id
		ok(service.resolve(state, instance, source.option_id, "again").ok and state.inventory[item.id] == 1, "Sold rare material can be obtained again: " + item.id)
	var world := Probe.fixture(db, 9, "stable", [], ["world_kucao", "world_yiji"])
	world.spirit_stones = 1000
	var source := Sources.cheapest(db, world, "herb_jiuye")
	var instance: String = service.enter(world, "world-enter", source.event_id).result.instance_id
	ok(source.quantity == 2 and service.resolve(world, instance, source.option_id, "world-get").ok and world.inventory.herb_jiuye == 2 and world.spirit_stones == 900, "World herb yield is reflected in source preview and real settlement")
	ok(Sources.entries(db, world, "recipe_juling").is_empty() and Sources.entries(db, world, "missing").is_empty(), "Source discovery rejects nonmaterial and unknown IDs")
	var docs := Model.documents()
	# A conditional equipment option or a resource-cost trade must not be advertised as cash-only supply.
	docs.exploration_events.items[9].options[0].cost_items = {"ore_tiejing": 1}
	var restricted := Database.new()
	restricted.load_documents(docs)
	ok(Sources.entries(restricted, world, "essence_yuelu").is_empty(), "Discovery excludes material-cost trades from the cash-only cost basis")

func _recipes() -> void:
	var service := Alchemy.new(db)
	var index := 0
	for original in Model.proposal().recipes:
		var recipe: Dictionary = db.get_item(original.id)
		var state := Model.fixture(db, recipe, "stable")
		state.spirit_stones = 20000
		state.unlocked_recipes.erase(recipe.id)
		_reject(state, func(): return service.execute_alchemy(state, recipe.id, {}, "unlearned"), "RECIPE_LOCKED", "Cannot brew unlearned side recipe: " + recipe.id)
		var purchase := Shop.new(db).buy_item(state, recipe.id, 1, "learn")
		ok(purchase.ok and state.unlocked_recipes.has(recipe.id) and state.spirit_stones == 20000 - recipe.unlock.price, "Side recipe learns through shop transaction: " + recipe.id)
		var selected := Model.setup(state, recipe, "stable")
		var preview := service.preview_alchemy(state, recipe.id, selected)
		var mirrored := state.duplicate(true)
		var receipt := service.execute_alchemy(state, recipe.id, selected, "new-brew")
		var replay := service.execute_alchemy(mirrored, recipe.id, selected, "new-brew")
		ok(receipt.ok and replay == receipt and mirrored == state, "New recipe executes and replays complete state: " + recipe.id)
		var sampled := Statistics.new()._sample(recipe.id, preview.result, 199001 + index)
		ok(sampled.passed, "100000-sample shipping probability check: " + recipe.id)
		index += 1

func _compatibility() -> void:
	var old: RefCounted = Previous.database()
	var state := Probe.fixture(old, 5, "stable", [], [])
	var profile := Profile.new(old)
	var meta: Dictionary = profile.sync(state, profile.empty_meta())
	var path := "res://test-output/p8-catalog-old-%d.json" % OS.get_process_id()
	var saved := Saves.new(old, path).save_run(state, [], meta)
	var current := Session.new(path)
	ok(saved.ok and current.load_run().ok and current.state().unlocked_recipes == state.unlocked_recipes and current.state().inventory == state.inventory and current.state().rng_states == state.rng_states, "Schema2 pre-catalog save loads without granting new recipes, materials or rerolls")
	_cleanup(path)

func _route() -> void:
	var route := Route.new()
	var report := route.run()
	ok(report.ok, "Public-command route completes every side recipe and grandmaster: " + report.error)
	if not report.ok: return
	var session: RefCounted = report.session
	ok(report.records.size() == 13 and session.state().rank == 10 and session.state().owned_furnaces.size() == 6 and session.state().owned_flames.size() == 5, "Normal route acquires all gear and successfully brews all thirteen new recipes")
	for record in report.records:
		ok(record.rank == maxi(1, db.get_item(record.recipe).required_rank) and record.attempts >= 1, "Side recipe brewed at its first route milestone: " + record.recipe)
	var path := "res://test-output/p8-catalog-route-%d.json" % OS.get_process_id()
	Saves.new(db, path).save_run(session.state(), session.history(), session.meta())
	var loaded := Session.new(path)
	var discoveries: Array = session.meta().discovered_pills
	ok(loaded.load_run().ok and loaded.meta().discovered_pills == discoveries and loaded.state().unlocked_recipes == session.state().unlocked_recipes, "New recipe rights, inventory and permanent discoveries round-trip")
	ok(loaded.claim_inheritance(1, "heritage_baicao").ok and loaded.begin_rebirth(1, ["heritage_baicao"]).ok and loaded.state().unlocked_recipes == ["recipe_juling"] and loaded.meta().discovered_pills == discoveries, "Rebirth resets side recipe rights while keeping new permanent discoveries")
	_cleanup(path)

func _cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
