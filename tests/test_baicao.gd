extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Spec := preload("res://scripts/core/baicao_definition.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Quests := preload("res://scripts/services/quest_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Service := preload("res://scripts/services/baicao_service.gd")
const Ending := preload("res://scripts/services/ending_trial_service.gd")
const Route := preload("res://tests/helpers/baicao_route.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Faults := preload("res://tests/test_save_load.gd")
const Analysis := preload("res://tools/baicao_analysis.gd")
var db := Database.new()
var check: Callable
var report: Dictionary
var profile: RefCounted
var service: RefCounted

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	profile = Profile.new(db)
	service = Service.new(db)
	_config()
	_mutation()
	_journal()
	report = Route.new().run()
	ok(report.ok, "Public command route reaches all three endings: " + report.error)
	if not report.ok: return false
	_plans()
	_saves()
	ok(Analysis.run_analysis().ok, "Production on/off profiles pass success, quality, mutation and multi-pill frequency bounds at 100000 samples")
	return true

func ok(value: bool, message: String) -> void:
	check.call(value, "P8 baicao: " + message)

func _config() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Spec.PATH))
	for field in ["chance", "required_rank", "recipe_id", "flame_id"]:
		var changed := original.duplicate(true)
		changed.mutation[field] = true
		ok(not Spec.validate(db, changed).ok, "Reject invalid mutation field " + field)
	for value in [-1, 0, INF, "0.2"]:
		var changed := original.duplicate(true)
		changed.mutation.chance = value
		ok(not Spec.validate(db, changed).ok, "Reject invalid mutation probability " + str(value))
	var changed := original.duplicate(true)
	changed.ending["script"] = "free_reward"
	ok(not Spec.validate(db, changed).ok and service.startup.ok, "Unknown scripted condition rejected; live definition valid")

func _fixture(worlds: Array = []) -> Dictionary:
	var state := Probe.fixture(db, 9, "rush", [], worlds)
	state.owned_furnaces = db.get_ids("furnaces")
	state.owned_flames = db.get_ids("flames")
	for id in db.get_ids("materials") + db.get_ids("consumables"): state.inventory[id] = 100
	return state

func _setup() -> Dictionary:
	return {"furnace_id": "furnace_jiulong", "flame_id": "flame_zixiao", "strategy": "rush", "consumable_id": "consumable_shuangsheng", "mutation_id": Pills.MUTATION_ID}

func _ordinary_roll(snapshot: Dictionary, rng: Context) -> Dictionary:
	# Frozen pre-mutation draw order, independent of the new mutation branch.
	if rng.next_float() >= snapshot.success_rate:
		return {"success": false, "quality": "", "quantity": 0, "mutation_id": "", "extra_pill": false}
	var quality := Rules.pick_quality(snapshot.quality_weights, rng.next_float())
	var extra: bool = snapshot.extra_pill_chance > 0 and rng.next_float() < snapshot.extra_pill_chance
	return {"success": true, "quality": quality, "quantity": 2 if extra else 1, "mutation_id": "", "extra_pill": extra}

func _reject(state: Dictionary, operation: Callable, code: String, message: String) -> void:
	var before := var_to_bytes(state)
	var result: Dictionary = operation.call()
	ok(not result.ok and result.error_code == code and before == var_to_bytes(state), message)

