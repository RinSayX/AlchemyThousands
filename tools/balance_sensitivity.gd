extends SceneTree
## Conditioned gear comparison; complements, never replaces, campaign policies.
const Database := preload("res://scripts/core/content_db.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")
const Experiment := preload("res://tools/balance/experiment.gd")
const Growth := preload("res://scripts/services/progression_service.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const SAMPLES := 100000


func _initialize() -> void:
	var output := "res://test-output/p8-build-sensitivity.json"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--output" or args[1] != "res://docs/P8_BUILD_SENSITIVITY.json":
			printerr("Use no arguments, or --output res://docs/P8_BUILD_SENSITIVITY.json")
			quit(1)
			return
		output = args[1]
	var db := Database.new()
	var loaded := db.load_directory()
	if not loaded.ok:
		printerr(loaded.errors)
		quit(1)
		return
	var hashes := Experiment.fingerprint()
	var rows: Array = []
	var errors: Array = []
	for target in range(1, 11):
		var exam: Dictionary = Growth.new(db).rank_definition(target)
		for style in ["stable", "rush", "recycle"]:
			for furnace in ["furnace_basic", "furnace_qingmu", "furnace_chiyan"]:
				if target == 1 and furnace != "furnace_basic": continue
				if furnace == "furnace_chiyan" and (style != "rush" or "fire" not in db.get_item(exam.exam_recipe_id).tags): continue
				var state := Probe.fixture(db, target, style, [], [])
				state.owned_furnaces = [furnace]
				# Make default equipment ownership coherent for production validation.
				state.equipped_furnace = furnace
				var row := Probe.analyze(db, state, exam.exam_recipe_id, style, exam.min_quality, SAMPLES, 91000 + target)
				row["target"] = target
				row["conditioned_furnace"] = furnace
				rows.append(row)
				if not row.ok or not row.get("mean_within_bound", false): errors.append("Invalid sensitivity row: " + str(target) + "/" + style + "/" + furnace)
	if hashes != Experiment.fingerprint(): errors.append("Inputs changed during sensitivity run")
	hashes["tools/balance_sensitivity.gd"] = FileAccess.get_sha256("res://tools/balance_sensitivity.gd")
	var report := {"report_schema": 1, "engine": Context.ENGINE_VERSION, "ok": errors.is_empty(), "errors": errors, "input_hashes": hashes, "samples_per_row": SAMPLES, "scope": "First-world conditioned gear only; excludes purchase costs, funding and acquisition. Same stage/talents/flame for each comparison; all ownership fields are coherent.", "rows": rows}
	var absolute := ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		printerr("Cannot create analysis output directory")
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write analysis artifact")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Build sensitivity: ", output, " rows=", rows.size(), " errors=", errors.size())
	quit(0 if errors.is_empty() else 1)
