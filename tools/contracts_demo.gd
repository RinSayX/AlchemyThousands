extends SceneTree
const Route := preload("res://tests/helpers/contracts_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func _initialize() -> void:
	var report := Route.new().run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	var session: RefCounted = report.session
	for entry in [["before-delivery", report.before_delivery], ["completed", {"state": session.state(), "meta": session.meta(), "history": session.history()}]]:
		var point: Dictionary = entry[1]
		var result: Dictionary = Saves.new(session.content, "res://test-output/p8-contracts/%s.json" % entry[0]).save_run(point.state, point.history, point.meta)
		if not result.ok:
			printerr(result.message)
			quit(1)
			return
	print("Contracts route passed: new deliveries=", report.deliveries.size(), " rank=", session.state().rank, " brews=", session.state().statistics.alchemy_attempts, " actions=", session.state().action_count, " stones=", session.state().spirit_stones)
	for row in report.deliveries: print(row.quest, " rank=", row.rank, " extra attempts=", row.attempts_after_first_pill)
	quit(0)
