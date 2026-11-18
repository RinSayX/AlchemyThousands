extends SceneTree
## Optional first user argument is a JSON report output path.

const Simulation := preload("res://tests/alchemy_probability.gd")


func _initialize() -> void:
	var report := Simulation.new().run()
	for row in report.profiles:
		print("%s: n=%d, success %.4f / expected %.4f, extra %.4f, passed=%s" % [row.name, row.samples, row.success_actual, row.success_expected, row.extra_actual, row.passed])
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file == null:
			printerr("Cannot open report output: ", args[0])
			quit(1)
			return
		file.store_string(JSON.stringify(report, "  ") + "\n")
		var error := file.get_error()
		file.close()
		if error != OK:
			printerr("Report write failed: ", error_string(error))
			quit(1)
			return
	print("Probability simulation passed: ", report.passed)
	quit(0 if report.passed else 1)
