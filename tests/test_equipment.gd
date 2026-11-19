extends RefCounted
const Model := preload("res://tools/balance/equipment_model.gd")
const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Explore := preload("res://scripts/services/exploration_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Route := preload("res://tests/helpers/equipment_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Equivalent := preload("res://tests/test_tuning.gd")
var db := Database.new()
var check: Callable

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	_content()
	_effects()
	_trials()
	_route()
	var sampled := Model.run()
	ok(sampled.ok and sampled.probability.size() == 9 and sampled.economy.size() == 9, "Nine shipping build probability and value probes pass 100000 samples each")
	return true

func ok(condition: bool, text: String) -> void:
	check.call(condition, "P8 equipment: " + text)

func _content() -> void:
	var expected: RefCounted = Model.database()
	var matches := expected != null
	for category in Model.documents():
		matches = matches and Equivalent.new()._equivalent(db.get_items(category).slice(0, expected.get_items(category).size()), expected.get_items(category))
	ok(matches, "All 84 pre-catalog definitions retain the independently analyzed equipment proposal")
	var mutations := [
		["furnaces", 4, "effect_strategy", "impossible"],
		["furnaces", 4, "effect_strategy", 1],
		["flames", 4, "effect_strategy", []],
		["flames", 4, "script_effect", "arbitrary"],
	]
	for test in mutations:
		var docs := Model.documents()
		docs[test[0]].items[test[1]][test[2]] = test[3]
		ok(not db.load_documents(docs).ok and db.get_counts().furnaces == 6, "Invalid equipment restriction rejected with cache retained: " + str(test[2]) + str(test[3]))
	var trials := [
		{"requires_unowned_reward": "yes"},
		{"success_rate": 0.9},
		{"reward_flame": ""},
		{"reward_furnace": "furnace_jiulong"},
		{"reward_flame": "flame_missing"},
	]
	for changes in trials:
		var docs := Model.documents()
		docs.exploration_events.items[5].options[0].merge(changes, true)
		ok(not db.load_documents(docs).ok and db.get_counts().exploration_events == 20, "Invalid once-per-life trial rejected: " + str(changes))

func _effects() -> void:
	var service := Alchemy.new(db)
	var thunder: Dictionary = Model.profiles()[3]
	var state := Model.fixture(db, thunder)
	var setup := Model.setup(thunder)
	var before := var_to_bytes(state)
	var rush: Dictionary = service.preview_alchemy(state, thunder.recipe, setup).result
	setup.strategy = "stable"
	var stable: Dictionary = service.preview_alchemy(state, thunder.recipe, setup).result
	setup.strategy = "normal"
	var normal: Dictionary = service.preview_alchemy(state, thunder.recipe, setup).result
	ok(before == var_to_bytes(state) and rush.quality_probabilities.legendary > normal.quality_probabilities.legendary, "Pure previews expose thunder's rush quality tradeoff")
	ok(stable.success_breakdown.furnace == 0 and stable.success_breakdown.flame == 0 and normal.success_breakdown.furnace == 0 and normal.success_breakdown.flame == 0 and stable.quality_probabilities.legendary == 0, "Both thunder pieces suppress all effects outside rush")
	var ice: Dictionary = Model.profiles()[1]
	var ice_state := Model.fixture(db, ice)
	var ice_base: Dictionary = service.preview_alchemy(ice_state, ice.recipe, {"strategy": "stable"}).result
	var ice_pair: Dictionary = service.preview_alchemy(ice_state, ice.recipe, Model.setup(ice)).result
	ok(is_equal_approx(ice_pair.material_refund_rate - ice_base.material_refund_rate, 0.45), "Ice pair contributes 45 percentage points of failure recovery")
	var inactive: Dictionary = Model.profiles()[7]
	var a := Model.fixture(db, inactive)
	var b := a.duplicate(true)
	var dragon := service.execute_alchemy(a, inactive.recipe, Model.setup(inactive), "same")
	var plain := service.execute_alchemy(b, inactive.recipe, {"strategy": "normal", "furnace_id": "furnace_basic", "flame_id": "flame_normal"}, "same")
	ok(dragon.ok and plain.ok and a.rng_states == b.rng_states and dragon.result.quantity == plain.result.quantity and dragon.result.quality == plain.result.quality and dragon.result.snapshot.extra_pill_chance == 0, "Inactive dragon changes neither sampling nor RNG consumption")
	var profile: Dictionary = Model.profiles()[5]
	var preview: Dictionary = service.preview_alchemy(Model.fixture(db, profile), profile.recipe, Model.setup(profile)).result
	var seed_value := 0
	for candidate in range(1, 513):
		if Rules.roll(preview, Context.new(candidate)).extra_pill:
			seed_value = candidate
			break
	ok(seed_value != 0, "A reproducible real sampler seed reaches shipping extra-pill branch")
	if seed_value == 0: return
	state = Model.fixture(db, profile)
	state.rng_states = Context.new(seed_value).snapshot()
	var original := state.duplicate(true)
	var receipt := service.execute_alchemy(state, profile.recipe, Model.setup(profile), "dragon-two")
	ok(receipt.ok and receipt.result.quantity == 2 and state.pills[Pills.key(profile.recipe, receipt.result.quality)].quantity == 2, "Shipping dragon grants two pills in one quality stack")
	var exact := true
	for id in preview.materials:
		exact = exact and state.inventory[id] == original.inventory[id] - preview.materials[id]
	ok(exact and state.statistics.alchemy_attempts == original.statistics.alchemy_attempts + 1 and state.exp == original.exp + preview.exp_rewards.success and state.research_points == original.research_points + preview.research_rewards.base + preview.research_rewards.new_quality, "Extra pill charges one batch and awards experience/research once")
	var replay := original.duplicate(true)
	var same := service.execute_alchemy(replay, profile.recipe, Model.setup(profile), "dragon-two")
	ok(same == receipt and replay == state, "Same seed and build replay the complete extra-pill transaction")

func _reject(state: Dictionary, action: Callable, code: String, text: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = action.call()
	ok(not result.ok and result.error_code == code and before == var_to_bytes(state), text)

func _trials() -> void:
	var service := Explore.new(db)
	var profile: Dictionary = Model.profiles()[1]
	var state := Model.fixture(db, profile)
	state.owned_furnaces = ["furnace_basic"]
	state.owned_flames = ["flame_normal"]
	state.spirit_stones = 20000
	var low := preload("res://tools/balance/economy_probe.gd").fixture(db, 4, "stable", [], [])
	_reject(low, func(): return service.enter(low, "locked", "event_xuanbing_trial"), "RANK_LOCKED", "Under-rank trial is atomic")
	var rng: Dictionary = state.rng_states.duplicate(true)
	var entered := service.enter(state, "enter-ice", "event_xuanbing_trial")
	ok(entered.ok and state.rng_states == rng, "Direct trial entry does not draw RNG")
	var instance: String = entered.result.instance_id
	var before := var_to_bytes(state)
	var view := service.preview_option(state, instance, "choice_forge_xuanbing")
	ok(view.ok and view.result.can_execute and before == var_to_bytes(state), "Trial cost preview is pure")
	state.spirit_stones = 0
	_reject(state, func(): return service.resolve(state, instance, "choice_forge_xuanbing", "poor"), "NOT_ENOUGH_STONES", "Insufficient trial money changes nothing")
	state.spirit_stones = 20000
	state.inventory.ore_tiejing = 0
	_reject(state, func(): return service.resolve(state, instance, "choice_forge_xuanbing", "missing"), "INSUFFICIENT_ITEMS", "Insufficient trial material changes nothing")
	state.inventory.ore_tiejing = 100
	var original := state.duplicate(true)
	var claimed := service.resolve(state, instance, "choice_forge_xuanbing", "forge")
	ok(claimed.ok and state.owned_furnaces.has("furnace_xuanbing") and state.spirit_stones == original.spirit_stones - 1200 and state.inventory.ore_tiejing == 94 and state.inventory.essence_hunlu == 98 and state.rng_states == rng, "Guaranteed trial spends exact costs and grants gear without RNG")
	_reject(state, func(): return service.resolve(state, instance, "choice_forge_xuanbing", "forge"), "ACTION_DUPLICATE", "Original action cannot claim twice")
	ok(service.destinations(state).result.rows[6].unlocked, "Partially claimed two-reward trial remains open")
	instance = service.enter(state, "enter-again", "event_xuanbing_trial").result.instance_id
	_reject(state, func(): return service.resolve(state, instance, "choice_forge_xuanbing", "duplicate-reward"), "REWARD_ALREADY_OWNED", "Fresh action rejects owned reward before any charge")
	ok(service.resolve(state, instance, "choice_attune_hansui", "ice-fire").ok, "Second option remains independently claimable")
	var row: Dictionary = service.destinations(state).result.rows[6]
	ok(row.completed and not row.unlocked and row.encounter_probability == 0, "Completed trial leaves the random pool")
	_reject(state, func(): return service.enter(state, "exhausted", "event_xuanbing_trial"), "EVENT_EXHAUSTED", "Completed trial direct entry spends no action or RNG")
	var sum := 0.0
	for offer in service.destinations(state).result.rows: sum += offer.encounter_probability
	ok(is_equal_approx(sum, 1), "Remaining random encounter weights renormalize to one")

func _route() -> void:
	var route := Route.new()
	var report := route.run()
	ok(report.ok, "Public-command acquisition route reaches grandmaster: " + report.error)
	if not report.ok: return
	var session: RefCounted = report.session
	ok(session.state().owned_furnaces.size() == 6 and session.state().owned_flames.size() == 5 and report.acquisitions.size() == 7, "Normal purchases and seven event transactions acquire all equipment")
	for acquisition in report.acquisitions:
		ok(acquisition.rank == session.content.get_item(acquisition.event).unlock.required_rank, "Reward acquired at its actual rank gate: " + acquisition.option)
	var completed := 0
	for row in session.destinations().result.rows:
		if row.completed: completed += 1
	ok(completed == 4, "All four resource trials finish without state injection")
	var path := "res://test-output/p8-equipment-test-%d.json" % OS.get_process_id()
	var saved := Saves.new(db, path).save_run(session.state(), session.history(), session.meta())
	var loaded := Session.new(path)
	var original: Dictionary = session.state()
	original.needs_save = false
	ok(saved.ok and loaded.load_run().ok and loaded.state() == original, "All gear and completion status survive schema2 round-trip")
	_reject(loaded._state, func(): return Explore.new(db).enter(loaded._state, "post-load", "event_jiulong_trial"), "EVENT_EXHAUSTED", "Reload cannot reclaim a trial")
	ok(loaded.claim_inheritance(1, "heritage_baicao").ok and loaded.begin_rebirth(1, ["heritage_baicao"]).ok, "Complete equipment run can claim inheritance and rebirth")
	completed = 0
	for row in loaded.destinations().result.rows:
		if row.completed: completed += 1
	ok(completed == 0 and loaded.state().owned_furnaces == ["furnace_basic"] and loaded.state().owned_flames == ["flame_normal"] and loaded.meta().unlocked_inheritances.has("heritage_baicao") and loaded.meta().records.size() == 1, "Rebirth resets trials and run gear while keeping permanent rewards")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
