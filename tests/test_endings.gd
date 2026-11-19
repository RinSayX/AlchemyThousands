extends RefCounted
const Database := preload("res://scripts/core/content_db.gd")
const Definition := preload("res://scripts/core/ending_trial_definition.gd")
const Service := preload("res://scripts/services/ending_trial_service.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Session := preload("res://scripts/core/game_session.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const OldSaves := preload("res://tests/test_save_load.gd")
const Route := preload("res://tests/helpers/ending_route.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
var db := Database.new()
var profile: RefCounted
var service: RefCounted
var check: Callable
var report: Dictionary

func run(callback: Callable) -> bool:
	check = callback
	if not db.load_directory().ok: return false
	profile = Profile.new(db)
	service = Service.new(db)
	_config()
	_collection()
	report = Route.new().run()
	ok(report.ok, "Public route reaches special ending: " + report.error)
	if not report.ok: return false
	_plans()
	_saves()
	return true

func ok(condition: bool, message: String) -> void:
	check.call(condition, "P8 ending: " + message)

func _config() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Definition.PATH))
	var cases := [["schema_version", true], ["required_rank", 9], ["required_rank", true], ["id", true], ["id", "ending_unknown"], ["name", ""], ["requirements", []], ["study", []], ["script", "free_reward"]]
	for test in cases:
		var changed := original.duplicate(true)
		changed[test[0]] = test[1]
		ok(not Definition.validate(db, changed).ok, "Malformed trial configuration rejected: " + str(test[0]))
	for value in [-1, 0, 1.5, "180", INF]:
		var changed := original.duplicate(true)
		changed.study[0].research_cost = value
		ok(not Definition.validate(db, changed).ok, "Invalid study price rejected: " + str(value))
	var changed := original.duplicate(true)
	changed.requirements[0].recipe_id = "recipe_missing"
	ok(not Definition.validate(db, changed).ok, "Unknown trial recipe rejected")
	changed = original.duplicate(true)
	changed.study[1].recipe_id = changed.study[0].recipe_id
	ok(not Definition.validate(db, changed).ok, "Duplicate study recipe rejected")
	ok(service.startup.ok and service.definition.study[0].research_cost is int, "Valid rule document normalizes integer costs")

func _collection() -> void:
	var run: Dictionary = profile.create_run(1).result.state
	var meta: Dictionary = profile.empty_meta()
	for id in db.get_ids("recipes"):
		for quality in Pills.QUALITIES: meta.discovered_pills.append(Pills.key(id, quality))
	ok(meta.discovered_pills.size() == 100 and profile.validate(run, meta).ok, "Permanent collection accepts all 100 valid recipe-quality discoveries")
	var path := "res://test-output/p8-collection-%d.json" % OS.get_process_id()
	var manager := Saves.new(db, path)
	ok(manager.save_run(run, [], meta).ok and manager.load_run().result.meta.discovered_pills.size() == 100, "Full 100-entry collection survives save verification and reload")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	meta.discovered_pills.append(meta.discovered_pills[0])
	ok(not profile.validate(run, meta).ok, "Collection still rejects duplicates beyond its dynamic limit")

func _reject(run: Dictionary, meta: Dictionary, action: Callable, code: String, text: String) -> void:
	var before := var_to_bytes([run, meta])
	var result: Dictionary = action.call()
	ok(not result.ok and result.error_code == code and before == var_to_bytes([run, meta]), text)

