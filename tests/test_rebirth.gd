extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Validator := preload("res://scripts/core/content_validator.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Rebirth := preload("res://scripts/services/rebirth_service.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const OldSaves := preload("res://tests/test_save_load.gd")
const Route := preload("res://tests/helpers/progression_route.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const AlchemyRules := preload("res://scripts/core/alchemy_rules.gd")
const Rules := preload("res://scripts/core/lineage_rules.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Resources := preload("res://scripts/core/resource_state.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Quests := preload("res://scripts/services/quest_service.gd")
const Explore := preload("res://scripts/services/exploration_service.gd")
const Forage := preload("res://scripts/services/forage_service.gd")
var _check: Callable
var db := Database.new()
var profiles: Profile
var rebirth: Rebirth
var completed: Dictionary
var permanent: Dictionary
var directory: String


func run(check: Callable) -> bool:
	_check = check
	if not db.load_directory().ok: return false
	profiles = Profile.new(db)
	rebirth = Rebirth.new(db)
	directory = "res://test-output/p7-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var report := Route.new().run()
	if not report.ok:
		_check.call(false, "P7: Real ending route prepares a valid first-life checkpoint")
		return false
	completed = report.session.state()
	permanent = report.session.meta()
	_content()
	_flow()
	_effects()
	_world_generation()
	_probability()
	_save_failures_and_migration()
	for name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	return true


func _snapshot(session: RefCounted) -> PackedByteArray:
	return var_to_bytes({"run": session.state(), "meta": session.meta()})


func _finished(path: String = "") -> Session:
	var file_path := path if not path.is_empty() else directory.path_join("checkpoint.json")
	Saves.new(db, file_path).save_run(completed, [], permanent)
	var session := Session.new(file_path)
	session.load_run()
	return session


func _reject(session: RefCounted, operation: Callable, code: String, label: String) -> void:
	var before := _snapshot(session)
	var result: Dictionary = operation.call()
	_check.call(not result.ok and result.error_code == code and before == _snapshot(session), "P7 atomic: " + label)


func _content() -> void:
	var original: Dictionary = {}
	for category in Validator.CATEGORIES:
		original[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % category))
	var cases := [
		["inheritances", ["items", 0, "effect"], "execute_script"],
		["inheritances", ["items", 0, "effect"], "first_quest_stones"],
		["inheritances", ["items", 0, "amount"], INF],
		["inheritances", ["items", 0, "amount"], -1],
		["inheritances", ["items", 0, "min_completed_runs"], 0],
		["inheritances", ["items", 1, "amount"], 1.1],
		["world_modifiers", ["items", 0, "weight"], 0],
		["world_modifiers", ["items", 0, "weight"], NAN],
		["world_modifiers", ["items", 0, "opportunity"], "yes"],
		["world_modifiers", ["items", 0, "min_run_number"], 1],
		["world_modifiers", ["items", 0, "exclusive_with"], ["world_missing"]],
		["world_modifiers", ["items", 0, "exclusive_with"], ["world_lingqi"]],
		["world_modifiers", ["items", 0, "exclusive_with"], []],
		["world_modifiers", ["items", 0, "changes"], {"script": "evil"}],
		["world_modifiers", ["items", 0, "changes"], {"success_bonus": 1.1}],
		["world_modifiers", ["items", 0, "changes"], {"suppress_special_flames": 1}],
		["world_modifiers", ["items", 0, "changes"], {"research_per_attempt": 0.5}],
		["world_modifiers", ["items", 0, "changes"], {"research_per_attempt": 1}],
		["exploration_events", ["items", 3, "options", 2, "required_heritage"], "heritage_missing"],
		["exploration_events", ["items", 3, "options", 2, "reward_furnace"], "furnace_missing"],
	]
	for i in range(cases.size()):
		var data := original.duplicate(true)
		var current: Variant = data[cases[i][0]]
		for j in range(cases[i][1].size() - 1): current = current[cases[i][1][j]]
		current[cases[i][1][-1]] = cases[i][2]
		var result := db.load_documents(data)
		_check.call(not result.ok and not result.errors.is_empty() and db.get_counts().inheritances == 9, "P7 content rejects invalid lineage field %d" % i)
	var none := original.duplicate(true)
	for world in none.world_modifiers.items: world.opportunity = false
	_check.call(not db.load_documents(none).ok, "P7: Content requires an opportunity in a reachable world pair")
	_check.call(db.get_item("heritage_baicao").min_completed_runs is int and db.get_item("world_yiji").min_run_number is int, "P7: Lineage JSON integer fields normalize")


func _flow() -> void:
	var fresh := Session.new()
	fresh.new_run(7)
	_check.call(fresh.state().run_number == 1 and fresh.state().world_modifiers.is_empty() and fresh.meta().records.is_empty(), "P7: First life is always a standard world with no inherited equipment")
	_reject(fresh, func() -> Dictionary: return fresh.claim_inheritance(1, "heritage_baicao"), "ENDING_REQUIRED", "No reward before ending")
	_reject(fresh, func() -> Dictionary: return fresh.begin_rebirth(1, []), "REWARD_REQUIRED", "No rebirth before ending and claim")
	var session := _finished()
	_check.call(profiles.validate(session.state(), session.meta()).ok and session.meta().records.size() == 1 and session.meta().highest_completed_run == 1 and session.meta().heritage_slots == 1, "P7: First ending archives statistics and unlocks one inheritance slot exactly once")
	var detached := session.meta()
	detached.records.clear()
	_check.call(session.meta().records.size() == 1, "P7: Permanent snapshots cannot alias owned state")
	var before := _snapshot(session)
	var view := session.rebirth_status()
	_check.call(view.ok and view.result.choices.size() == 3 and before == _snapshot(session), "P7: Three eligible unlock choices are pure and stable")
	_reject(session, func() -> Dictionary: return session.new_run(9), "REBIRTH_REQUIRED", "Restart cannot bypass an ended life's reward and composite transition")
	_reject(session, func() -> Dictionary: return session.claim_inheritance(1, "heritage_yuanqi"), "INVALID_REWARD", "Cannot claim outside the current offer")
	_check.call(session.claim_inheritance(1, "heritage_baicao").ok and session.meta().unlocked_inheritances == ["heritage_baicao"] and session.saved_run().result.meta.unlocked_inheritances == ["heritage_baicao"], "P7: Reward selection persists its unlock and archive entry together")
	_reject(session, func() -> Dictionary: return session.claim_inheritance(1, "heritage_luyin"), "REWARD_ALREADY_CLAIMED", "A new command cannot reselect or duplicate an ending reward")
	_reject(session, func() -> Dictionary: return session.begin_rebirth(1, ["heritage_luyin"]), "INVALID_LOADOUT", "Cannot equip a locked inheritance")
	_reject(session, func() -> Dictionary: return session.begin_rebirth(1, ["heritage_baicao", "heritage_baicao"]), "INVALID_LOADOUT", "Duplicate equipment cannot exceed one slot")
	before = _snapshot(session)
	var planned := session.preview_rebirth(["heritage_baicao"])
	_check.call(planned.ok and planned == session.preview_rebirth(["heritage_baicao"]) and before == _snapshot(session), "P7: Repeated next-world previews never advance live RNG or reset resources")
	var old_meta := session.meta()
	_check.call(session.begin_rebirth(1, ["heritage_baicao"]).ok, "P7: Explicit composite transition starts the second life")
	var run := session.state()
	_check.call(run.run_number == 2 and run.rank == 0 and run.exp == 0 and run.research_points == 0 and run.spirit_stones == 200 and run.inventory == {"herb_lingcao": 5, "herb_qinghua": 3} and run.pills.is_empty(), "P7: Currency, material/pill inventory, rank and experience reset to the new-life baseline")
	_check.call(run.owned_furnaces == ["furnace_basic"] and run.owned_flames == ["flame_normal"] and run.unlocked_recipes == ["recipe_juling"] and run.talent_choices.is_empty() and run.quest_instances.is_empty() and run.action_count == 0 and run.ending.is_empty() and session.history().is_empty(), "P7: Equipment, recipe permissions, talents, quests, statistics, ending and recent history reset")
	_check.call(run.equipped_inheritances == ["heritage_baicao"] and run.world_modifiers.size() == 2 and session.meta().discovered_pills == old_meta.discovered_pills and session.meta().quality_of_life_unlocks == old_meta.quality_of_life_unlocks and session.meta().records[0].next_run == 2 and session.meta().best_records == old_meta.best_records, "P7: Chosen inheritance and all permanent records survive; archive records the committed next life")
	_reject(session, func() -> Dictionary: return session.begin_rebirth(1, []), "RUN_CHANGED", "Old confirmation cannot transition twice after the source life changes")
	var loaded := Session.new(session.save_path)
	_check.call(loaded.load_run().ok and loaded.state() == session.state() and loaded.meta() == session.meta(), "P7: Second life and permanent history round-trip in one envelope")
	var a := session.begin_brew("recipe_juling", {})
	var b := loaded.begin_brew("recipe_juling", {})
	_check.call(a.ok and a == b and session.state() == loaded.state() and session.meta() == loaded.meta(), "P7: Second-life furnace continues identical results and permanent discovery state after reload")
	session.finish_brew()
	var discoveries: Array = session.meta().discovered_pills
	_check.call(session.new_run(11).ok and session.state().run_number == 2 and session.state().equipped_inheritances == ["heritage_baicao"] and session.meta().discovered_pills == discoveries and session.state().world_modifiers == run.world_modifiers, "P7: Restarting unfinished life preserves permanent discoveries, equipment choice and its world rules")
	# Complete life two using only normal commands, then unlock the second slot.
	var report := Route.new().run("research", 10, true, session)
	_check.call(report.ok, "P7 full route: second life can reach grandmaster under generated world rules")
	if not report.ok:
		printerr(report.error)
		return
	_check.call(session.meta().records.size() == 2 and session.meta().heritage_slots == 2 and "two_endings" in session.meta().achievements and session.meta().records[0].ending == old_meta.records[0].ending, "P7: Two completed lives unlock two slots without rewriting prior results")
	_check.call(session.claim_inheritance(2, "heritage_luyin").ok and session.begin_rebirth(2, ["heritage_baicao", "heritage_luyin"]).ok and session.state().equipped_inheritances.size() == 2, "P7: Third life can equip two unlocked distinct inheritances")
	var carried := session.meta()
	for i in range(3, 11):
		# Structural multi-life fixture, separate from the real first/second route.
		var ended := completed.duplicate(true)
		for field in ["run_number", "run_id", "run_seed", "equipped_inheritances", "world_modifiers"]:
			ended[field] = session.state()[field]
		ended.heritage_reward = ""
		var next_meta := profiles.sync(ended, session.meta())
		Saves.new(db, session.save_path).save_run(ended, [], next_meta)
		session = Session.new(session.save_path)
		session.load_run()
		var offer := session.rebirth_status()
		var choice: String = offer.result.choices[0].id if not offer.result.choices.is_empty() else "legacy_insight"
		var claimed := session.claim_inheritance(i, choice)
		_check.call(claimed.ok, "P7 reward fixture: life %d grants exactly one available reward" % i)
		if i == 10:
			_check.call(choice == "legacy_insight" and session.meta().legacy_insight == 1 and session.meta().unlocked_inheritances.size() == 9 and "all_inheritances" in session.meta().achievements, "P7: Exhausted inheritance pool offers one recorded alternative permanent insight")
			_reject(session, func() -> Dictionary: return session.claim_inheritance(i, choice), "REWARD_ALREADY_CLAIMED", "Alternative reward cannot be reclaimed")
		_check.call(session.begin_rebirth(i, []).ok, "P7 reward fixture: next-life initialization %d remains valid" % (i + 1))
	_check.call(session.state().research_points == 1 and session.meta().records.size() == 10 and session.meta().discovered_pills.size() >= carried.discovered_pills.size(), "P7: Alternative insight applies at next initialization and permanent history remains cumulative")


func _base(heritages: Array = [], worlds: Array = []) -> Dictionary:
	var state: Dictionary = Resources.new(db).create_state(1).result.state
	state["equipped_inheritances"] = heritages
	state["world_modifiers"] = worlds
	return state


func _effects() -> void:
	var alchemy := Alchemy.new(db)
	var shop := Shop.new(db)
	var inventory := Inventory.new(db)
	var quests := Quests.new(db)
	var explore := Explore.new(db)
	var forage := Forage.new(db)
	var run := _base(["heritage_luyin"])
	_check.call(is_equal_approx(alchemy.preview_alchemy(run, "recipe_juling").result.success_rate, 0.83), "P7 effect: Basic furnace seal adds exactly three percentage points")
	run.owned_furnaces.append("furnace_qingmu")
	_check.call(alchemy.preview_alchemy(run, "recipe_juling", {"furnace_id": "furnace_qingmu"}).result.success_breakdown.get("inheritance", 0.0) == 0, "P7 effect: Furnace seal does not stack onto a different furnace")
	run = _base(["heritage_baicao"])
	var outcome := alchemy.execute_alchemy(run, "recipe_juling", {}, "discovery")
	_check.call(outcome.ok and outcome.result.success and outcome.result.research_gained == 4, "P7 effect: First-quality discovery actually grants the extra inherited research")
	run = _base(["heritage_huozhong"])
	run.rank = 1
	inventory.add_items(run, {"ore_tiejing": 2}, "ore")
	var id: String = explore.enter(run, "enter", "event_earth_fire").result.instance_id
	var option := explore.preview_option(run, id, "choice_ritual")
	_check.call(option.result.option.cost_stones == 15 and explore.resolve(run, id, "choice_ritual", "ritual").ok and run.spirit_stones == 185 and "flame_earth" in run.owned_flames, "P7 effect: Flame seed halves ritual coins in preview and execution while still granting the flame")
	run = _base(["heritage_wendan"])
	id = quests.accept(run, "quest_juling_supply", "q1").result.instance_id
	inventory.add_pill(run, "recipe_juling", "common", 1, "pill1")
	quests.deliver(run, id, "d1")
	_check.call(run.spirit_stones == 260, "P7 effect: First daily commission gets its twenty-stone inherited bonus")
	id = quests.accept(run, "quest_juling_supply", "q2").result.instance_id
	inventory.add_pill(run, "recipe_juling", "common", 1, "pill2")
	quests.deliver(run, id, "d2")
	_check.call(run.spirit_stones == 300, "P7 effect: Repeated commission does not regain the first-completion bonus")
	run = _base(["heritage_jizhuan"])
	var plain := alchemy.preview_alchemy(_base(), "recipe_juling", {"strategy": "rush"})
	var inherited := alchemy.preview_alchemy(run, "recipe_juling", {"strategy": "rush"})
	_check.call(is_equal_approx(inherited.result.raw_success_rate, plain.result.raw_success_rate - 0.02) and inherited.result.quality_weights.legendary == plain.result.quality_weights.legendary + 2, "P7 effect: Nine-turn awareness applies disclosed rush risk and weight transfer")
	run = _base(["heritage_huishou"])
	inventory.add_items(run, {"material_danzha": 2}, "residue")
	_check.call(shop.quote_sell(run, [{"item_id": "material_danzha", "quantity": 2}]).result.total == 12 and shop.sell_item(run, "material_danzha", 2, "sell").ok and run.spirit_stones == 212, "P7 effect: Ash return prices and pays doubled residue exactly once")
	run = _base()
	run.rank = 1
	id = explore.enter(run, "locked-enter", "event_mineral_vein").result.instance_id
	var before := var_to_bytes(run)
	_check.call(explore.resolve(run, id, "choice_furnace_trace", "locked").error_code == "OPTION_LOCKED" and before == var_to_bytes(run), "P7 effect: Extra furnace option cannot be executed without its inheritance")
	explore.leave(run, id, "leave")
	run.equipped_inheritances = ["heritage_tuolu"]
	inventory.add_items(run, {"ore_tiejing": 8}, "ore-trace")
	id = explore.enter(run, "trace-enter", "event_mineral_vein").result.instance_id
	_check.call(explore.resolve(run, id, "choice_furnace_trace", "trace").ok and run.spirit_stones == 20 and "furnace_qingmu" in run.owned_furnaces and run.inventory.ore_tiejing == 4, "P7 effect: Furnace tracing consumes exact coins/items and grants real equipment")
	run = _base(["heritage_yandan"])
	_check.call(quests.board(run).result.rows[2].template.min_quality == "good", "P7 effect: Pill insight exposes the actual lowered commission quality")
	id = quests.accept(run, "quest_juling_elite", "elite").result.instance_id
	inventory.add_pill(run, "recipe_juling", "good", 1, "good-pill")
	_check.call(quests.deliver(run, id, "elite-delivery").ok, "P7 effect: Lowered quality is honored by actual delivery, not only the UI")
	run = _base(["heritage_yuanqi"])
	run.inventory.clear()
	_check.call(forage.preview(run).result.heritage_supply and forage.forage(run, "inherited-supply").ok and run.forage_uses == 0 and run.resource_stats.heritage_supplies == 1, "P7 effect: First shortage uses the one-time inherited supply without consuming forage charges")
	inventory.consume_items(run, run.inventory.duplicate(), "use-supply")
	_check.call(not forage.preview(run).result.heritage_supply and forage.forage(run, "ordinary-supply").ok and run.forage_uses == 1, "P7 effect: Later shortages return to the ordinary renewable forage route")
	run = _base([], ["world_lingqi"])
	_check.call(is_equal_approx(alchemy.preview_alchemy(run, "recipe_juling").result.success_rate, 0.83), "P7 world: Spirit revival applies its visible success modifier")
	run = _base([], ["world_kucao"])
	_check.call(shop.quote_buy(run, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}]).result.total == 18 and alchemy.preview_alchemy(run, "recipe_juling").result.material_shop_cost == 18, "P7 world: Herb scarcity changes authoritative shop and alchemy preview costs consistently")
	id = explore.enter(run, "gather-enter", "event_qinglan").result.instance_id
	option = explore.preview_option(run, id, "choice_gather")
	_check.call(option.result.option.success_items == {"herb_lingcao": 3, "herb_qinghua": 2} and explore.resolve(run, id, "choice_gather", "gather").result.items == option.result.option.success_items, "P7 world: Scarcity's exploration compensation uses the same shown and awarded item quantities")
	run = _base([], ["world_huoling"])
	run.rank = 1
	run.unlocked_recipes.append("recipe_cuiti")
	var fire := alchemy.preview_alchemy(run, "recipe_cuiti")
	_check.call(is_equal_approx(fire.result.success_rate, 0.67) and fire.result.quality_weights.legendary == 4, "P7 world: Fire unrest changes fire-recipe risk and quality without inventing mutation support")
	run = _base([], ["world_dansheng"])
	var board := quests.board(run)
	_check.call(board.result.rows[0].template.min_quality == "common" and board.result.rows[0].template.reward_spirit_stones == 50 and board.result.rows[2].template.min_quality == "legendary", "P7 world: Prosperity raises optional order quality/reward while preserving deterministic basic progression")
	run = _base([], ["world_yiji"])
	var rng := Context.new(2)
	run.rng_states = rng.snapshot()
	outcome = alchemy.execute_alchemy(run, "recipe_juling", {}, "failure-research")
	_check.call(outcome.ok and not outcome.result.success and outcome.result.research_gained == 2, "P7 world: Ruins grant extra base research even on actual failed furnaces")
	run = _base([], ["world_jinhuo"])
	run.owned_flames.append("flame_earth")
	var normal := alchemy.preview_alchemy(run, "recipe_juling")
	var earth := alchemy.preview_alchemy(run, "recipe_juling", {"flame_id": "flame_earth"})
	_check.call(is_equal_approx(normal.result.success_rate, 0.85) and is_equal_approx(earth.result.success_rate, 0.8) and earth.result.success_breakdown.flame == 0 and "flame_earth" in run.owned_flames, "P7 world: Forbidden fire suppresses bonuses without removing ownership needed by mainline certification")


