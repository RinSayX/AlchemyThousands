extends RefCounted
const Model := preload("res://tools/balance/contracts_model.gd")
const Catalog := preload("res://tools/balance/catalog_model.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Explore := preload("res://scripts/services/exploration_service.gd")
const Quests := preload("res://scripts/services/quest_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
const Equivalent := preload("res://tests/test_tuning.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tests/helpers/contracts_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")
var db := Database.new()
var check: Callable

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	_content()
	_consumables()
	_quests()
	_events()
	_route()
	return true

func ok(value: bool, message: String) -> void:
	check.call(value, "P8 contracts: " + message)

func _reject(state: Dictionary, operation: Callable, code: String, message: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = operation.call()
	ok(not result.ok and result.error_code == code and before == var_to_bytes(state), message)

func _content() -> void:
	var expected: RefCounted = Model.database()
	var matches := expected != null
	for category in Model.documents(): matches = matches and Equivalent.new()._equivalent(db.get_items(category), expected.get_items(category))
	ok(matches, "All 144 shipping definitions match the analyzed proposal")
	for invalid in [-1, 6, 1.5, "2", true, INF]:
		var docs := Model.documents()
		docs.consumables.items[-1].research_bonus = invalid
		ok(not db.load_documents(docs).ok and db.get_counts().quests == 20, "Reject invalid research bonus and retain cache: " + str(invalid))
	var docs := Model.documents()
	docs.furnaces.items[0].research_bonus = 2
	ok(not db.load_documents(docs).ok, "Research bonus cannot be injected into permanent equipment")
	ok(db.get_item("consumable_yanjiu").research_bonus is int, "Validated research integer normalizes")

func _consumables() -> void:
	var service := Alchemy.new(db)
	var recipe: Dictionary = db.get_item("recipe_bingxin")
	var state := Catalog.fixture(db, recipe, "stable")
	var selected := Catalog.setup(state, recipe, "stable")
	selected.consumable_id = "consumable_yanjiu"
	var before := var_to_bytes(state)
	var preview: Dictionary = service.preview_alchemy(state, recipe.id, selected).result
	ok(before == var_to_bytes(state) and preview.research_rewards.base == 3, "Incense preview is pure and exposes two extra base research")
	for success in [true, false]:
		var seed_value := 0
		for seed_candidate in range(1, 1025):
			if Rules.roll(preview, Context.new(seed_candidate)).success == success:
				seed_value = seed_candidate
				break
		var aided := state.duplicate(true)
		aided.rng_states = Context.new(seed_value).snapshot()
		var plain := aided.duplicate(true)
		var no_token := selected.duplicate()
		no_token.consumable_id = ""
		var a := service.execute_alchemy(aided, recipe.id, selected, "same")
		var b := service.execute_alchemy(plain, recipe.id, no_token, "same")
		ok(a.ok and b.ok and a.result.research_gained == b.result.research_gained + 2 and a.result.exp_gained == b.result.exp_gained and a.result.quality == b.result.quality and aided.rng_states == plain.rng_states and aided.inventory.consumable_yanjiu == 99, "Incense changes only base research and spends once on outcome " + str(success))
		_reject(aided, func(): return service.execute_alchemy(aided, recipe.id, selected, "same"), "ACTION_DUPLICATE", "Incense furnace action cannot replay")
	var high := Catalog.fixture(db, db.get_item("recipe_leijie"), "rush")
	var setup := Catalog.setup(high, db.get_item("recipe_leijie"), "rush")
	setup.consumable_id = "consumable_jiuzhuan"
	var boosted: Dictionary = service.preview_alchemy(high, "recipe_leijie", setup).result
	setup.strategy = "stable"
	var inactive: Dictionary = service.preview_alchemy(high, "recipe_leijie", setup).result
	setup.consumable_id = ""
	var normal: Dictionary = service.preview_alchemy(high, "recipe_leijie", setup).result
	ok(boosted.quality_transfers.any(func(row): return row.source == "consumable") and inactive.quality_weights == normal.quality_weights, "Nine-turn catalyst activates only under rush")
	_reject(state, func(): return service.execute_alchemy(state, recipe.id, {"consumable_id": ["consumable_yanjiu", "consumable_wendan"]}, "two"), "INVALID_SETUP", "One-consumable boundary remains enforced")
	var worlds := Catalog.fixture(db, recipe, "stable", ["world_kucao", "world_yiji"])
	worlds.equipped_inheritances = ["heritage_baicao"]
	ok(service.preview_alchemy(worlds, recipe.id, selected).result.research_rewards == {"base": 4, "new_quality": 3}, "Incense stacks once with world base research and separate discovery heritage")
	var overflowing := state.duplicate(true)
	overflowing.research_points = 2147483646
	_reject(overflowing, func(): return service.execute_alchemy(overflowing, recipe.id, selected, "overflow"), "AMOUNT_OVERFLOW", "Incense overflow rolls back material, token and RNG")
	var dragon := Catalog.fixture(db, db.get_item("recipe_jiuzhuan"), "stable")
	var twin := Catalog.setup(dragon, db.get_item("recipe_jiuzhuan"), "stable")
	twin.consumable_id = "consumable_shuangsheng"
	ok(is_equal_approx(service.preview_alchemy(dragon, "recipe_jiuzhuan", twin).result.extra_pill_chance, 0.45), "Twin talisman and dragon furnace disclose a combined 45 percent extra-pill chance")

func _quests() -> void:
	var service := Quests.new(db)
	var inventory := Inventory.new(db)
	for source in Model.proposal().quests:
		var quest: Dictionary = db.get_item(source.id)
		var state := Probe.fixture(db, quest.unlock.required_rank + 1, "stable", [], [])
		var accepted := service.accept(state, quest.id, "accept")
		var id: String = accepted.result.instance_id
		_reject(state, func(): return service.deliver(state, id, "missing"), "INSUFFICIENT_PILLS", "Commission cannot pay without consuming pills: " + quest.id)
		inventory.add_pill(state, quest.required_recipe_id, quest.min_quality, quest.quantity, "fixture-pills")
		var before: Dictionary = state.duplicate(true)
		var delivered := service.deliver(state, id, "deliver")
		ok(delivered.ok and state.spirit_stones == before.spirit_stones + quest.reward_spirit_stones and state.rng_states == before.rng_states and state.resource_stats.quests_completed == before.resource_stats.quests_completed + 1, "Commission pays exactly once and leaves RNG untouched: " + quest.id)
		_reject(state, func(): return service.deliver(state, id, "fresh"), "QUEST_ALREADY_COMPLETED", "Fresh action cannot reclaim completed commission: " + quest.id)
		var again := service.accept(state, quest.id, "again")
		ok(again.ok == quest.repeatable, "Repeatability follows each commission definition: " + quest.id)
	var world := Probe.fixture(db, 9, "stable", [], ["world_huoling", "world_dansheng"])
	world.equipped_inheritances = ["heritage_yandan"]
	var transformed := Lineage.quest(db, world, db.get_item("quest_jiuzhuan_order"))
	ok(transformed.min_quality == "common" and transformed.reward_spirit_stones == int(floor(db.get_item("quest_jiuzhuan_order").reward_spirit_stones * 1.25)), "New commissions honor existing world reward/quality and inheritance rules")

func _events() -> void:
	var service := Explore.new(db)
	for event in Model.proposal().exploration_events:
		var state := Probe.fixture(db, event.unlock.required_rank + 1, "stable", [], [])
		state.spirit_stones = 1000
		var instance: String = service.enter(state, "enter", event.id).result.instance_id
		var before: Dictionary = state.duplicate(true)
		ok(service.resolve(state, instance, "choice_safe", "safe").ok and state.spirit_stones == before.spirit_stones - event.options[0].cost_stones and state.rng_states == before.rng_states, "Safe encounter pays fixed fee with no RNG: " + event.id)
		instance = service.enter(state, "risk-enter", event.id).result.instance_id
		var mirrored := state.duplicate(true)
		var rng: Dictionary = state.rng_states.duplicate(true)
		var result := service.resolve(state, instance, "choice_risk", "risk")
		var same := service.resolve(mirrored, instance, "choice_risk", "risk")
		ok(result.ok and result == same and state == mirrored and state.rng_states.streams.exploration != rng.streams.exploration and state.rng_states.streams.alchemy == rng.streams.alchemy and state.rng_states.streams.world == rng.streams.world, "Risky encounter replays and advances exploration stream only: " + event.id)

func _route() -> void:
	var report := Route.new().run()
	ok(report.ok, "Public-command route completes new commissions: " + report.error)
	if not report.ok: return
	ok(report.deliveries.size() == 15 and report.session.state().rank == 10, "All fifteen new commissions deliver using real brewed pills before grandmaster")
	var path := "res://test-output/p8-contracts-%d.json" % OS.get_process_id()
	var session: RefCounted = report.session
	Saves.new(db, path).save_run(session.state(), session.history(), session.meta())
	var loaded := Session.new(path)
	ok(loaded.load_run().ok and loaded.state().quest_instances == session.state().quest_instances and loaded.state().inventory == session.state().inventory, "New commission instances, rewards and stock survive schema2 round-trip")
	ok(loaded.claim_inheritance(1, "heritage_baicao").ok and loaded.begin_rebirth(1, ["heritage_baicao"]).ok and loaded.state().quest_instances.is_empty() and loaded.meta().records.size() == 1, "Rebirth clears commission state and preserves permanent completion history")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
