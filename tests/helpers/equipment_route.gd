extends RefCounted
## Real acquisitions at their rank milestones. No injected money, loot or rank.
const Route := preload("res://tests/helpers/progression_route.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
var driver := Route.new()
var error := ""
var acquisitions: Array[Dictionary] = []
var checkpoints: Dictionary = {}


func run(stop_at: int = 10) -> Dictionary:
	var result := driver.run("rush", stop_at, true, null, _milestone)
	return {"ok": result.ok and error.is_empty(), "error": error if not error.is_empty() else result.error, "session": driver.session, "acquisitions": acquisitions.duplicate(true), "checkpoints": checkpoints.duplicate(true), "furnaces": driver.steps}


func _milestone(rank_value: int) -> bool:
	if rank_value == 1:
		for id in ["furnace_qingmu", "furnace_chiyan"]:
			var item: Dictionary = driver.session.content.get_item(id)
			if not _fund(item.unlock.price) or not _accept(driver.session.buy_shop(id, 1)): return false
		if not acquire("event_earth_fire", "choice_ritual"): return false
	for event in driver.session.content.get_items("exploration_events"):
		if "trial" not in event.tags or event.unlock.required_rank != rank_value: continue
		for option in event.options:
			if not acquire(event.id, option.id): return false
	checkpoints[rank_value] = {"state": driver.session.state(), "meta": driver.session.meta(), "history": driver.session.history()}
	return true


func acquire(event_id: String, option_id: String) -> bool:
	var db: RefCounted = driver.session.content
	for original in db.get_item(event_id).options:
		if original.id != option_id: continue
		var option := Lineage.option(db, driver.session.state(), event_id, original)
		if not ensure_items(option.cost_items, option.cost_stones): return false
		var before: Dictionary = driver.session.state()
		if event_id == "event_xuanbing_trial" and option_id == "choice_forge_xuanbing":
			checkpoints["before_ice"] = {"state": before, "meta": driver.session.meta(), "history": driver.session.history()}
		var entered: Dictionary = driver.session.enter_event(event_id)
		if not _accept(entered): return false
		var resolved: Dictionary = driver.session.resolve_event(entered.result.instance_id, option_id)
		if not _accept(resolved): return false
		acquisitions.append({"event": event_id, "option": option_id, "rank": before.rank, "stones": option.cost_stones, "items": option.cost_items.duplicate(), "flame": option.reward_flame, "furnace": option.get("reward_furnace", ""), "furnaces_before": before.statistics.alchemy_attempts})
		return true
	error = "Unknown acquisition: " + event_id + "/" + option_id
	return false


func ensure_items(costs: Dictionary, fee: int = 0) -> bool:
	var db: RefCounted = driver.session.content
	var state: Dictionary = driver.session.state()
	var budget := fee
	for id in costs:
		var missing := maxi(costs[id] - state.inventory.get(id, 0), 0)
		if missing == 0: continue
		var item: Dictionary = db.get_item(id)
		if item.shop_available:
			budget += Lineage.buy_price(db, state, item, item.buy_price) * missing
		elif Probe.RARE_SOURCES.has(id):
			var source: Array = Probe.RARE_SOURCES[id]
			for original in db.get_item(source[0]).options:
				if original.id == source[1]:
					var option := Lineage.option(db, state, source[0], original)
					budget += int(ceil(float(missing) / option.success_items[id])) * option.cost_stones
		else:
			error = "Unsupported source: " + id
			return false
	if not _fund(budget): return false
	if not driver._ensure_items(costs):
		error = driver.error
		return false
	return true


func _fund(amount: int) -> bool:
	while driver.session.state().spirit_stones < amount:
		if not driver._earn():
			error = driver.error
			return false
	return true


func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok
