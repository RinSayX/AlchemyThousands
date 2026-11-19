extends SceneTree
const Model := preload("res://tools/balance/equipment_model.gd")


func _initialize() -> void:
	var output := "res://test-output/p8-equipment-analysis.json"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--output" or args[1] != "res://docs/P8_EQUIPMENT_ANALYSIS.json":
			printerr("Use no arguments, or --output res://docs/P8_EQUIPMENT_ANALYSIS.json")
			quit(1)
			return
		output = args[1]
	var report := Model.run()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir()) != OK:
		printerr("Cannot create report directory")
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write equipment analysis")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Equipment analysis: ", report.ok, " ", output)
	quit(0 if report.ok else 1)