func _mutation() -> void:
	var alchemy := Alchemy.new(db)
	var state := _fixture()
	var setup := _setup()
	var frozen := var_to_bytes(state)
	var active: Dictionary = alchemy.preview_alchemy(state, Pills.MUTATION_RECIPE, setup).result
	ok(var_to_bytes(state) == frozen and active.mutation_chance == 0.2 and is_equal_approx(active.extra_pill_chance, 0.45), "Opt-in preview exposes independent mutation and extra-pill chances without spending or RNG")
	var off := setup.duplicate()
	off.erase("mutation_id")
	var plain: Dictionary = alchemy.preview_alchemy(state, Pills.MUTATION_RECIPE, off).result
	var a := Context.new(99)
	var b := Context.new(99)
	var ordinary_matches := true
	for i in range(64):
		if Rules.roll(plain, a) != _ordinary_roll(plain, b) or a.snapshot() != b.snapshot(): ordinary_matches = false
	ok(ordinary_matches, "Disabled mutation preserves previous sampler path and RNG consumption")
	var failure_seed := 0
	for candidate in range(1, 64):
		if not Rules.roll(active, Context.new(candidate)).success:
			failure_seed = candidate
			break
	a = Context.new(failure_seed)
	b = Context.new(failure_seed)
	ok(Rules.roll(active, a) == Rules.roll(plain, b) and a.snapshot() == b.snapshot(), "Failed brew draws neither mutation nor extra-pill outcomes")
	var seed_value := 0
	for seed_candidate in range(1, 2049):
		var roll := Rules.roll(active, Context.new(seed_candidate))
		if roll.mutation_id == Pills.MUTATION_ID and roll.extra_pill:
			seed_value = seed_candidate
			break
	ok(seed_value > 0, "Real sampler reaches a mutated double-pill outcome")
	state.rng_states = Context.new(seed_value).snapshot()
	var original := state.duplicate(true)
	var receipt := alchemy.execute_alchemy(state, Pills.MUTATION_RECIPE, setup, "mutant")
	var key := Pills.key(Pills.MUTATION_RECIPE, receipt.result.quality, Pills.MUTATION_ID)
	ok(receipt.ok and receipt.result.quantity == 2 and state.pills[key].quantity == 2 and state.statistics.alchemy_attempts == original.statistics.alchemy_attempts + 1, "Both extra pills share one quality/mutation stack and one furnace settlement")
	var mirrored := original.duplicate(true)
	ok(alchemy.execute_alchemy(mirrored, Pills.MUTATION_RECIPE, setup, "mutant") == receipt and mirrored == state, "Mutated complete transaction replays exactly")
	ok(state.rng_states.streams.exploration == original.rng_states.streams.exploration and state.rng_states.streams.world == original.rng_states.streams.world, "Mutation affects alchemy stream only")
	var shop := Shop.new(db)
	var inventory := Inventory.new(db)
	inventory.add_pill(state, Pills.MUTATION_RECIPE, receipt.result.quality, 1, "ordinary")
	var normal_key := Pills.key(Pills.MUTATION_RECIPE, receipt.result.quality)
	ok(state.pills.has(normal_key) and state.pills.has(key), "Ordinary and mutated pills never merge")
	var offer := shop.quote_sell(state, [{"recipe_id": Pills.MUTATION_RECIPE, "quality": receipt.result.quality, "quantity": 1, "mutation_id": Pills.MUTATION_ID}])
	ok(offer.ok and offer.result.total == Probe.price(db, Pills.MUTATION_RECIPE, receipt.result.quality), "Mutation keeps the same quality-based shop price")
	shop.sell_pill(state, Pills.MUTATION_RECIPE, receipt.result.quality, 1, "sell-mutant", Pills.MUTATION_ID)
	ok(state.pills[key].quantity == 1 and state.pills[normal_key].quantity == 1, "Explicit mutation sale consumes only that stack")
	var journal: Dictionary = profile.sync(state, profile.empty_meta())
	ok(journal.mutation_discoveries == [key], "Permanent mutation discovery records the full stack key")
	var quest: Dictionary = Quests.new(db).accept(state, "quest_niepan_order", "accept").result
	inventory.consume_pill(state, Pills.MUTATION_RECIPE, receipt.result.quality, 1, "remove-ordinary")
	ok(not Quests.new(db).preview_delivery(state, quest.instance_id).result.can_deliver, "Ordinary commissions do not silently consume rare mutated proof pills")
	var invalid := setup.duplicate()
	invalid.strategy = "stable"
	_reject(state, func(): return alchemy.execute_alchemy(state, Pills.MUTATION_RECIPE, invalid, "wrong-mode"), "MUTATION_UNAVAILABLE", "Ineligible strategy cannot enable mutation")
	var banned := _fixture(["world_yiji", "world_jinhuo"])
	_reject(banned, func(): return alchemy.execute_alchemy(banned, Pills.MUTATION_RECIPE, setup, "forbidden"), "MUTATION_UNAVAILABLE", "Suppressed special flame cannot enable mutation")
	var overflow := original.duplicate(true)
	overflow.pills[key] = Pills.create(Pills.MUTATION_RECIPE, receipt.result.quality, 2147483647, Pills.MUTATION_ID)
	_reject(overflow, func(): return alchemy.execute_alchemy(overflow, Pills.MUTATION_RECIPE, setup, "overflow"), "AMOUNT_OVERFLOW", "Mutant stack overflow rolls back costs and RNG")

