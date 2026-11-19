extends SceneTree
const Route := preload("res://tests/helpers/equipment_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")


func _initialize() -> void:
	var helper := Route.new()
	var report := helper.run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	var session: RefCounted = report.session
	for rank_value in [3, 4, 6, 8, 10, "before_ice"]:
		var point: Dictionary = report.checkpoints[rank_value]
		var saved: Dictionary = Saves.new(session.content, "res://test-output/p8-equipment/rank-%s.json" % rank_value).save_run(point.state, point.history, point.meta)
		if not saved.ok:
			printerr(saved.message)
			quit(1)
			return
	var restored := Session.new("res://test-output/p8-equipment/rank-8.json")
	if not restored.load_run().ok or restored.state().owned_furnaces.size() != 6 or restored.state().owned_flames.size() != 5:
		printerr("Equipment checkpoint did not round-trip")
		quit(1)
		return
	var owned := 0
	for row in restored.destinations().result.rows:
		if row.completed: owned += 1
	if owned != 4:
		printerr("Claimed trials did not remain complete")
		quit(1)
		return
	print("Equipment route passed: rank=", session.state().rank, " furnaces=", session.state().owned_furnaces.size(), " flames=", session.state().owned_flames.size(), " real brews=", session.state().statistics.alchemy_attempts, " actions=", session.state().action_count, " cash=", session.state().spirit_stones, " acquisition events=", report.acquisitions.size())
	print("Review checkpoints: res://test-output/p8-equipment/rank-3.json through rank-10.json (3,4,6,8,10)")
	quit(0)
