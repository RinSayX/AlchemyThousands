extends SceneTree
const Route := preload("res://tests/helpers/progression_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Session := preload("res://scripts/core/game_session.gd")


func _initialize() -> void:
	var report := Route.new().run()
	if not report.ok:
		printerr(report.error)
		quit(1)
		return
	var first: RefCounted = report.session
	var checkpoint := "res://test-output/p7-demo/first-ending.json"
	var writer := Saves.new(first.content, checkpoint)
	var written := writer.save_run(first.state(), first.history(), first.meta())
	if not written.ok:
		printerr(written.message)
		quit(1)
		return
	var session := Session.new(checkpoint)
	var loaded := session.load_run()
	var claimed := session.claim_inheritance(1, "heritage_baicao")
	var preview := session.preview_rebirth(["heritage_baicao"])
	var reborn := session.begin_rebirth(1, ["heritage_baicao"])
	if not loaded.ok or not claimed.ok or not preview.ok or not reborn.ok:
		printerr([loaded.message, claimed.message, preview.message, reborn.message])
		quit(1)
		return
	var second := Session.new(checkpoint)
	if not second.load_run().ok or second.state() != session.state() or second.meta() != session.meta():
		printerr("Composite save did not round-trip")
		quit(1)
		return
	var left := session.begin_brew("recipe_juling", {})
	var right := second.begin_brew("recipe_juling", {})
	if not left.ok or left != right or session.state() != second.state() or session.meta() != second.meta():
		printerr("Second-run furnace did not replay")
		quit(1)
		return
	session.finish_brew()
	print("P7 flow passed: endings=", session.meta().records.size(), " run=", session.state().run_number, " worlds=", session.state().world_modifiers, " equipped=", session.state().equipped_inheritances, " attempts=", session.state().statistics.alchemy_attempts, " permanent discoveries=", session.meta().discovered_pills.size())
	if OS.get_cmdline_user_args().has("--write-checkpoints"):
		writer.save_run(first.state(), first.history(), first.meta())
		Saves.new(first.content, "res://test-output/p7-demo/second-run.json").save_run(session.state(), session.history(), session.meta())
		print("Isolated review files: res://test-output/p7-demo/first-ending.json and second-run.json")
	quit(0)
