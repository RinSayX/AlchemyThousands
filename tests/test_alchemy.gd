extends RefCounted

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Sequence := preload("res://tests/helpers/sequence_rng.gd")
const Simulation := preload("res://tests/alchemy_probability.gd")

var _check: Callable
var _db: Database
var _service: Alchemy


func run(check: Callable) -> bool:
	_check = check
	_db = Database.new()
	var loaded := _db.load_directory()
	_check.call(loaded.ok, "P3: Content loads with residue definition")
	if not loaded.ok:
		return false
	_service = Alchemy.new(_db)
	_check.call(_test_rules(), "P3: Probability rules group completed")
	_check.call(_test_rng(), "P3: RNG group completed")
	_check.call(_test_execution(), "P3: Settlement group completed")
	_check.call(_test_rejections(), "P3: Atomic rejection group completed")
	_check.call(_test_replay(), "P3: Replay group completed")
	var report := Simulation.new().run()
	_check.call(report.passed and report.total_samples == 500000, "P3: Five representative profiles each simulate 100000 furnaces")
	for profile in report.profiles:
		_check.call(profile.passed, "P3 statistics: " + profile.name)
	return true


func _state(seed_value: int = 1) -> Dictionary:
	return _service.create_state(seed_value).result.state


func _test_rules() -> bool:
	var state := _state()
	var before := var_to_bytes(state)
	var normal: Dictionary = _service.preview_alchemy(state, "recipe_juling").result
	_check.call(is_equal_approx(normal.success_rate, 0.8) and normal.quality_weights == {"common": 65.0, "good": 25.0, "superior": 9.0, "legendary": 1.0}, "P3: Base preview preserves 80 percent and 65/25/9/1")
	_check.call(is_equal_approx(normal.legendary_per_attempt, 0.008) and normal.total_shop_cost == 14, "P3: Preview distinguishes joint legendary chance and material value")
	var stable: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"strategy": "stable"}).result
	var rush: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"strategy": "rush"}).result
	_check.call(is_equal_approx(stable.success_rate, 0.9) and stable.quality_weights.legendary == 0 and stable.quality_weights.common == 66, "P3: Stable strategy moves one legendary weight to common")
	_check.call(is_equal_approx(rush.success_rate, 0.65) and rush.quality_weights.legendary == 6 and rush.quality_weights.common == 60 and is_equal_approx(rush.legendary_per_attempt, 0.039), "P3: Rush trades 15 success points for five legendary weights")
	_check.call(before == var_to_bytes(state), "P3: Repeated previews do not mutate resources, progress or RNG")
	_check.call(not state.needs_save, "P3: Preview does not mark a clean state dirty")
	state.rank = 1
	state.owned_furnaces.append("furnace_qingmu")
	state.owned_furnaces.append("furnace_chiyan")
	state.owned_flames.append("flame_earth")
	var enhanced: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"furnace_id": "furnace_qingmu", "flame_id": "flame_earth", "consumable_id": "consumable_wendan", "strategy": "stable"}).result
	_check.call(is_equal_approx(enhanced.raw_success_rate, 1.15) and enhanced.success_rate == 0.95, "P3: Additive rank/gear/token/strategy bonuses cap at 95 percent")
	var wood: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"furnace_id": "furnace_chiyan"}).result
	_check.call(is_equal_approx(wood.success_rate, 0.82) and wood.quality_weights.superior == 9, "P3: Fire furnace modifiers do not apply to wood recipes")
	state.unlocked_recipes.append("recipe_cuiti")
	var fire: Dictionary = _service.preview_alchemy(state, "recipe_cuiti", {"furnace_id": "furnace_chiyan"}).result
	_check.call(is_equal_approx(fire.success_rate, 0.67) and fire.quality_weights.common == 57 and fire.quality_weights.superior == 17, "P3: Fire tag applies both the penalty and quality transfer")
	var token: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"consumable_id": "consumable_juling"}).result
	_check.call(token.quality_weights.common == 55 and token.quality_weights.good == 30 and token.quality_weights.superior == 14, "P3: Quality token transfers weights without inflating their total")
	var protected: Dictionary = _service.preview_alchemy(state, "recipe_juling", {"consumable_id": "consumable_hulu"}).result
	_check.call(protected.failure_returns == {"herb_lingcao": 1} and protected.material_refund_rate == 0.5, "P3: Failure refunds floor each material count and exclude consumables")
	var weights := {"common": 1.0, "good": 2.0, "superior": 3.0, "legendary": 4.0}
	var moved := Rules.transfer_up(weights, "legendary", 8)
	_check.call(moved == 6 and weights.legendary == 10 and weights.common == 0 and weights.good == 0 and weights.superior == 0, "P3: Transfer shortage uses lower qualities then caps at available weight")
	var extreme := {"common": 65.0, "good": 25.0, "superior": 9.0, "legendary": 1.0}
	_check.call(Rules.transfer_up(extreme, "legendary", 1e308) == 99 and extreme.legendary == 100, "P3: Large finite transfer requests report actual moved weight accurately")
	var low_recipe: Dictionary = _db.get_item("recipe_juling")
	low_recipe.base_success_rate = 0.0
	var low := Rules.calculate(low_recipe, 0, _db.get_item("furnace_basic"), _db.get_item("flame_normal"), {}, "rush")
	_check.call(low.success_rate == 0.05, "P3: Success probability has a five-percent lower bound")
	var capped := Rules.calculate(low_recipe, 10, _db.get_item("furnace_basic"), _db.get_item("flame_normal"), {}, "normal")
	_check.call(is_equal_approx(capped.success_breakdown.rank, 0.10), "P3: Rank familiarity bonus caps at ten points")
	var fail_rng := Sequence.new([0.8])
	_check.call(not Rules.roll(normal, fail_rng).success and fail_rng.calls == 1, "P3: Exact success threshold fails and failure consumes just one draw")
	var quality_rng := Sequence.new([0.0, 0.65])
	_check.call(Rules.roll(normal, quality_rng).quality == "good" and quality_rng.calls == 2, "P3: Quality boundary belongs to the next interval and uses one draw")
	_check.call(Rules.pick_quality(stable.quality_weights, 0.999999) == "superior", "P3: Zero-weight legendary cannot be selected at the upper tail")
	var twins: Dictionary = normal.duplicate(true)
	twins.extra_pill_chance = 1.0
	var twins_rng := Sequence.new([0.1, 0.99, 0.999999])
	var doubled := Rules.roll(twins, twins_rng)
	_check.call(doubled.quantity == 2 and doubled.quality == "legendary" and twins_rng.calls == 3, "P3: Extra pills share the single quality result and consume a later draw")
	twins.extra_pill_chance = 0.5
	_check.call(not Rules.roll(twins, Sequence.new([0, 0, 0.5])).extra_pill, "P3: Extra-pill boundary is half open")
	return true


