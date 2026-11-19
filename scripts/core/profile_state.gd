class_name ProfileState
extends RefCounted
## Logical permanent/current-run split. All getters/plans are detached values.
const Run := preload("res://scripts/core/progression_state.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Talents := preload("res://scripts/core/talent_rules.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const Baicao := preload("res://scripts/core/baicao_definition.gd")
const EndingTrial := preload("res://scripts/core/ending_trial_definition.gd")
var db: RefCounted
var runs: Run


func _init(content: RefCounted) -> void:
	db = content
	runs = Run.new(content)


func empty_meta() -> Dictionary:
	return {"highest_completed_run": 0, "discovered_pills": [], "unlocked_endings": [], "achievements": [], "best_records": {}, "records": [], "unlocked_inheritances": [], "heritage_slots": 1, "legacy_insight": 0, "tutorial_completed": false, "quality_of_life_unlocks": []}


func create_run(seed_value: int, number: int = 1, loadout: Array = [], worlds: Array = [], insight: int = 0) -> Dictionary:
	var created := runs.create_state(seed_value)
	if created.ok:
		var state: Dictionary = created.result.state
		state.merge({"run_number": number, "run_id": "run_%d" % number, "run_seed": str(seed_value), "equipped_inheritances": loadout.duplicate(), "world_modifiers": worlds.duplicate(), "heritage_reward": ""})
		state.resource_stats["heritage_supplies"] = 0
		state.research_points = mini(insight, 10)
		state.needs_save = true
	return created


func upgrade(state: Dictionary, meta: Variant = null) -> Dictionary:
	var run := state.duplicate(true)
	var valid_run := runs.validate(run)
	if not valid_run.ok:
		return valid_run
	if not run.has("run_number"):
		var checked := runs.validate(run)
		if not checked.ok:
			return checked
		var seed_value: int = run.rng_states.streams.alchemy.seed.to_int() ^ Context.SALTS.alchemy
		run.merge({"run_number": 1, "run_id": "run_1", "run_seed": str(seed_value), "equipped_inheritances": [], "world_modifiers": [], "heritage_reward": ""})
		run.resource_stats["heritage_supplies"] = 0
	if meta == null:
		if not Economy.valid_integer(run.get("run_number"), 1) or run.run_number != 1 or not run.get("heritage_reward") is String or run.heritage_reward != "":
			return Result.failure("META_REQUIRED", "后续周目或已领奖修行必须连同永久记录保存。")
		for field in ["run_id", "run_seed", "equipped_inheritances", "world_modifiers"]:
			if not run.has(field):
				return Result.failure("INVALID_PROFILE", "周目字段缺失。")
		if not run.run_id is String or not run.run_seed is String or not run.equipped_inheritances is Array or not run.world_modifiers is Array:
			return Result.failure("INVALID_PROFILE", "周目字段类型不合法。")
		meta = sync(run, empty_meta())
	var checked := validate(run, meta)
	if not checked.ok:
		return checked
	return Result.success({}, {"state": run, "meta": sync(run, meta)})


func sync(run: Dictionary, source: Dictionary) -> Dictionary:
	var meta := source.duplicate(true)
	var journal: Dictionary = meta.get("material_journal", {}).duplicate(true)
	var seen: Array = journal.get(run.run_id, []).duplicate()
	for id in run.inventory:
		if id in db.get_ids("materials") and run.inventory[id] > 0 and id not in seen: seen.append(id)
	journal[run.run_id] = seen
	meta["material_journal"] = journal
	var mutations: Array = meta.get("mutation_discoveries", []).duplicate()
	for key in run.pills:
		if run.pills[key].get("mutation_id", "") == Pills.MUTATION_ID and key not in mutations: mutations.append(key)
	meta["mutation_discoveries"] = mutations
	for key in run.alchemy_discoveries:
		if key not in meta.discovered_pills:
			meta.discovered_pills.append(key)
	if not run.ending.is_empty():
		var exists := false
		for record in meta.records:
			if record.run_number == run.run_number:
				exists = true
		if not exists:
			meta.records.append({"run_number": run.run_number, "run_id": run.run_id, "seed": run.run_seed, "ending": run.ending.duplicate(true), "world_modifiers": run.world_modifiers.duplicate(), "equipped_inheritances": run.equipped_inheritances.duplicate(), "talents": run.talent_choices.duplicate(), "reward": "", "next_run": 0})
	var count: int = meta.records.size()
	meta.highest_completed_run = count
	meta.heritage_slots = 2 if count >= 2 else 1
	meta.tutorial_completed = count > 0
	meta.unlocked_endings = ["ending_grandmaster"] if count > 0 else []
	for record in meta.records:
		for ending in record.get("optional_endings", []):
			if ending.id not in meta.unlocked_endings: meta.unlocked_endings.append(ending.id)
	meta.quality_of_life_unlocks = ["skip_prologue", "quick_reveal"] if count > 0 else []
	meta.achievements = []
	if count > 0: meta.achievements.append("first_ending")
	if count >= 2: meta.achievements.append("two_endings")
	if EndingTrial.ID in meta.unlocked_endings: meta.achievements.append("jiuzhuan_saint")
	if Baicao.ID in meta.unlocked_endings: meta.achievements.append("baicao_ancestor")
	if meta.unlocked_inheritances.size() == db.get_ids("inheritances").size(): meta.achievements.append("all_inheritances")
	meta.best_records = {}
	for record in meta.records:
		for pair in [["fewest_actions", "action_count"], ["fewest_furnaces", "alchemy_attempts"]]:
			meta.best_records[pair[0]] = mini(meta.best_records.get(pair[0], Economy.MAX_VALUE), record.ending[pair[1]])
	return meta


func validate(run: Dictionary, value: Variant) -> Dictionary:
	var checked := runs.validate(run)
	if not checked.ok:
		return checked
	for field in ["run_number", "run_id", "run_seed", "equipped_inheritances", "world_modifiers", "heritage_reward"]:
		if not run.has(field):
			return Result.failure("INVALID_PROFILE", "缺少周目字段：" + field)
	if not Economy.valid_integer(run.run_number, 1) or not run.run_id is String or run.run_id != "run_%d" % run.run_number or not _seed(run.run_seed) or not run.heritage_reward is String:
		return Result.failure("INVALID_PROFILE", "周目标识、种子或传承选择不合法。")
	if not run.equipped_inheritances is Array:
		return Result.failure("INVALID_PROFILE", "携带传承列表不合法。")
	if (run.run_number == 1 and not run.equipped_inheritances.is_empty()) or (run.run_number == 2 and run.equipped_inheritances.size() > 1):
		return Result.failure("INVALID_PROFILE", "本世开局时尚未解锁这些携带栏位。")
	if not _worlds(run.world_modifiers, run.run_number) or not _ids(run.equipped_inheritances, db.get_ids("inheritances"), 2) or not Economy.valid_integer(run.resource_stats.get("heritage_supplies"), 0, 1):
		return Result.failure("INVALID_PROFILE", "本世传承、世界规则或补给计数不合法。")
	if not value is Dictionary or value.size() != empty_meta().size() + (1 if value.has("material_journal") else 0) + (1 if value.has("mutation_discoveries") else 0):
		return Result.failure("INVALID_META", "永久记录结构不完整。")
	for field in empty_meta():
		if not value.has(field):
			return Result.failure("INVALID_META", "缺少永久字段：" + field)
	var meta: Dictionary = value
	if not meta.records is Array or not Economy.valid_integer(meta.highest_completed_run, 0) or not Economy.valid_integer(meta.legacy_insight, 0) or not meta.tutorial_completed is bool or not Economy.valid_integer(meta.heritage_slots, 1, 2) or not meta.best_records is Dictionary:
		return Result.failure("INVALID_META", "历史统计与传承栏不合法。")
	var pill_ids: Array[String] = []
	for id in db.get_ids("recipes"):
		for quality in Pills.QUALITIES:
			pill_ids.append(Pills.key(id, quality))
	for pair in [["discovered_pills", pill_ids, pill_ids.size()], ["unlocked_inheritances", db.get_ids("inheritances"), 9], ["unlocked_endings", ["ending_grandmaster", EndingTrial.ID, Baicao.ID], 3], ["achievements", ["first_ending", "two_endings", "all_inheritances", "jiuzhuan_saint", "baicao_ancestor"], 5], ["quality_of_life_unlocks", ["skip_prologue", "quick_reveal"], 2]]:
		if not _ids(meta[pair[0]], pair[1], pair[2]):
			return Result.failure("INVALID_META", "永久引用或重复条目不合法：" + pair[0])
	if not _journal_valid(run, meta): return Result.failure("INVALID_META", "材料日志或变异图鉴不合法。")
	if run.equipped_inheritances.size() > meta.heritage_slots:
		return Result.failure("INVALID_PROFILE", "携带传承超出永久栏位。")
	for id in run.equipped_inheritances:
		if id not in meta.unlocked_inheritances:
			return Result.failure("INVALID_PROFILE", "不能携带尚未解锁的传承。")
	for key in run.alchemy_discoveries:
		if key not in meta.discovered_pills:
			return Result.failure("INVALID_META", "本世发现尚未归入永久图鉴。")
	var count: int = meta.records.size()
	if run.run_number != count + (1 if run.ending.is_empty() else 0) or meta.highest_completed_run != count:
		return Result.failure("INVALID_META", "当前周目与历史结局序列不一致。")
	var rewards: Array = []
	var fallback := 0
	for i in range(count):
		var record: Variant = meta.records[i]
		if not record is Dictionary or record.size() != (10 if record.has("optional_endings") else 9) or not Economy.valid_integer(record.get("run_number"), 1) or record.run_number != i + 1 or not record.get("run_id") is String or record.run_id != "run_%d" % (i + 1) or not _seed(record.get("seed")) or not _ending(record.get("ending")) or not _worlds(record.get("world_modifiers"), i + 1) or not _ids(record.get("equipped_inheritances"), db.get_ids("inheritances"), 2) or not record.get("reward") is String or not Economy.valid_integer(record.get("next_run"), 0):
			return Result.failure("INVALID_META", "历史周目记录不合法。")
		if not _optional_endings(record, run):
			return Result.failure("INVALID_META", "特殊结局归档不合法。")
		if not record.get("talents") is Array or record.talents.size() != 3 or not Talents.valid_choices(db, {"rank": 10, "talent_choices": record.talents}):
			return Result.failure("INVALID_META", "历史天赋记录不合法。")
		if record.run_number < run.run_number and (record.next_run != record.run_number + 1 or record.reward.is_empty()):
			return Result.failure("INVALID_META", "历史轮回缺少已提交标记或奖励。")
		if record.run_number == run.run_number and (record.next_run != 0 or record.reward != run.heritage_reward or record.ending != run.ending or record.seed != run.run_seed or record.world_modifiers != run.world_modifiers or record.equipped_inheritances != run.equipped_inheritances or record.talents != run.talent_choices):
			return Result.failure("INVALID_META", "当前结局与历史快照不一致。")
		if record.equipped_inheritances.size() > (0 if i == 0 else 1 if i == 1 else 2):
			return Result.failure("INVALID_META", "历史开局携带栏位不合法。")
		for id in record.equipped_inheritances:
			if id not in rewards:
				return Result.failure("INVALID_META", "历史开局携带了当时尚未解锁的传承。")
		if record.reward == "legacy_insight":
			if rewards.size() != db.get_ids("inheritances").size():
				return Result.failure("INVALID_META", "仍有未解锁传承时不能提前领取替代奖励。")
			fallback += 1
		elif not record.reward.is_empty():
			if record.reward not in db.get_ids("inheritances") or record.reward in rewards:
				return Result.failure("INVALID_META", "传承解锁奖励重复或不存在。")
			rewards.append(record.reward)
	if fallback != meta.legacy_insight or rewards.size() != meta.unlocked_inheritances.size():
		return Result.failure("INVALID_META", "永久奖励与历史结算不一致。")
	for id in rewards:
		if id not in meta.unlocked_inheritances:
			return Result.failure("INVALID_META", "历史奖励尚未解锁。")
	if run.ending.is_empty() and not run.heritage_reward.is_empty():
		return Result.failure("INVALID_PROFILE", "未完成结局不能领取传承。")
	var expected := sync(run, meta)
	for field in ["heritage_slots", "tutorial_completed", "unlocked_endings", "achievements", "best_records", "quality_of_life_unlocks"]:
		if meta[field] != expected[field]:
			return Result.failure("INVALID_META", "永久成就或最佳纪录不一致：" + field)
	return Result.success()


func _worlds(value: Variant, number: int) -> bool:
	if not _ids(value, db.get_ids("world_modifiers"), 2):
		return false
	if number == 1:
		return value.is_empty()
	if value.size() != 2:
		return false
	var opportunity := false
	for id in value:
		var item: Dictionary = db.get_item(id)
		if item.min_run_number > number:
			return false
		opportunity = opportunity or item.opportunity
		for other in value:
			if other in item.exclusive_with:
				return false
	return opportunity


func _ending(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 6 or not value.get("id") is String or value.id != "ending_grandmaster":
		return false
	for field in ["action_count", "alchemy_attempts", "research_crafts", "quests_completed", "exp"]:
		if not Economy.valid_integer(value.get(field), 0): return false
	return true


func _optional_endings(record: Dictionary, run: Dictionary) -> bool:
	var entries: Variant = record.get("optional_endings", [])
	if not entries is Array or entries.size() > 2: return false
	var seen: Array = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("id") is String or entry.id not in [EndingTrial.ID, Baicao.ID] or entry.id in seen or not entry.get("consumed") is Dictionary: return false
		seen.append(entry.id)
		var baicao: bool = entry.id == Baicao.ID
		if entry.size() != (8 if baicao else 7) or entry.consumed.size() != (1 if baicao else 2): return false
		if baicao:
			var evidence: Variant = entry.get("evidence")
			if not evidence is Dictionary or evidence.size() != 2 or not _ids(evidence.get("materials"), db.get_ids("materials"), db.get_ids("materials").size()) or evidence.materials.size() < 25 or not Economy.valid_integer(evidence.get("research_cost"), 1, 10000): return false
		for field in ["action_count", "alchemy_attempts", "research_crafts", "quests_completed", "exp"]:
			if not Economy.valid_integer(entry.get(field), 0) or entry[field] < record.ending[field]: return false
			if record.run_number == run.run_number:
				var maximum: int = run.statistics.alchemy_attempts if field == "alchemy_attempts" else run.resource_stats.quests_completed if field == "quests_completed" else run[field]
				if entry[field] > maximum: return false
		for key in entry.consumed:
			if not key is String: return false
			var parts: PackedStringArray = key.split("|", true)
			if parts.size() != 3 or parts[0] not in db.get_ids("recipes") or parts[1] not in Pills.QUALITIES or not Economy.valid_integer(entry.consumed[key], 1, 2): return false
			if baicao:
				if parts[0] != Pills.MUTATION_RECIPE or parts[2] != Pills.MUTATION_ID: return false
			elif parts[1] != "legendary" or parts[2] != "": return false
	return true


func _journal_valid(run: Dictionary, meta: Dictionary) -> bool:
	var journal: Variant = meta.get("material_journal", {})
	if not journal is Dictionary: return false
	for key in journal:
		if not key is String or not key.begins_with("run_"): return false
		var number_text: String = key.trim_prefix("run_")
		if not number_text.is_valid_int() or str(number_text.to_int()) != number_text or number_text.to_int() < 1 or number_text.to_int() > run.run_number or not _ids(journal[key], db.get_ids("materials"), db.get_ids("materials").size()): return false
	var allowed: Array = []
	if Pills.MUTATION_RECIPE in db.get_ids("recipes"):
		for quality in Pills.QUALITIES: allowed.append(Pills.key(Pills.MUTATION_RECIPE, quality, Pills.MUTATION_ID))
	return _ids(meta.get("mutation_discoveries", []), allowed, 4)


func _ids(value: Variant, allowed: Array, maximum: int) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Array = []
	for id in value:
		if not id is String or id not in allowed or id in seen: return false
		seen.append(id)
	return true


func _seed(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value