func _journal() -> void:
	var session := Session.new()
	session.new_run(1)
	ok(session.meta().material_journal.run_1 == ["herb_lingcao", "herb_qinghua"], "New run logs actual initial material contact")
	var before := var_to_bytes(session.meta())
	session.quote_shop("herb_zhixue", 1)
	ok(var_to_bytes(session.meta()) == before, "Quotes do not invent material discoveries")
	session.buy_shop("herb_zhixue", 1)
	session.sell_shop("herb_zhixue", 1)
	ok("herb_zhixue" in session.meta().material_journal.run_1 and not session.state().inventory.has("herb_zhixue"), "Sold materials remain known in current life journal")
	var bad: Dictionary = session.meta()
	bad.material_journal["run_2"] = []
	ok(not profile.validate(session.state(), bad).ok, "Future-life journal entries are rejected")
	bad = session.meta()
	bad.mutation_discoveries = ["recipe_juling|common|mutation_qingling"]
	ok(not profile.validate(session.state(), bad).ok, "Invalid mutation discovery recipe is rejected")

func _plans() -> void:
	var point: Dictionary = report.checkpoints.before_mutation_study
	var state: Dictionary = point.state
	var meta: Dictionary = point.meta
	var before := var_to_bytes([state, meta])
	var plan: Dictionary = service.plan_study(state, meta, 1, "study")
	ok(plan.ok and before == var_to_bytes([state, meta]) and plan.result.state.research_points == state.research_points - 180 and plan.result.state.rng_states == state.rng_states, "Deterministic mutation study is pure until committed and spends exact research without RNG")
	var proof := Pills.key(Pills.MUTATION_RECIPE, "superior", Pills.MUTATION_ID)
	ok(plan.result.state.pills[proof].quantity == 1 and plan.result.meta.mutation_discoveries.has(proof), "Study produces registered mutated superior pill and permanent discovery")
	point = report.checkpoints.before_baicao
	var certified: Dictionary = service.plan_certify(point.state, point.meta, 1, "certify")
	ok(certified.ok and certified.result.meta.records[0].optional_endings.size() == 2 and certified.result.state.research_points == point.state.research_points - 120 and certified.result.state.ending == point.state.ending and certified.result.meta.records[0].optional_endings[0] == point.meta.records[0].optional_endings[0], "Baicao certification appends alongside immutable Jiuzhuan and standard records")
	ok(certified.result.meta.records[0].optional_endings[1].evidence.materials.size() == 25 and not certified.result.state.pills.has(proof), "Archive freezes 25 actual material contacts and consumes one mutant proof")
	var failed: Dictionary = service.plan_certify(certified.result.state, certified.result.meta, 1, "again")
	ok(not failed.ok and failed.error_code == "ENDING_ALREADY_CERTIFIED", "Fresh action cannot claim Baicao twice")
	var missing_meta: Dictionary = point.meta.duplicate(true)
	missing_meta.material_journal.run_1.erase("herb_zhixue")
	failed = service.plan_certify(point.state, missing_meta, 1, "missing")
	ok(not failed.ok and failed.error_code == "BAICAO_REQUIREMENTS", "Permanent or other-life contacts cannot replace missing current-life material evidence")
	# Certify in the reverse order as well; both services must append rather than overwrite.
	var reverse: Dictionary = point.meta.duplicate(true)
	reverse.records[0].erase("optional_endings")
	reverse = profile.sync(point.state, reverse)
	var baicao: Dictionary = service.plan_certify(point.state, reverse, 1, "first-baicao")
	ok(baicao.ok and not Ending.new(db).preview(baicao.result.state, baicao.result.meta).result.completed, "Baicao first does not mark the Jiuzhuan trial complete")
	var reverse_state: Dictionary = baicao.result.state
	var inventory := Inventory.new(db)
	inventory.add_pill(reverse_state, "recipe_taichu", "legendary", 1, "proof-a")
	inventory.add_pill(reverse_state, "recipe_jiuzhuan", "legendary", 1, "proof-b")
	var second: Dictionary = Ending.new(db).plan_certify(reverse_state, baicao.result.meta, 1, "then-nine")
	ok(second.ok and second.result.meta.records[0].optional_endings.size() == 2 and second.result.meta.records[0].optional_endings[0].id == "ending_baicao", "Reverse-order Jiuzhuan certification appends without overwriting Baicao")
	var early: Dictionary = profile.create_run(3).result.state
	var early_meta: Dictionary = profile.sync(early, profile.empty_meta())
	ok(service.plan_study(early, early_meta, 1, "early").error_code == "MUTATION_STUDY_LOCKED", "Deterministic mutant study stays locked before standard completion")
	var locked: Dictionary = report.checkpoints.before_mutation_study.state.duplicate(true)
	locked.research_points = 0
	ok(service.plan_study(locked, report.checkpoints.before_mutation_study.meta, 1, "no-points").error_code == "INSUFFICIENT_RESEARCH", "Mutation study cannot spend unavailable research")
	locked = report.checkpoints.before_mutation_study.state.duplicate(true)
	locked.inventory.erase("herb_shouxian")
	ok(service.plan_study(locked, report.checkpoints.before_mutation_study.meta, 1, "no-items").error_code == "INSUFFICIENT_ITEMS", "Mutation study cannot skip missing materials")

