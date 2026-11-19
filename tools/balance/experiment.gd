extends RefCounted
## Report orchestration only; does not edit content or player saves.
const Probe := preload("res://tools/balance/economy_probe.gd")
const Route := preload("res://tools/balance/campaign_route.gd")
const Growth := preload("res://scripts/services/progression_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")


static func scenarios(db: RefCounted) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{"id": "first", "loadout": [], "worlds": [], "start_run": 1}]
	# Matched world control for the single-inheritance experiments.
	var control := ["world_dansheng", "world_huoling"]
	for item in db.get_items("inheritances"):
		rows.append({"id": item.id, "loadout": [item.id], "worlds": control.duplicate(), "start_run": 2})
	var worlds: Array = db.get_items("world_modifiers")
	for i in range(worlds.size()):
		for j in range(i + 1, worlds.size()):
			var a: Dictionary = worlds[i]
			var b: Dictionary = worlds[j]
			if b.id in a.exclusive_with or a.id in b.exclusive_with or not (a.opportunity or b.opportunity): continue
			rows.append({"id": a.id + "+" + b.id, "loadout": [], "worlds": [a.id, b.id], "start_run": 2})
	rows.append({"id": "dual_baicao_huishou", "loadout": ["heritage_baicao", "heritage_huishou"], "worlds": control, "start_run": 3})
	return rows


static func fingerprint() -> Dictionary:
	var hashes: Dictionary = {"tools/balance_simulator.gd": FileAccess.get_sha256("res://tools/balance_simulator.gd")}
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"): hashes["data/" + file] = FileAccess.get_sha256("res://data/" + file)
	for directory in ["scripts/core", "scripts/services", "tools/balance"]:
		for file in DirAccess.get_files_at("res://" + directory):
			if file.ends_with(".gd"): hashes[directory + "/" + file] = FileAccess.get_sha256("res://" + directory + "/" + file)
	return hashes


static func summarize(runs: Array) -> Dictionary:
	var result := {"runs": runs.size(), "statuses": {}, "completed": 0, "stages": []}
	for row in runs:
		result.statuses[row.status] = result.statuses.get(row.status, 0) + 1
		if row.status == "completed": result.completed += 1
	for field in ["furnaces", "failures", "actions", "commands", "support_furnaces", "net_cash", "cash_end", "min_cash", "earned", "spent", "outings", "forages", "rests", "studies", "liquidity_shortfalls", "consumable_skips"]:
		var values: Array = []
		var sum := 0.0
		for row in runs:
			values.append(row[field])
			sum += row[field]
		values.sort()
		result[field] = {"mean": sum / maxf(runs.size(), 1), "p10": Probe.percentile(values, 0.1), "p50": Probe.percentile(values, 0.5), "p90": Probe.percentile(values, 0.9), "min": values.front() if not values.is_empty() else null, "max": values.back() if not values.is_empty() else null}
	for target in range(1, 11):
		var stage_rows: Array = []
		for row in runs:
			for stage in row.stages:
				if stage.target == target: stage_rows.append(stage)
		if stage_rows.is_empty(): continue
		var stage_result := {"target": target, "reached": stage_rows.size()}
		for field in ["furnaces", "failures", "actions", "commands", "support_furnaces", "random_exam_attempts", "studies", "earned", "spent", "cash_end", "outings", "forages", "rests"]:
			var sum := 0.0
			for row in stage_rows: sum += row[field]
			stage_result[field] = sum / stage_rows.size()
		result.stages.append(stage_result)
	return result


static func quest_probes(db: RefCounted, scenario: Dictionary) -> Array:
	var rows: Array = []
	for template in db.get_items("quests"):
		var state := Probe.fixture(db, maxi(2, template.unlock.required_rank + 1), "stable", scenario.loadout, scenario.worlds)
		var changed := Lineage.quest(db, state, template)
		rows.append({"id": template.id, "min_quality": changed.min_quality, "quantity": changed.quantity, "stones": changed.reward_spirit_stones, "reward_items": changed.reward_items})
	return rows