func _test_rng() -> bool:
	var a := Context.new(9007199254740993)
	var b := Context.new(9007199254740993)
	var identical := true
	for index in range(32):
		identical = identical and a.next_float() == b.next_float()
	_check.call(identical, "P3: Same int64 seed replays the same stream")
	var alchemy_before: Dictionary = a.snapshot().streams.alchemy
	a.next_float("exploration")
	a.next_float("world")
	_check.call(a.snapshot().streams.alchemy == alchemy_before, "P3: Exploration and world streams do not advance alchemy")
	var snapshot: Dictionary = a.snapshot()
	var json_value: Variant = JSON.parse_string(JSON.stringify(snapshot))
	var restored := Context.new(-9)
	_check.call(restored.restore(json_value).ok and restored.snapshot() == snapshot, "P3: Decimal seed/state strings survive JSON without 64-bit rounding")
	var continues := true
	for stream in ["alchemy", "exploration", "world"]:
		for index in range(16):
			continues = continues and a.next_float(stream) == restored.next_float(stream)
	_check.call(continues, "P3: Restoring all streams continues each exact draw sequence")
	for invalid in [null, {}, {"schema_version": true}]:
		var before: Dictionary = restored.snapshot()
		_check.call(not restored.restore(invalid).ok and restored.snapshot() == before, "P3: Malformed RNG restore is atomic")
	for value in ["9223372036854775808", "01", 1.0, true, "not_an_integer"]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.streams.world.state = value
		var before: Dictionary = restored.snapshot()
		_check.call(not restored.restore(bad).ok and restored.snapshot() == before, "P3: Reject lossy or malformed RNG integer %s" % str(value))
	var wrong_engine: Dictionary = snapshot.duplicate(true)
	wrong_engine.engine_version = "4.6"
	_check.call(not restored.restore(wrong_engine).ok, "P3: Cross-engine RNG snapshots are rejected")
	_check.call(not _service.create_state(true).ok, "P3: Boolean seed is rejected")
	return true


func _test_execution() -> bool:
	var state := _state(_seed_for(true))
	var rng_before: Dictionary = state.rng_states.duplicate(true)
	var outcome := _service.execute_alchemy(state, "recipe_juling", {}, "success-1")
	_check.call(outcome.ok and outcome.result.success and outcome.result.quantity == 1 and state.inventory.herb_lingcao == 3 and state.inventory.herb_qinghua == 2, "P3: Successful furnace consumes exact materials and produces one pill")
	_check.call(state.needs_save, "P3: Committed furnace marks progress for a future save coordinator")
	_check.call(state.exp == 10 and state.research_points == 3 and state.action_count == 1 and state.statistics.alchemy_attempts == 1 and state.statistics.alchemy_successes == 1 and state.statistics.alchemy_failures == 0, "P3: Rewards, first-quality discovery, statistics and action count settle together")
	_check.call(state.rng_states.streams.alchemy != rng_before.streams.alchemy and state.rng_states.streams.exploration == rng_before.streams.exploration and state.rng_states.streams.world == rng_before.streams.world, "P3: Execution commits only alchemy RNG advancement")
	_check.call(outcome.result.snapshot == _service.preview_alchemy(_state(_seed_for(true)), "recipe_juling").result and state.spirit_stones == 200, "P3: Execution freezes the same rules as preview and does not charge materials twice")
	outcome.result.snapshot.materials.herb_lingcao = 999
	outcome.state_changes.inventory.after.herb_lingcao = 999
	_check.call(state.inventory.herb_lingcao == 3 and _db.get_item("recipe_juling").materials.herb_lingcao == 2, "P3: Editing result snapshots cannot alter state or content")
	_reject(state, "recipe_juling", {}, "success-1", "ACTION_DUPLICATE", "Repeated furnace action cannot pay twice")
	state.rng_states = Context.new(_seed_for(true)).snapshot() # Fixture guarantees same quality.
	var second := _service.execute_alchemy(state, "recipe_juling", {}, "success-2")
	_check.call(second.ok and second.result.research_gained == 1 and not second.result.new_quality and state.alchemy_discoveries.size() == 1, "P3: Repeated quality earns no repeated discovery bonus")
	var failed := _state(_seed_for(false))
	var failure := _service.execute_alchemy(failed, "recipe_juling", {}, "failure-1")
	_check.call(failure.ok and not failure.result.success and failure.result.quantity == 0 and failed.inventory.material_danzha == 1 and failed.pills.is_empty(), "P3: Gameplay failure commits residue without producing pills")
	_check.call(failed.exp == 3 and failed.research_points == 1 and failed.statistics.alchemy_failures == 1 and failed.action_count == 1, "P3: Failure still earns its disclosed experience and research")
	var sale := Shop.new(_db).sell_item(failed, "material_danzha", 1, "sell-residue")
	_check.call(sale.ok and failed.spirit_stones == 203 and not failed.inventory.has("material_danzha"), "P3: Failure residue is a real stackable sellable item worth three stones")
	var clean := _state()
	_check.call(Shop.new(_db).buy_item(clean, "herb_lingcao", 1, "dirty-purchase").ok and clean.needs_save, "P3: Economic transactions also dirty an extended alchemy state")
	var protected := _state(_seed_for(false))
	protected.inventory["consumable_hulu"] = 1
	var refund := _service.execute_alchemy(protected, "recipe_juling", {"consumable_id": "consumable_hulu"}, "refund")
	_check.call(refund.ok and not refund.result.success and protected.inventory.herb_lingcao == 4 and protected.inventory.herb_qinghua == 2 and not protected.inventory.has("consumable_hulu") and refund.result.returned == {"herb_lingcao": 1}, "P3: Failure protection returns floored materials but spends its token once")
	var legendary := _state(_seed_for(true, true))
	var rare := _service.execute_alchemy(legendary, "recipe_juling", {}, "legendary")
	_check.call(rare.ok and rare.result.quality == "legendary", "P3: Real seeded execution can produce legendary quality")
	var documents := _documents()
	documents.furnaces.items[0].extra_pill_chance = 1
	var twins_db := Database.new()
	_check.call(twins_db.load_documents(documents).ok, "P3: Extra-pill fixture is valid content")
	var twins_service := Alchemy.new(twins_db)
	var twin_state: Dictionary = twins_service.create_state(_seed_for(true)).result.state
	var twins := twins_service.execute_alchemy(twin_state, "recipe_juling", {}, "twins")
	_check.call(twins.ok and twins.result.quantity == 2 and twin_state.pills[Pills.key("recipe_juling", twins.result.quality)].quantity == 2, "P3: Real transaction stacks both same-quality pills")
	return true


