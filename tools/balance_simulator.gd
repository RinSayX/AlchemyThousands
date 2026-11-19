extends SceneTree
const Database := preload("res://scripts/core/content_db.gd")
const Experiment := preload("res://tools/balance/experiment.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output := "res://test-output/p8-balance.json"
	var samples := 10000
	var seeds := 4
	var smoke := false
	var index := 0
	while index < args.size():
		var flag: String = args[index]
		if flag == "--smoke":
			smoke = true
		elif flag in ["--output", "--samples", "--seeds"] and index + 1 < args.size():
			index += 1
			var value: String = args[index]
			if flag == "--output": output = value
			elif not value.is_valid_int():
				_fail("Expected positive integer for " + flag)
				return
			elif flag == "--samples": samples = value.to_int()
			else: seeds = value.to_int()
		else:
			_fail("Unknown or incomplete option: " + flag)
			return
		index += 1
	if samples < 1 or samples > 1000000 or seeds < 1 or seeds > 100:
		_fail("samples must be 1..1000000 and seeds 1..100")
		return
	# Analysis artifacts cannot overwrite source content or player saves.
	if not output.begins_with("res://test-output/") and output != "res://docs/P8_BALANCE_RESULTS.json":
		_fail("Output must be an analysis artifact under test-output or docs/P8_BALANCE_RESULTS.json")
		return
	if output.contains("..") or not output.ends_with(".json"):
		_fail("Invalid output artifact path")
		return
	var db := Database.new()
	var loaded := db.load_directory()
	if not loaded.ok:
		_fail(str(loaded.errors))
		return
	var report := Experiment.run(db, samples, seeds, func(message: String) -> void: print(message), smoke)
	var path := ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		_fail("Cannot create output directory")
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write output artifact")
		return
	# One record per line keeps generated traces reviewable without huge indentation.
	file.store_line("{")
	var keys := report.keys()
	for key_index in range(keys.size()):
		var key: String = keys[key_index]
		file.store_string(JSON.stringify(key) + ":")
		if report[key] is Array:
			file.store_line("[")
			for row_index in range(report[key].size()):
				file.store_line(JSON.stringify(report[key][row_index]) + ("," if row_index < report[key].size() - 1 else ""))
			file.store_string("]")
		else:
			file.store_string(JSON.stringify(report[key]))
		file.store_line("," if key_index < keys.size() - 1 else "")
	file.store_line("}")
	file.close()
	print("Balance report: ", output, " campaigns=", report.campaigns.size(), " stage probes=", report.stage_probes.size(), " technical_errors=", report.errors.size())
	quit(0 if report.ok else 1)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
