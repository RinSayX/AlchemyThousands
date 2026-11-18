extends RefCounted
## End-to-end reachability driver: only public session commands, no injected loot/rank.
const Session := preload("res://scripts/core/game_session.gd")
var session: Session
var steps := 0
var error := ""
var checkpoints: Dictionary = {}


func run(style: String = "research", stop_at: int = 10, choose_last: bool = true, existing_session: Variant = null) -> Dictionary:
	session = Session.new() if existing_session == null else existing_session
	if existing_session == null and not _accept(session.new_run(20261119)):
		return _result(false)
	if not _accept(session.accept_quest("quest_juling_supply")):
		return _result(false)
	for target in range(1, stop_at + 1):
		var exam: Dictionary = session.progression().result.next
		while session.state().research_points < session.study_preview().result.research_cost or session.state().exp < exam.exp_required:
			if not _earn():
				return _result(false)
		if not exam.required_flame.is_empty() and exam.required_flame not in session.state().owned_flames:
			if not _ensure_items({"ore_tiejing": 2}) or not _event("event_earth_fire", "choice_ritual"):
				return _result(false)
		if not _ensure_items(session.study_preview().result.cost_items):
			return _result(false)
		if not _accept(session.study_exam(target)):
			return _result(false)
		if not _accept(session.promote(target)):
			return _result(false)
		checkpoints[target] = session.state()
		if target in [3, 6, 9] and (target < stop_at or choose_last):
			if not _accept(session.choose_talent("talent_%s_%d" % [style, target])):
				return _result(false)
	return _result(true)


func _earn() -> bool:
	steps += 1
	if steps > 1500:
		error = "Reachability route exceeded furnace bound"
		return false
	if not session.preview("recipe_juling", {}).result.can_execute:
		if session.forage_status().result.can_rest and not _accept(session.rest()):
			return false
		if not _accept(session.forage()):
			return false
	if not _accept(session.begin_brew("recipe_juling", {"strategy": "stable"})) or not _accept(session.finish_brew()):
		return false
	var offer: Dictionary = session.quest_board().result.rows[0]
	if not offer.active_id.is_empty() and offer.delivery.can_deliver:
		if not _accept(session.deliver_quest(offer.active_id)):
			return false
	if session.quote_products().ok and not _accept(session.sell_products()):
		return false
	return true


func _ensure_items(costs: Dictionary) -> bool:
	for id in costs:
		var deficit: int = costs[id] - session.state().inventory.get(id, 0)
		while deficit > 0:
			var item: Dictionary = session.content.get_item(id)
			if item.shop_available:
				if not _accept(session.buy_shop(id, deficit)):
					return false
			elif id == "herb_lingzhi":
				if not _event("event_old_grove", "choice_trade"):
					return false
			elif id == "essence_hunlu":
				if not _event("event_soul_spring", "choice_offer"):
					return false
			else:
				error = "No deterministic source: " + id
				return false
			deficit = costs[id] - session.state().inventory.get(id, 0)
	return true


func _event(event_id: String, choice: String) -> bool:
	var entered := session.enter_event(event_id)
	if not _accept(entered):
		return false
	return _accept(session.resolve_event(entered.result.instance_id, choice))


func _accept(result: Dictionary) -> bool:
	if not result.ok:
		error = result.error_code + ": " + result.message
	return result.ok


func _result(ok: bool) -> Dictionary:
	return {"ok": ok, "error": error, "session": session, "furnaces": steps, "checkpoints": checkpoints}