func _world_generation() -> void:
	var session := _finished(directory.path_join("worlds.json"))
	session.claim_inheritance(1, "heritage_baicao")
	var seen: Dictionary = {}
	var all_valid := true
	var untouched := true
	for seed_value in range(200):
		var state := session.state()
		state.rng_states.streams.world = Context.new(seed_value).snapshot().streams.world
		var before := var_to_bytes(state)
		var plan := rebirth.preview_next(state, session.meta(), ["heritage_baicao"])
		all_valid = all_valid and plan.ok
		if not plan.ok: break
		var worlds: Array = plan.result.worlds
		all_valid = all_valid and worlds.size() == 2 and worlds[0].opportunity and worlds[0].id != worlds[1].id and worlds[1].id not in worlds[0].exclusive_with and worlds[0].id not in worlds[1].exclusive_with
		var initial_rng := Context.new(plan.result.state.run_seed.to_int()).snapshot()
		all_valid = all_valid and plan.result.state.rng_states.streams.alchemy == initial_rng.streams.alchemy and plan.result.state.rng_states.streams.exploration == initial_rng.streams.exploration and plan.result.state.rng_states.streams.world != initial_rng.streams.world
		untouched = untouched and before == var_to_bytes(state)
		for world in worlds: seen[world.id] = true
	_check.call(all_valid and seen.size() == 6, "P7 worlds: Two hundred deterministic seeds cover all six rules, with two distinct compatible rules and at least one opportunity")
	_check.call(untouched, "P7 worlds: Generation previews advance only disposable world RNG; live state and other next-life streams remain untouched")
	var plan := session.preview_rebirth(["heritage_baicao"])
	var next_meta := session.meta()
	next_meta.records[0].next_run = 2
	for pair in [["world_lingqi", "world_jinhuo"], ["world_huoling", "world_jinhuo"], ["world_lingqi", "world_lingqi"], ["world_kucao", "world_huoling"]]:
		var state: Dictionary = plan.result.state.duplicate(true)
		state.world_modifiers = pair
		_check.call(not profiles.validate(state, next_meta).ok, "P7 worlds: Invalid/conflicting/no-opportunity pair cannot be loaded: " + str(pair))