static func free_source_probe(db: RefCounted, repeats: int = 100) -> Dictionary:
	var state: Dictionary = preload("res://scripts/core/profile_state.gd").new(db).create_run(88117).result.state
	# Condition on rank one to measure the repeatable mineral option in isolation.
	state.rank = 1
	state.spirit_stones = 0
	state.inventory = {}
	var explore := preload("res://scripts/services/exploration_service.gd").new(db)
	var shop := preload("res://scripts/services/shop_service.gd").new(db)
	for index in range(repeats):
		var entered: Dictionary = explore.enter(state, "free-entry-%d" % index, "event_mineral_vein")
		if not entered.ok: return {"ok": false, "error": entered.message}
		var resolved: Dictionary = explore.resolve(state, entered.result.instance_id, "choice_mine", "free-choice-%d" % index)
		if not resolved.ok: return {"ok": false, "error": resolved.message}
		var lines: Array = []
		for id in resolved.result.items: lines.append({"item_id": id, "quantity": resolved.result.items[id]})
		var sold: Dictionary = shop.sell_batch(state, lines, "free-sale-%d" % index)
		if not sold.ok: return {"ok": false, "error": sold.message}
	return {"ok": true, "repeats": repeats, "cash": state.spirit_stones, "actions": state.action_count, "commands": repeats * 3, "furnaces": state.statistics.alchemy_attempts, "fixture": "rank one, zero cash/materials; all iterations execute real services"}


static func run(db: RefCounted, samples: int, seeds: int, progress: Callable = Callable(), smoke: bool = false) -> Dictionary:
	var before := fingerprint()
	var definition := scenarios(db)
	if smoke: definition.resize(1)
	var rows: Array = []
	var probes: Array = []
	var failures: Array = []
	var summaries: Array = []
	var recovery: Array = []
	for scenario in definition:
		for style in Probe.STYLES:
			var group: Array = []
			for index in range(seeds):
				var row: Dictionary = Route.new(db).run(73001 + index, style, scenario.loadout, scenario.worlds, 3 if smoke else 10)
				row["scenario"] = scenario.id
				rows.append(row)
				group.append(row)
				var stress: Dictionary = Route.new(db).recovery_probe(73001 + index, style, scenario.loadout, scenario.worlds)
				stress["scenario"] = scenario.id
				recovery.append(stress)
				if stress.status != "recovered" or not stress.cash_reconciles: failures.append("Recovery probe failed: " + scenario.id + "/" + style)
				if row.status in ["transaction_error", "unsupported_source", "invalid_experiment"]: failures.append(scenario.id + "/" + style + ": " + row.error)
			var summary := summarize(group)
			summary.merge({"scenario": scenario.id, "style": style})
			summaries.append(summary)
			for target in range(1, 4 if smoke else 11):
				var state := Probe.fixture(db, target, style, scenario.loadout, scenario.worlds)
				var exam: Dictionary = Growth.new(db).rank_definition(target)
				var probe := Probe.analyze(db, state, exam.exam_recipe_id, style, exam.min_quality, samples, 91000 + target)
				probe.merge({"scenario": scenario.id, "target": target})
				probes.append(probe)
				if not probe.ok or not probe.get("mean_within_bound", false): failures.append("Probe failed: " + scenario.id + "/" + style + "/" + str(target))
		if progress.is_valid(): progress.call("Simulated " + scenario.id + ": " + str(rows.size()) + " campaigns")
	var quests: Dictionary = {}
	for scenario in definition: quests[scenario.id] = quest_probes(db, scenario)
	var after := fingerprint()
	if before != after: failures.append("Input files changed during experiment")
	var free_source := free_source_probe(db, 10 if smoke else 100)
	if not free_source.ok: failures.append("Free source service probe failed")
	return {"report_schema": 1, "engine": Context.ENGINE_VERSION, "policy_version": 1, "ok": failures.is_empty(), "errors": failures, "input_hashes": before, "inputs_unchanged": before == after, "seed_start": "73001", "seed_count": seeds, "probe_samples_per_row": samples, "smoke": smoke, "scenario_definitions": definition, "policy_styles": Probe.STYLES, "campaigns": rows, "summaries": summaries, "stage_probes": probes, "quest_probes": quests, "bankruptcy_recovery": recovery, "free_source_probe": free_source, "assumptions": ["Controlled later-life loadouts/worlds; no permanent unlock grind is simulated", "Stage probes condition on all rank-one equipment already owned and exclude its sunk cost", "Campaigns purchase equipment and acquire earth flame at rank one using actual services", "Rush uses chiyan on fire recipes; recycle uses stable talents and hulu jade", "At most eight natural exam attempts before deterministic study; research control studies immediately", "All support income uses free basic forage/rest and sells outputs; stable also repeats basic supply commissions", "Rare inputs valued by deterministic trade sources, including outing counts; inventory returns are opportunity value, not immediate cash", "No player saves, UI timing, hidden endings or content changes"]}