func _saves() -> void:
	var path := "res://test-output/p8-baicao-%d.json" % OS.get_process_id()
	var initial: Dictionary = report.checkpoints.before_mutation_study
	Saves.new(db, path).save_run(initial.state, initial.history, initial.meta)
	var studying := Session.new(path)
	studying.load_run()
	studying._saves = Faults.FaultSave.new(db, path)
	studying._saves.fail_replace = true
	var study_before := var_to_bytes([studying.state(), studying.meta()])
	var study_failed: Dictionary = studying.study_mutation(1)
	ok(not study_failed.ok and study_failed.error_code == "SAVE_REPLACE_FAILED" and study_before == var_to_bytes([studying.state(), studying.meta()]), "Failed mutation-study replacement grants neither proof nor permanent discovery")
	var point: Dictionary = report.checkpoints.before_baicao
	Saves.new(db, path).save_run(point.state, point.history, point.meta)
	var session := Session.new(path)
	session.load_run()
	session._saves = Faults.FaultSave.new(db, path)
	session._saves.fail_write = true
	var before := var_to_bytes([session.state(), session.meta()])
	var failed := session.certify_baicao(1)
	ok(not failed.ok and failed.error_code == "SAVE_WRITE_FAILED" and before == var_to_bytes([session.state(), session.meta()]), "Failed Baicao archive save spends neither research nor proof")
	session._saves.fail_write = false
	ok(session.certify_baicao(1).ok, "Failed certification retries successfully once")
	var restored := Session.new(path)
	ok(restored.load_run().ok and restored.meta().unlocked_endings.size() == 3 and restored.meta().material_journal.run_1.size() == 25, "All three endings and material journal survive schema2 round-trip")
	var archive: Dictionary = restored.meta().records[0].duplicate(true)
	ok(restored.claim_inheritance(1, "heritage_baicao").ok and restored.begin_rebirth(1, ["heritage_baicao"]).ok and restored.meta().records[0].optional_endings == archive.optional_endings and restored.meta().material_journal.run_2.size() == 2 and restored.meta().mutation_discoveries.size() == 1, "Rebirth preserves both special archives and mutant discovery, starts fresh material contact")
	# Reconstruct a genuine old-shape schema2 envelope: no retrospective sold-material evidence.
	var old_state: Dictionary = profile.create_run(7).result.state
	var legacy: Dictionary = profile.sync(old_state, profile.empty_meta())
	legacy.erase("material_journal")
	legacy.erase("mutation_discoveries")
	var payload := JSON.stringify({"run": old_state, "meta": legacy, "history": []})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 2, "engine_version": Context.ENGINE_VERSION, "saved_at": "2026-11-19T00:00:00", "payload": payload, "checksum": payload.sha256_text()}))
	file.close()
	var disk := FileAccess.get_file_as_bytes(path)
	var loaded := Saves.new(db, path).load_run()
	ok(loaded.ok and loaded.result.meta.material_journal.run_1 == ["herb_lingcao", "herb_qinghua"] and FileAccess.get_file_as_bytes(path) == disk, "Old schema2 reads existing stock into an in-memory journal without rewriting disk or inventing sold history")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