func _probability() -> void:
	for fire in [false, true]:
		var state := _base(["heritage_luyin", "heritage_jizhuan"] if fire else ["heritage_baicao"], ["world_huoling", "world_yiji"] if fire else ["world_yiji", "world_jinhuo"])
		var recipe := "recipe_cuiti" if fire else "recipe_juling"
		if fire:
			state.rank = 1
			state.unlocked_recipes.append(recipe)
		var snapshot: Dictionary = Alchemy.new(db).preview_alchemy(state, recipe, {"strategy": "rush" if fire else "normal"}).result
		var before := var_to_bytes(state)
		var rng := Context.new(20261119)
		var successes := 0
		var qualities := {"common": 0, "good": 0, "superior": 0, "legendary": 0}
		for i in range(100000):
			var outcome := AlchemyRules.roll(snapshot, rng)
			if outcome.success:
				successes += 1
				qualities[outcome.quality] += 1
		var valid: bool = before == var_to_bytes(state) and absf(successes / 100000.0 - snapshot.success_rate) <= 0.01
		for quality in qualities:
			var expected: float = snapshot.quality_probabilities[quality]
			valid = valid and absf(qualities[quality] / float(successes) - expected) <= maxf(0.000001, 6 * sqrt(expected * (1 - expected) / successes))
		_check.call(valid, "P7 statistics: %s 100000 furnaces, success %.5f / %.5f and four conditional qualities pass" % ["fire/rush/lineage" if fire else "normal/forbidden-fire", successes / 100000.0, snapshot.success_rate])


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _save_failures_and_migration() -> void:
	var path := directory.path_join("transaction.json")
	var session := _finished(path)
	var faulty := OldSaves.FaultSave.new(db, path)
	session._saves = faulty
	faulty.fail_write = true
	var disk := FileAccess.get_file_as_bytes(path)
	_reject(session, func() -> Dictionary: return session.claim_inheritance(1, "heritage_baicao"), "SAVE_WRITE_FAILED", "Failed reward write leaves both memory halves unclaimed")
	_check.call(FileAccess.get_file_as_bytes(path) == disk, "P7 save: Failed claim preserves the valid on-disk ending")
	faulty.fail_write = false
	session.claim_inheritance(1, "heritage_baicao")
	disk = FileAccess.get_file_as_bytes(path)
	for mode in ["write", "replace", "verify"]:
		faulty.fail_write = mode == "write"
		faulty.fail_replace = mode == "replace"
		faulty.corrupt_after_replace = mode == "verify"
		_reject(session, func() -> Dictionary: return session.begin_rebirth(1, ["heritage_baicao"]), {"write": "SAVE_WRITE_FAILED", "replace": "SAVE_REPLACE_FAILED", "verify": "SAVE_VERIFY_FAILED"}[mode], "Failed rebirth " + mode + " preserves ended run, unlock and RNG")
		var recovered := Session.new(path)
		_check.call(recovered.load_run().ok and recovered.state().run_number == 1 and recovered.state().heritage_reward == "heritage_baicao" and recovered.meta().records[0].next_run == 0, "P7 save: Interrupted " + mode + " reads a complete old generation, never a new run with old meta")
	faulty.fail_write = false
	faulty.fail_replace = false
	faulty.corrupt_after_replace = false
	_check.call(session.begin_rebirth(1, ["heritage_baicao"]).ok and session.state().run_number == 2, "P7 save: Retrying the same displayed transition succeeds exactly once")
	# Read a genuine P6-shaped v1 envelope without modifying it on load.
	var legacy := completed.duplicate(true)
	for field in ["run_number", "run_id", "run_seed", "equipped_inheritances", "world_modifiers", "heritage_reward"]: legacy.erase(field)
	legacy.resource_stats.erase("heritage_supplies")
	var payload := JSON.stringify({"run": legacy, "history": []})
	var envelope := {"schema_version": 1, "engine_version": Context.ENGINE_VERSION, "saved_at": "2026-11-18T00:00:00", "payload": payload, "checksum": payload.sha256_text()}
	path = directory.path_join("legacy.json")
	_write(path, JSON.stringify(envelope))
	disk = FileAccess.get_file_as_bytes(path)
	var migrated := Session.new(path)
	var read := migrated.load_run()
	_check.call(read.ok and read.result.migrated and migrated.state().rank == 10 and migrated.state().rng_states == completed.rng_states and migrated.meta().records.size() == 1 and FileAccess.get_file_as_bytes(path) == disk, "P7 migration: P6 v1 ending upgrades in memory without rewriting original resources, RNG or file")
	_check.call(migrated.claim_inheritance(1, "heritage_baicao").ok and JSON.parse_string(FileAccess.get_file_as_string(path)).schema_version == 2 and FileAccess.get_file_as_bytes(path + ".bak") == disk, "P7 migration: First successful transaction commits v2 and retains the intact v1 backup")
	for seed_text in ["9223372036854775807", "-9223372036854775808"]:
		var old_state: Dictionary = profiles.runs.create_state(seed_text.to_int()).result.state
		var old_payload := JSON.stringify({"run": old_state, "history": []})
		var old_envelope := {"schema_version": 1, "engine_version": Context.ENGINE_VERSION, "saved_at": "2026-11-18T00:00:00", "payload": old_payload, "checksum": old_payload.sha256_text()}
		var old_path := directory.path_join("seed-legacy.json")
		_write(old_path, JSON.stringify(old_envelope))
		var old_session := Session.new(old_path)
		var migrated_seed := old_session.load_run()
		_check.call(migrated_seed.ok and old_session.state().run_seed == seed_text and old_session.state().rng_states == old_state.rng_states, "P7 migration: Full int64 seed and RNG are reconstructed losslessly: " + seed_text)
	var current_bytes := FileAccess.get_file_as_bytes(path)
	_write(path, "broken")
	var fallback := Session.new(path)
	var loaded := fallback.load_run()
	_check.call(loaded.ok and loaded.result.recovered and loaded.result.migrated and fallback.meta().records.size() == 1, "P7 migration: A broken v2 primary can recover a v1 backup consistently")
	_write(path, current_bytes.get_string_from_utf8())
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for field in ["heritage_slots", "records", "unlocked_inheritances", "discovered_pills", "first_equipment", "early_fallback"]:
		var edited := good.duplicate(true)
		var contents: Dictionary = JSON.parse_string(edited.payload)
		if field == "heritage_slots": contents.meta.heritage_slots = 3
		if field == "records": contents.meta.records = []
		if field == "unlocked_inheritances": contents.meta.unlocked_inheritances.append("heritage_luyin")
		if field == "discovered_pills": contents.meta.discovered_pills.append("recipe_missing|common|")
		if field == "first_equipment":
			contents.run.equipped_inheritances = ["heritage_baicao"]
			contents.meta.records[0].equipped_inheritances = ["heritage_baicao"]
		if field == "early_fallback":
			contents.run.heritage_reward = "legacy_insight"
			contents.meta.records[0].reward = "legacy_insight"
			contents.meta.unlocked_inheritances = []
			contents.meta.legacy_insight = 1
		edited.payload = JSON.stringify(contents)
		edited.checksum = edited.payload.sha256_text()
		var invalid_path := directory.path_join("invalid-meta.json")
		_write(invalid_path, JSON.stringify(edited))
		var broken := Session.new(invalid_path)
		_check.call(not broken.load_run().ok and not broken.has_run(), "P7 save: Invalid permanent " + field + " is rejected without creating starter resources")
