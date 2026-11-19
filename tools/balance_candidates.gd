extends SceneTree
const Candidates := preload("res://tools/balance/candidate_experiment.gd")


func _initialize() -> void:
	var seeds := 8
	var samples := 10000
	var output := "res://test-output/p8-candidates.json"
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] not in ["--seeds", "--samples", "--output"] or i + 1 >= args.size():
			_fail("Unknown or incomplete option")
			return
		var flag: String = args[i]
		var value: String = args[i + 1]
		if flag == "--output": output = value
		elif not value.is_valid_int():
			_fail("Expected integer")
			return
		elif flag == "--seeds": seeds = value.to_int()
		else: samples = value.to_int()
		i += 2
	if seeds < 1 or seeds > 100 or samples < 1 or samples > 1000000:
		_fail("seeds must be 1..100; samples must be 1..1000000")
		return
	if (not output.begins_with("res://test-output/") and output != "res://docs/P8_TUNING_RESULTS.json") or output.contains("..") or not output.ends_with(".json"):
		_fail("Output must be test-output JSON or docs/P8_TUNING_RESULTS.json")
		return
	var report := Candidates.run(seeds, samples, func(message: String) -> void: print(message))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir()) != OK:
		_fail("Cannot create report directory")
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write report")
		return
	file.store_line("{")
	var keys := report.keys()
	for index in range(keys.size()):
		var key: String = keys[index]
		file.store_string(JSON.stringify(key) + ":")
		if report[key] is Array:
			file.store_line("[")
			for row_index in range(report[key].size()):
				file.store_line(JSON.stringify(report[key][row_index]) + ("," if row_index + 1 < report[key].size() else ""))
			file.store_string("]")
		else: file.store_string(JSON.stringify(report[key]))
		file.store_line("," if index + 1 < keys.size() else "")
	file.store_line("}")
	file.close()
	print("Candidate report: ", output, " ok=", report.ok)
	quit(0 if report.ok else 1)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
