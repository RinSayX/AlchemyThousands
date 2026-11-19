extends SceneTree
const Route := preload("res://tests/helpers/catalog_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")

func _initialize() -> void:
	var route := Route.new()
	var report := route.run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	for key in [2, 4, 6, 8, 10, "before_gushen"]:
		var point: Dictionary = report.checkpoints[key]
		var saved: Dictionary = Saves.new(report.session.content, "res://test-output/p8-catalog/rank-%s.json" % key).save_run(point.state, point.history, point.meta)
		if not saved.ok:
			printerr(saved.message)
			quit(1)
			return
	print("Catalog route passed: recipes=", report.records.size(), " rank=", report.session.state().rank, " brews=", report.session.state().statistics.alchemy_attempts, " actions=", report.session.state().action_count, " stones=", report.session.state().spirit_stones)
	for row in report.records: print(row.recipe, " rank=", row.rank, " attempts=", row.attempts, " quality=", row.quality)
	quit(0)
