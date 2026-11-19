extends RefCounted
const Candidates := preload("res://tools/balance/candidate_experiment.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tools/balance/campaign_route.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Growth := preload("res://scripts/services/progression_service.gd")
const Database := preload("res://scripts/core/content_db.gd")
var _check: Callable


func run(check: Callable) -> bool:
	_check = check
	var base_docs := Candidates.documents("baseline")
	var frozen := base_docs.duplicate(true)
	var base: RefCounted = Candidates.database("baseline")
	var combined: RefCounted = Candidates.database("combined")
	_ok(base != null and combined != null and Candidates.database("invalid") == null, "Frozen baseline and candidates validate, unknown variants are rejected")
	_ok(base.get_item("furnace_chiyan").success_bonus == -0.03 and base.get_item("talent_rush_9").success_bonus == -0.05, "Archived original parameters remain independently reproducible")
	for variant in Candidates.VARIANTS:
		var docs := Candidates.documents(variant)
		var changed: Array[String] = []
		for category in base_docs:
			for i in range(base_docs[category].items.size()):
				var a: Dictionary = base_docs[category].items[i]
				var b: Dictionary = docs[category].items[i]
				if a != b:
					changed.append(a.id)
					var restored := b.duplicate(true)
					restored.success_bonus = a.success_bonus
					restored.description = a.description
					_ok(restored == a, variant + " modifies only disclosed success and description fields on " + a.id)
		var expected := 0 if variant == "baseline" else 4 if variant == "combined" else 3 if variant == "talent_only" else 1
		_ok(changed.size() == expected, variant + " changes exactly the planned entries")
	_ok(base_docs == frozen, "Candidate construction cannot mutate the baseline documents")
	var panel := preload("res://scripts/ui/resource_hub.gd").new()
	var text: String = panel._talent_text(combined.get_item("talent_rush_3"))
	_ok(text.contains("不额外降低成功率") and text.contains("冲品策略自身的风险仍然保留") and text.contains("3"), "Talent card explains the new three-point quality reward and retained strategy risk")
	panel.free()
	for milestone in [3, 6, 9]:
		var state := Probe.fixture(combined, milestone + 1, "rush", [], [])
		state.talent_choices.erase("talent_rush_%d" % milestone)
		state.pending_talent_rank = milestone
		var service := Alchemy.new(combined)
		var before: Dictionary = service.preview_alchemy(state, "recipe_zhuji", {"strategy": "rush"}).result
		var chosen := Growth.new(combined).choose_talent(state, "talent_rush_%d" % milestone, "choose-%d" % milestone)
		var after: Dictionary = service.preview_alchemy(state, "recipe_zhuji", {"strategy": "rush"}).result
		_ok(chosen.ok and is_equal_approx(before.raw_success_rate, after.raw_success_rate) and after.quality_weights.legendary > before.quality_weights.legendary, "Actual milestone %d choice improves quality without adding a success penalty" % milestone)
	var low := Probe.fixture(combined, 3, "recycle", [], [])
	var before := low.duplicate(true)
	var low_advice := Probe.refund_advice(combined, low, "recipe_zhuji", Probe.setup(combined, low, "recipe_zhuji", "recycle"))
	_ok(low_advice.ok and not low_advice.recommended and is_equal_approx(low_advice.expected_net_delta, -9.62), "Adaptive jade rejects negative marginal value with per-material refund floors")
	_ok(low == before, "Advice never spends items, changes state or advances any RNG")
	var high := Probe.fixture(combined, 7, "recycle", [], [])
	var high_advice := Probe.refund_advice(combined, high, "recipe_xuanyuan", Probe.setup(combined, high, "recipe_xuanyuan", "recycle"))
	_ok(high_advice.recommended and is_equal_approx(high_advice.expected_net_delta, 4.1), "Adaptive jade selects positive marginal value at the relevant expensive recipe")
	_ok(Probe.setup(combined, low, "recipe_zhuji", "recycle_smart").consumable_id == "" and Probe.setup(combined, high, "recipe_xuanyuan", "recycle_smart").consumable_id == "consumable_hulu", "Smart policy uses production previews to choose one or zero consumables")
	var tie_docs := Candidates.documents("combined")
	for item in tie_docs.recipes.items:
		if item.id == "recipe_ningshen": item.base_success_rate = 0.5
	for item in tie_docs.consumables.items:
		if item.id == "consumable_hulu": item.unlock.price = 5
	var tie_db := Database.new()
	tie_db.load_documents(tie_docs)
	var tie := Probe.fixture(tie_db, 2, "recycle", [], [])
	# .5 failure * one extra returned ningshen herb valued10 = jade price5.
	var exact := Probe.refund_advice(tie_db, tie, "recipe_ningshen", {"strategy": "normal", "furnace_id": "furnace_basic", "flame_id": "flame_normal"})
	_ok(exact.ok and exact.available and exact.expected_net_delta == 0 and not exact.recommended, "Zero marginal gain never causes a speculative jade purchase")
	var smart_route := Route.new(combined)
	var smart := smart_route.run(73001, "recycle_smart", [], [], 3)
	_ok(smart.status == "completed" and smart.cash_reconciles and smart_route.state.talent_choices == ["talent_stable_3"], "Smart recovery completes real transactions and selects stable talents")
	_save_compatibility(base, combined)
	var live := Database.new()
	var loaded := live.load_directory()
	var matches: bool = loaded.ok
	for category in base_docs:
		for item in combined.get_items(category):
			matches = matches and _equivalent(live.get_item(item.id), item)
	_ok(matches, "All pre-expansion live definitions retain the validated combined tuning")
	return true


func _save_compatibility(old_db: RefCounted, next_db: RefCounted) -> void:
	var state := Probe.fixture(old_db, 5, "rush", [], [])
	for id in old_db.get_item("recipe_pojing").materials: state.inventory[id] = 20
	var old := Alchemy.new(old_db)
	var receipt := old.execute_alchemy(state, "recipe_pojing", {"strategy": "rush", "furnace_id": "furnace_chiyan", "flame_id": "flame_earth"}, "old-furnace")
	_ok(receipt.ok, "Old rule furnace actually settles before constructing an upgrade checkpoint")
	var path := "res://test-output/p8-tuning-old-%d.json" % OS.get_process_id()
	var profiles := Profile.new(old_db)
	var meta: Dictionary = profiles.sync(state, profiles.empty_meta())
	var saved := Saves.new(old_db, path).save_run(state, [receipt.result], meta)
	var loaded := Saves.new(next_db, path).load_run()
	_ok(saved.ok and loaded.ok and loaded.result.state.talent_choices == state.talent_choices and loaded.result.state.rng_states == state.rng_states, "Numeric update reads old schema2 progress, talent IDs and exact RNG without migration or reroll")
	if loaded.ok:
		_ok(_equivalent(loaded.result.history[0].snapshot, receipt.result.snapshot) and loaded.result.history[0].quality == receipt.result.quality and loaded.result.history[0].quantity == receipt.result.quantity, "Recorded old furnace preserves frozen probabilities at JSON precision and its exact awarded result")
		var next: Dictionary = Alchemy.new(next_db).preview_alchemy(loaded.result.state, "recipe_pojing", {"strategy": "rush", "furnace_id": "furnace_chiyan", "flame_id": "flame_earth"})
		_ok(next.ok and is_equal_approx(next.result.success_rate - receipt.result.snapshot.success_rate, 0.09), "Only future furnaces use the newly loaded equipment and talent rules")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _ok(condition: bool, message: String) -> void:
	_check.call(condition, "P8 tuning: " + message)


func _equivalent(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _equivalent(a[i], b[i]): return false
		return true
	if a is int and b is int: return a == b
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	return a == b
