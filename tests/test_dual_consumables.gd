extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const OldRules := preload("res://tests/fixtures/p8_single_rules.gd")
const Loadout := preload("res://scripts/core/consumable_loadout.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
var db := Database.new()
var check: Callable
var service: RefCounted

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	service = Alchemy.new(db)
	_inputs()
	_legacy()
	_settlement()
	_shop_save()
	return true

func ok(value: bool, message: String) -> void:
	check.call(value, "P8 dual: " + message)

func fixture(worlds: Array = []) -> Dictionary:
	var state := Probe.fixture(db, 10, "rush", [], worlds)
	state.owned_furnaces = db.get_ids("furnaces")
	state.owned_flames = db.get_ids("flames")
	for id in db.get_ids("materials") + db.get_ids("consumables"): state.inventory[id] = 100
	return state

func pair(ids: Array = ["consumable_wendan", "consumable_yanjiu"]) -> Dictionary:
	return {"strategy": "normal", "consumable_ids": ids}

func _reject(state: Dictionary, setup: Dictionary, code: String) -> bool:
	var frozen := var_to_bytes(state)
	var receipt: Dictionary = service.execute_alchemy(state, "recipe_juling", setup, "rejected")
	return not receipt.ok and receipt.error_code == code and frozen == var_to_bytes(state)

func _inputs() -> void:
	var state := fixture()
	for invalid in [null, "consumable_wendan", {}, [""], [1], [true], ["recipe_juling"], ["consumable_wendan", "consumable_yanjiu", "consumable_juling"], ["consumable_wendan", "consumable_wendan"], ["consumable_wendan", "consumable_wenhuo"], ["consumable_juling", "consumable_jiuzhuan"], ["consumable_hulu", "consumable_bingpo"]]:
		ok(_reject(state, {"consumable_ids": invalid}, "INVALID_SETUP"), "Reject invalid selection atomically: " + str(invalid))
	ok(_reject(state, {"consumable_ids": [], "consumable_id": ""}, "INVALID_SETUP"), "Reject mixed legacy and list fields even when empty")
	var frozen := var_to_bytes(state)
	var preview: Dictionary = service.preview_alchemy(state, "recipe_juling", pair()).result
	ok(var_to_bytes(state) == frozen and preview.can_execute and preview.consumable_shop_cost == 30 and preview.consumables.size() == 2 and preview.research_rewards.base == 3, "Preview is pure and exposes both items, aggregate price and research")
	ok(service.preview_alchemy(state, "recipe_juling", pair(["consumable_yanjiu", "consumable_wendan"])).result == preview, "Swapping slots produces the same canonical snapshot")
	state.inventory.erase("consumable_yanjiu")
	var missing: Dictionary = service.preview_alchemy(state, "recipe_juling", pair()).result
	ok(not missing.can_execute and missing.missing_consumables == {"consumable_yanjiu": 1} and _reject(state, pair(), "INSUFFICIENT_CONSUMABLE"), "Missing second item never spends the first item or RNG")
	var valid_pairs := 0
	var symmetric := true
	var ids: Array = db.get_ids("consumables")
	state = fixture()
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			if db.get_item(ids[a]).effect_category == db.get_item(ids[b]).effect_category: continue
			valid_pairs += 1
			for recipe in db.get_ids("recipes"):
				for strategy in ["normal", "stable", "rush"]:
					var setup := {"strategy": strategy, "consumable_ids": [ids[a], ids[b]]}
					var first: Dictionary = service.preview_alchemy(state, recipe, setup)
					setup.consumable_ids.reverse()
					var second: Dictionary = service.preview_alchemy(state, recipe, setup)
					symmetric = symmetric and first.ok and first == second
	ok(valid_pairs == 25 and symmetric, "All 25 valid pairs across 25 recipes and 3 strategies have slot-independent previews")

func _legacy() -> void:
	var state := fixture()
	var unchanged := true
	for id in [""] + db.get_ids("consumables"):
		for strategy in ["normal", "stable", "rush"]:
			var setup := {"consumable_id": id, "strategy": strategy}
			var view: Dictionary = service.preview_alchemy(state, "recipe_juling", setup).result
			var item: Dictionary = {} if id.is_empty() else db.get_item(id)
			var old := OldRules.calculate(db.get_item("recipe_juling"), state.rank, db.get_item(state.equipped_furnace), db.get_item(state.equipped_flame), item, strategy, preload("res://scripts/core/talent_rules.gd").definitions(db, state))
			for field in old: unchanged = unchanged and old[field] == view[field]
			var a := Context.new(618)
			var b := Context.new(618)
			for i in range(32): unchanged = unchanged and Rules.roll(view, a) == OldRules.roll(old, b) and a.snapshot() == b.snapshot()
			var list_setup := {"strategy": strategy, "consumable_ids": [] if id.is_empty() else [id]}
			var list_view: Dictionary = service.preview_alchemy(state, "recipe_juling", list_setup).result
			list_view.setup = view.setup.duplicate(true)
			unchanged = unchanged and list_view == view
	ok(unchanged, "Frozen 8ca605b single-item math and 864 outcomes/RNG snapshots remain unchanged; empty/single lists are equivalent")

func _settlement() -> void:
	for success in [true, false]:
		var state := fixture()
		var setup := pair(["consumable_hulu", "consumable_yanjiu"])
		var view: Dictionary = service.preview_alchemy(state, "recipe_juling", setup).result
		var seed_value := 1
		while Rules.roll(view, Context.new(seed_value)).success != success: seed_value += 1
		state.rng_states = Context.new(seed_value).snapshot()
		var original := state.duplicate(true)
		var receipt: Dictionary = service.execute_alchemy(state, "recipe_juling", setup, "dual")
		ok(receipt.ok and receipt.result.success == success and state.inventory.consumable_hulu == 99 and state.inventory.consumable_yanjiu == 99 and receipt.result.research_gained >= 3 and state.action_count == original.action_count + 1 and state.statistics.alchemy_attempts == original.statistics.alchemy_attempts + 1, "Both items spend exactly once with one settlement on success=" + str(success))
		if not success: ok(receipt.result.returned == {"herb_lingcao": 1} and receipt.result.residue == 1, "Failure refund floors each material; consumables never return")
		var mirrored := original.duplicate(true)
		ok(service.execute_alchemy(mirrored, "recipe_juling", setup, "dual") == receipt and mirrored == state and state.rng_states.streams.world == original.rng_states.streams.world and state.rng_states.streams.exploration == original.rng_states.streams.exploration, "Complete dual transaction replays; other RNG streams remain isolated")
		var frozen := var_to_bytes(state)
		ok(service.execute_alchemy(state, "recipe_juling", setup, "dual").error_code == "ACTION_DUPLICATE" and frozen == var_to_bytes(state), "Repeated action cannot charge either item twice")
	var inactive := fixture()
	var receipt: Dictionary = service.execute_alchemy(inactive, "recipe_juling", pair(["consumable_bingpo", "consumable_wenhuo"]), "inactive")
	ok(receipt.ok and receipt.result.snapshot.material_refund_rate == 0 and receipt.result.snapshot.success_breakdown.consumable == 0 and inactive.inventory.consumable_bingpo == 99 and inactive.inventory.consumable_wenhuo == 99, "Inactive tag/strategy effects still spend their selected items")
	var overflow := fixture()
	overflow.research_points = 2147483647
	ok(_reject(overflow, pair(), "AMOUNT_OVERFLOW"), "Late research overflow rolls back both costs and RNG")
	var capped: Dictionary = service.preview_alchemy(fixture(), "recipe_bingxin", {"furnace_id": "furnace_xuanbing", "flame_id": "flame_hansui", "consumable_ids": ["consumable_bingpo", "consumable_yanjiu"]}).result
	ok(capped.material_refund_rate == 1.0, "Equipment plus one refund consumable clamps at 100 percent")
	var mutated := fixture()
	var setup := {"strategy": "rush", "furnace_id": "furnace_jiulong", "flame_id": "flame_zixiao", "consumable_ids": ["consumable_shuangsheng", "consumable_jiuzhuan"], "mutation_id": Pills.MUTATION_ID}
	var view: Dictionary = service.preview_alchemy(mutated, Pills.MUTATION_RECIPE, setup).result
	var seed_value := 1
	while true:
		var roll := Rules.roll(view, Context.new(seed_value))
		if roll.mutation_id == Pills.MUTATION_ID and roll.extra_pill: break
		seed_value += 1
	mutated.rng_states = Context.new(seed_value).snapshot()
	receipt = service.execute_alchemy(mutated, Pills.MUTATION_RECIPE, setup, "mutated-dual")
	ok(receipt.ok and receipt.result.quantity == 2 and receipt.result.mutation_id == Pills.MUTATION_ID and is_equal_approx(view.extra_pill_chance, 0.45) and mutated.pills[Pills.key(Pills.MUTATION_RECIPE, receipt.result.quality, Pills.MUTATION_ID)].quantity == 2, "Dual consumables combine with independent mutation and one shared-quality extra-pill roll")

func _shop_save() -> void:
	var session := Session.new()
	session.new_run(618)
	var setup := pair(["consumable_wendan", "consumable_juling"])
	var before := var_to_bytes([session.state(), session.meta()])
	ok(session.quote_consumables(setup).result.total == 16 and before == var_to_bytes([session.state(), session.meta()]), "Two-item purchase quote is pure")
	var stones: int = session.state().spirit_stones
	ok(session.buy_consumables(setup).ok and session.state().spirit_stones == stones - 16 and session.state().inventory.consumable_wendan == 1 and session.state().inventory.consumable_juling == 1, "Public purchase buys both items in one transaction")
	before = var_to_bytes([session.state(), session.meta()])
	ok(not session.buy_consumables(pair(["consumable_wendan", "consumable_yanjiu"])).ok and before == var_to_bytes([session.state(), session.meta()]), "Rank-locked second item rejects the whole cart")
	var state := fixture()
	state.spirit_stones = 15
	var profile := Profile.new(db)
	var meta: Dictionary = profile.sync(state, profile.empty_meta())
	var path := "res://test-output/p8-dual-%d.json" % OS.get_process_id()
	var saver := Saves.new(db, path)
	var prepared: Dictionary = saver.save_run(state, [], meta)
	ok(prepared.ok, "Purchase failure fixture is a valid persisted rank-nine run")
	if not prepared.ok: return
	var poor := Session.new(path)
	poor.load_run()
	before = var_to_bytes([poor.state(), poor.meta()])
	ok(not poor.buy_consumables(setup).ok and before == var_to_bytes([poor.state(), poor.meta()]), "Insufficient combined funds never partially buy either item")
	state.spirit_stones = 100
	var receipt: Dictionary = service.execute_alchemy(state, "recipe_juling", setup, "saved-dual")
	meta = profile.sync(state, meta)
	var saved: Dictionary = saver.save_run(state, [receipt.result], meta)
	ok(saved.ok, "Schema2 stores dual receipt without adding required state fields")
	if not saved.ok: return
	var loaded: Dictionary = saver.load_run()
	var first := state.duplicate(true)
	first.needs_save = false
	var second: Dictionary = loaded.result.state
	ok(loaded.ok and service.execute_alchemy(first, "recipe_juling", setup, "continued") == service.execute_alchemy(second, "recipe_juling", setup, "continued") and first == second, "Actual save/reload continues dual brewing identically")
	var bad: Dictionary = receipt.result.duplicate(true)
	bad.snapshot.setup.consumable_ids = ["consumable_wendan", "consumable_wenhuo"]
	ok(not saver.save_run(state, [bad], meta).ok, "Invalid dual history is rejected before replacing the good file")
	bad = receipt.result.duplicate(true)
	bad.consumed.erase("consumable_juling")
	ok(not saver.save_run(state, [bad], meta).ok, "History must retain both actually consumed items")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
