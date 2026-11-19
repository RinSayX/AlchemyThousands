extends SceneTree
## Public-command checkpoint for reviewing the P8 tuning in the real UI.
const Route := preload("res://tests/helpers/progression_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")


func _initialize() -> void:
	var route := Route.new().run("research", 3, false)
	if not route.ok:
		_fail(route.error)
		return
	var session: RefCounted = route.session
	for id in ["furnace_chiyan", "recipe_cuiti"]:
		var purchase: Dictionary = session.buy_shop(id, 1)
		if not purchase.ok:
			_fail(purchase.message)
			return
	var materials: Dictionary = session.buy_materials("recipe_cuiti", 1)
	if not materials.ok:
		_fail(materials.message)
		return
	var directory := "res://test-output/p8-tuning"
	var saved: Dictionary = Saves.new(session.content, directory + "/pending-three.json").save_run(session.state(), session.history(), session.meta())
	if not saved.ok:
		_fail(saved.message)
		return
	var setup := {"strategy": "rush", "furnace_id": "furnace_chiyan", "flame_id": "flame_normal"}
	var before: Dictionary = session.preview("recipe_cuiti", setup).result
	var chosen: Dictionary = session.choose_talent("talent_rush_3")
	var after: Dictionary = session.preview("recipe_cuiti", setup).result
	if not chosen.ok or not is_equal_approx(before.success_rate, after.success_rate) or after.quality_weights.legendary != before.quality_weights.legendary + 3:
		_fail("Talent did not preserve success and transfer three legendary weights")
		return
	saved = Saves.new(session.content, directory + "/chosen-rush.json").save_run(session.state(), session.history(), session.meta())
	if not saved.ok:
		_fail(saved.message)
		return
	# Give both replay branches the same persistence boundary and dirty flag.
	for name in ["replay-a.json", "replay-b.json"]:
		if not Saves.new(session.content, directory + "/" + name).save_run(session.state(), session.history(), session.meta()).ok:
			_fail("Could not prepare isolated replay branches")
			return
	session = Session.new(directory + "/replay-a.json")
	var resumed := Session.new(directory + "/replay-b.json")
	if not session.load_run().ok or not resumed.load_run().ok:
		_fail("Could not resume review checkpoint")
		return
	var left: Dictionary = session.begin_brew("recipe_cuiti", setup)
	var right := resumed.begin_brew("recipe_cuiti", setup)
	if not left.ok or left != right or session.state() != resumed.state():
		_fail("Real tuned furnace did not replay after loading")
		return
	print("P8 tuning demo passed: rank=3 success=", after.success_rate, " conditional legendary=", after.quality_probabilities.legendary, " result=", left.result.quality)
	print("Review checkpoints: ", directory, "/pending-three.json and chosen-rush.json")
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