func _test_rejections() -> bool:
	var state := _state()
	state.inventory.clear()
	var preview := _service.preview_alchemy(state, "recipe_juling")
	_check.call(preview.ok and not preview.result.can_execute and preview.result.missing_materials == {"herb_lingcao": 2, "herb_qinghua": 1}, "P3: Preview reports shortages without hiding probabilities")
	_reject(state, "recipe_juling", {}, "no-materials", "INSUFFICIENT_MATERIAL", "Material shortage preserves the whole state and RNG")
	state = _state()
	_reject(state, "recipe_juling", {"consumable_id": "consumable_wendan"}, "no-token", "INSUFFICIENT_CONSUMABLE", "Missing selected token cannot consume materials or RNG")
	_reject(state, "recipe_missing", {}, "unknown", "UNKNOWN_RECIPE", "Unknown recipes fail")
	_reject(state, "recipe_cuiti", {}, "locked", "RECIPE_LOCKED", "Locked recipes fail")
	state.unlocked_recipes.append("recipe_cuiti")
	_reject(state, "recipe_cuiti", {}, "rank", "RANK_LOCKED", "Recipe rank is checked separately from ownership")
	_reject(state, "recipe_juling", {"furnace_id": "furnace_qingmu"}, "unowned", "EQUIPMENT_NOT_OWNED", "Unowned equipment cannot grant bonuses")
	for setup in [{"strategy": "cheat"}, {"consumable_id": ["consumable_wendan", "consumable_juling"]}, {"success_bonus": 1}, {"consumable_id": "recipe_juling"}]:
		_reject(state, "recipe_juling", setup, "invalid-setup", "INVALID_SETUP", "Reject invalid setup and injected bonuses")
	state = _state(_seed_for(true))
	for quality in Pills.QUALITIES:
		state.pills[Pills.key("recipe_juling", quality)] = Pills.create("recipe_juling", quality, Economy.MAX_VALUE)
	_reject(state, "recipe_juling", {}, "full-output", "AMOUNT_OVERFLOW", "Output overflow after drawing rolls back RNG as well as resources")
	state = _state(_seed_for(false))
	state.inventory["material_danzha"] = Economy.MAX_VALUE
	_reject(state, "recipe_juling", {}, "full-residue", "AMOUNT_OVERFLOW", "Failure residue overflow also rolls back the full transaction")
	state = _state()
	state.exp = Economy.MAX_VALUE
	_reject(state, "recipe_juling", {}, "full-exp", "AMOUNT_OVERFLOW", "Progress overflow cannot silently lose rewards or RNG")
	state = _state()
	state.rng_states.streams.alchemy.state = 123
	_reject(state, "recipe_juling", {}, "bad-rng", "INVALID_RNG_STATE", "Lossy RNG snapshots cannot execute")
	state = _state()
	state.statistics.alchemy_successes = 1
	_reject(state, "recipe_juling", {}, "bad-stats", "INVALID_STATE", "Inconsistent statistics fail without repair")
	state = _state()
	state.world_modifiers = ["world_unimplemented"]
	_reject(state, "recipe_juling", {}, "unknown-world", "UNSUPPORTED_RULE", "Unimplemented world effects are not silently ignored")
	return true


