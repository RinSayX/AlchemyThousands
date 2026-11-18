extends SceneTree
const Route := preload("res://tests/helpers/progression_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--prepare-final"):
		var driver := Route.new()
		var review := driver.run("research", 9, false)
		if not review.ok:
			printerr(review.error)
			quit(1)
			return
		while driver.session.state().research_points < driver.session.study_preview().result.research_cost:
			if not driver._earn():
				printerr(driver.error)
				quit(1)
				return
		if not driver._ensure_items(driver.session.study_preview().result.cost_items):
			printerr(driver.error)
			quit(1)
			return
		var saved := Saves.new(driver.session.content, "res://test-output/p6-demo/final-ready.json").save_run(driver.session.state(), driver.session.history())
		print("Final review checkpoint: rank=", driver.session.state().rank, " points=", driver.session.state().research_points, " pending_talent=", driver.session.state().pending_talent_rank, " saved=", saved.ok)
		quit(0 if saved.ok else 1)
		return
	var report := Route.new().run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	var session: RefCounted = report.session
	print("P6 public-command route: rank=", session.state().rank, ", furnaces=", report.furnaces, ", actions=", session.state().action_count, ", talents=", session.state().talent_choices, ", ending=", session.state().ending)
	if OS.get_cmdline_user_args().has("--write-checkpoints"):
		for rank_value in [3, 9, 10]:
			var path := "res://test-output/p6-demo/rank-%d.json" % rank_value
			var saved := Saves.new(session.content, path).save_run(report.checkpoints[rank_value])
			if not saved.ok:
				printerr(saved.message)
				quit(1)
				return
		print("Review checkpoints written under res://test-output/p6-demo (no real user save).")
	quit(0)
