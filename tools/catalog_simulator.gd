extends SceneTree
const Model := preload("res://tools/balance/catalog_model.gd")

func _initialize() -> void:
	var output := "res://test-output/p8-catalog-analysis.json"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args != PackedStringArray(["--output", "res://docs/P8_CATALOG_ANALYSIS.json"]):
			printerr("Use no arguments, or --output res://docs/P8_CATALOG_ANALYSIS.json")
			quit(1)
			return
		output = args[1]
	var report := Model.run(func(id: String): print("Analyzed ", id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write catalog report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Catalog analysis: ", report.ok, " ", report.get("errors", []))
	quit(0 if report.ok else 1)
