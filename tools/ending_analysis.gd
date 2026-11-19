extends SceneTree
const Database := preload("res://scripts/core/content_db.gd")
const Spec := preload("res://scripts/core/ending_trial_definition.gd")
const Probe := preload("res://tools/balance/economy_probe.gd")

func _initialize() -> void:
	var db := Database.new()
	if not db.load_directory().ok:
		quit(1)
		return
	var loaded := Spec.read(db)
	if not loaded.ok:
		printerr(loaded.message)
		quit(1)
		return
	var rows: Array = []
	for worlds in [[], ["world_kucao", "world_yiji"], ["world_yiji", "world_jinhuo"]]:
		var state := Probe.fixture(db, 10, "stable", [], worlds)
		var total := 0.0
		var points := 0
		var items: Dictionary = {}
		for rule in loaded.result.definition.study:
			points += rule.research_cost
			for id in db.get_item(rule.recipe_id).materials:
				var amount: int = db.get_item(rule.recipe_id).materials[id] * rule.material_multiplier
				items[id] = items.get(id, 0) + amount
				var basis := Probe.unit_basis(db, state, id)
				if basis.stones == null:
					printerr("Unpriced material: ", id)
					quit(1)
					return
				total += basis.stones * amount
		rows.append({"worlds": worlds, "material_value": total, "research_cost": points, "materials": items})
	var report := {"engine": "4.5.stable.official.876b29033", "definition_sha256": FileAccess.get_sha256(Spec.PATH), "rows": rows, "scope": "Exact deterministic recipe costs using repeatable source unit values; excludes recipe unlock/equipment investment, whole-outing rounding and research acquisition time. Public route separately verifies actual cash and commands."}
	var output := "res://test-output/p8-ending-analysis.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print(JSON.stringify(report))
	quit(0)