func _test_replay() -> bool:
	var a := _state(7766)
	a.inventory = {"herb_lingcao": 100, "herb_qinghua": 100}
	var b: Dictionary = a.duplicate(true)
	var same := true
	for index in range(12):
		var setup := {"strategy": ["normal", "stable", "rush"][index % 3]}
		_service.preview_alchemy(b, "recipe_juling", setup)
		var left := _service.execute_alchemy(a, "recipe_juling", setup, "replay-%d" % index)
		var right := _service.execute_alchemy(b, "recipe_juling", setup, "replay-%d" % index)
		same = same and left.ok and left == right and var_to_bytes(a) == var_to_bytes(b)
	_check.call(same, "P3: Same seed/state/actions replay exactly despite extra UI previews")
	var path := "res://test-output/p3-state-%d.bin" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-output"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check.call(file != null, "P3: Temporary state checkpoint opens")
	if file == null:
		return false
	file.store_buffer(var_to_bytes(a))
	file.close()
	var restored: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check.call(_service.validate_state(restored).ok and var_to_bytes(a) == var_to_bytes(restored), "P3: File checkpoint preserves integer state and all RNG snapshots")
	var left := _service.execute_alchemy(a, "recipe_juling", {}, "after-restore")
	var right := _service.execute_alchemy(restored, "recipe_juling", {}, "after-restore")
	_check.call(left.ok and left == right and var_to_bytes(a) == var_to_bytes(restored), "P3: Restored checkpoint continues the same actual furnace result")
	_reject(restored, "recipe_juling", {}, "after-restore", "ACTION_DUPLICATE", "Restored action history prevents re-awarding a furnace")
	return true


func _seed_for(success: bool, legendary: bool = false) -> int:
	for seed_value in range(1, 10000):
		var rng := Context.new(seed_value)
		var passed: bool = rng.next_float() < 0.8
		if passed == success and (not legendary or rng.next_float() >= 0.99):
			return seed_value
	assert(false, "Seed search failed")
	return 1


func _documents() -> Dictionary:
	var documents: Dictionary = {}
	for category in ["recipes", "materials", "furnaces", "flames", "consumables", "quests", "exploration_events"]:
		documents[category] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + category + ".json"))
	return documents


func _reject(state: Dictionary, recipe: String, setup: Dictionary, id: String, code: String, label: String) -> void:
	var before := var_to_bytes(state)
	var result := _service.execute_alchemy(state, recipe, setup, id)
	var correct: bool = not result.ok and result.error_code == code and result.state_changes.is_empty() and before == var_to_bytes(state)
	_check.call(correct, "P3 rejects atomically: " + label)
	if not correct:
		printerr("Expected %s, got %s" % [code, result])