func _plans() -> void:
	var initial: Dictionary = profile.create_run(1).result.state
	var empty: Dictionary = profile.empty_meta()
	_reject(initial, empty, func(): return service.plan_study(initial, empty, 1, "recipe_taichu", "early"), "ENDING_STUDY_LOCKED", "No legendary study before standard completion")
	_reject(initial, empty, func(): return service.plan_certify(initial, empty, 1, "early"), "ENDING_REQUIRED", "No special certification before standard completion")
	var point: Dictionary = report.checkpoints.before_study
	var run: Dictionary = point.state.duplicate(true)
	var meta: Dictionary = point.meta.duplicate(true)
	var before := var_to_bytes([run, meta])
	var a: Dictionary = service.preview(run, meta)
	var b: Dictionary = service.preview_study(run, meta, "recipe_taichu")
	ok(a.ok and b.result.can_execute and before == var_to_bytes([run, meta]), "Ending and study previews are pure")
	_reject(run, meta, func(): return service.plan_study(run, meta, 2, "recipe_taichu", "stale"), "RUN_CHANGED", "Stale life study rejected")
	_reject(run, meta, func(): return service.plan_study(run, meta, 1, "recipe_juling", "wrong"), "UNKNOWN_ENDING_RECIPE", "Study restricted to configured god pills")
	_reject(run, meta, func(): return service.plan_certify(run, meta, 1, "missing"), "INSUFFICIENT_PILLS", "Permanent discoveries do not replace held proof pills")
	var poor := run.duplicate(true)
	poor.research_points = 0
	_reject(poor, meta, func(): return service.plan_study(poor, meta, 1, "recipe_taichu", "poor"), "INSUFFICIENT_RESEARCH", "Insufficient study points cannot consume materials")
	poor = run.duplicate(true)
	poor.inventory.erase("herb_lingzhi")
	_reject(poor, meta, func(): return service.plan_study(poor, meta, 1, "recipe_taichu", "missing"), "INSUFFICIENT_ITEMS", "Missing study items cannot consume research")
	var plan: Dictionary = service.plan_study(run, meta, 1, "recipe_taichu", "study")
	ok(plan.ok and run == point.state and plan.result.state.rng_states == run.rng_states and plan.result.state.research_points == run.research_points - 180 and plan.result.state.research_crafts == run.research_crafts + 1 and plan.result.state.statistics == run.statistics and plan.result.state.pills[Pills.key("recipe_taichu", "legendary")].quantity == 1, "Deterministic study produces one legendary pill, charges exact points and leaves all RNG/furnace statistics untouched")
	_reject(plan.result.state, plan.result.meta, func(): return service.plan_study(plan.result.state, plan.result.meta, 1, "recipe_taichu", "study"), "ACTION_DUPLICATE", "Study action replay rejected")
	poor = run.duplicate(true)
	poor.research_crafts = 2147483647
	_reject(poor, meta, func(): return service.plan_study(poor, meta, 1, "recipe_taichu", "overflow"), "AMOUNT_OVERFLOW", "Study overflow does not consume research, materials or RNG")
	point = report.checkpoints.before_certify
	run = point.state.duplicate(true)
	meta = point.meta.duplicate(true)
	plan = service.plan_certify(run, meta, 1, "certify")
	ok(plan.ok and plan.result.state.ending == run.ending and plan.result.state.rng_states == run.rng_states and plan.result.meta.records[0].ending == meta.records[0].ending and plan.result.meta.records.size() == 1 and plan.result.meta.unlocked_endings == ["ending_grandmaster", "ending_jiuzhuan"], "Certification appends independent archive without changing standard ending, life count or RNG")
	ok(not plan.result.state.pills.has(Pills.key("recipe_taichu", "legendary")) and not plan.result.state.pills.has(Pills.key("recipe_jiuzhuan", "legendary")), "Certification consumes both exact legendary proof pills")
	_reject(plan.result.state, plan.result.meta, func(): return service.plan_certify(plan.result.state, plan.result.meta, 1, "certify"), "ACTION_DUPLICATE", "Certification action replay rejected")
	_reject(plan.result.state, plan.result.meta, func(): return service.plan_certify(plan.result.state, plan.result.meta, 1, "fresh"), "ENDING_ALREADY_CERTIFIED", "New action cannot certify same life twice")
	var invalid: Dictionary = plan.result.meta.duplicate(true)
	invalid.records[0].optional_endings[0].consumed = {"bad": 1}
	ok(not profile.validate(plan.result.state, invalid).ok, "Malformed archive evidence rejected")
	invalid = plan.result.meta.duplicate(true)
	invalid.records[0].optional_endings.append(invalid.records[0].optional_endings[0].duplicate(true))
	ok(not profile.validate(plan.result.state, invalid).ok, "Duplicate optional archives rejected")

func _saves() -> void:
	var path := "res://test-output/p8-ending-%d.json" % OS.get_process_id()
	for key in ["before_study", "before_certify"]:
		var point: Dictionary = report.checkpoints[key]
		Saves.new(db, path).save_run(point.state, point.history, point.meta)
		var session := Session.new(path)
		session.load_run()
		session._saves = OldSaves.FaultSave.new(db, path)
		session._saves.fail_write = true
		var before := var_to_bytes([session.state(), session.meta()])
		var failed: Dictionary = session.study_ending(1, "recipe_taichu") if key == "before_study" else session.certify_ending(1)
		ok(not failed.ok and failed.error_code == "SAVE_WRITE_FAILED" and before == var_to_bytes([session.state(), session.meta()]), "Save failure preserves both halves before swapping: " + key)
		session._saves.fail_write = false
		var retry: Dictionary = session.study_ending(1, "recipe_taichu") if key == "before_study" else session.certify_ending(1)
		ok(retry.ok, "Failed composite transaction can retry once: " + key)
	var point: Dictionary = report.checkpoints.certified
	Saves.new(db, path).save_run(point.state, point.history, point.meta)
	var session := Session.new(path)
	ok(session.load_run().ok and session.meta().unlocked_endings.has("ending_jiuzhuan"), "New optional archive round-trips in schema2")
	var record: Dictionary = session.meta().records[0].optional_endings[0].duplicate(true)
	ok(session.claim_inheritance(1, "heritage_baicao").ok and session.begin_rebirth(1, ["heritage_baicao"]).ok and session.meta().unlocked_endings.has("ending_jiuzhuan") and session.meta().records[0].optional_endings[0] == record and not session.ending_trial().result.completed, "Rebirth retains special archive and resets this-life eligibility")
	_reject(session._state, session._meta, func(): return service.plan_certify(session._state, session._meta, 1, "old-life"), "RUN_CHANGED", "Old confirmation cannot certify a new life")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
