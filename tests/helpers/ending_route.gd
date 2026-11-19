extends RefCounted
## End-to-end ending trial through public gameplay commands, no result injection.
const Contracts := preload("res://tests/helpers/contracts_route.gd")
var base := Contracts.new()
var error := ""
var checkpoints: Dictionary = {}

func run() -> Dictionary:
	var report := base.run()
	if not report.ok: return report
	var session: RefCounted = report.session
	checkpoints.initial = _point(session)
	var standard: Dictionary = session.state().ending
	var total_points := 0
	var all_items: Dictionary = {}
	for item in session.ending_trial().result.definition.study:
		var plan: Dictionary = session.ending_study_preview(item.recipe_id).result
		total_points += plan.research_cost
		for id in plan.cost_items: all_items[id] = all_items.get(id, 0) + plan.cost_items[id]
	# Prepare both batches before crafting, so public funding never sells the first proof pill.
	while session.state().research_points < total_points:
		if not base.catalog.gear.driver._earn():
			error = base.catalog.gear.driver.error
			return _result(false, session)
	if not base.catalog.ensure_items(all_items):
		error = base.catalog.error
		return _result(false, session)
	checkpoints.before_study = _point(session)
	for item in session.ending_trial().result.definition.study:
		if not _accept(session.study_ending(session.state().run_number, item.recipe_id)): return _result(false, session)
	checkpoints.before_certify = _point(session)
	if not _accept(session.certify_ending(session.state().run_number)): return _result(false, session)
	if session.state().ending != standard:
		error = "Standard ending snapshot changed"
		return _result(false, session)
	checkpoints.certified = _point(session)
	return _result(true, session)

func _point(session: RefCounted) -> Dictionary:
	return {"state": session.state(), "meta": session.meta(), "history": session.history()}

func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok

func _result(value: bool, session: RefCounted) -> Dictionary:
	return {"ok": value, "error": error, "session": session, "checkpoints": checkpoints.duplicate(true)}
