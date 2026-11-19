extends RefCounted
const Ending := preload("res://tests/helpers/ending_route.gd")
var base := Ending.new()
var error := ""
var checkpoints: Dictionary = {}

func run() -> Dictionary:
	var result := base.run()
	if not result.ok: return result
	var session: RefCounted = result.session
	var catalog: RefCounted = base.base.catalog
	var study: Dictionary = session.mutation_study_preview().result
	var cost: int = study.research_cost + session.baicao_trial().result.definition.ending.research_cost
	while session.state().research_points < cost:
		if not catalog.gear.driver._earn():
			error = catalog.gear.driver.error
			return _result(false, session)
	# Record actual contact, not possession: only gather missing journal entries.
	for id in session.baicao_trial().result.missing_materials:
		if id == "material_danzha":
			error = "Normal route did not encounter residue"
			return _result(false, session)
		if not catalog.ensure_items({id: 1}):
			error = catalog.error
			return _result(false, session)
	if not catalog.ensure_items(study.cost_items):
		error = catalog.error
		return _result(false, session)
	checkpoints.before_mutation_study = _point(session)
	if not _accept(session.study_mutation(1)): return _result(false, session)
	checkpoints.before_baicao = _point(session)
	if not _accept(session.certify_baicao(1)): return _result(false, session)
	checkpoints.completed = _point(session)
	return _result(true, session)

func _point(session: RefCounted) -> Dictionary:
	return {"state": session.state(), "meta": session.meta(), "history": session.history()}

func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok

func _result(value: bool, session: RefCounted) -> Dictionary:
	return {"ok": value, "error": error, "session": session, "checkpoints": checkpoints}
