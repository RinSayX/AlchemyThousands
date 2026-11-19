extends SceneTree
const Route := preload("res://tests/helpers/ending_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func _initialize() -> void:
	var report := Route.new().run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	for key in report.checkpoints:
		var point: Dictionary = report.checkpoints[key]
		var saved: Dictionary = Saves.new(report.session.content, "res://test-output/p8-endings/%s.json" % key).save_run(point.state, point.history, point.meta)
		if not saved.ok:
			printerr(saved.message)
			quit(1)
			return
	print("Ending route passed: rank=", report.session.state().rank, " endings=", report.session.meta().unlocked_endings, " brews=", report.session.state().statistics.alchemy_attempts, " studies=", report.session.state().research_crafts, " actions=", report.session.state().action_count, " stones=", report.session.state().spirit_stones)
	quit(0)
