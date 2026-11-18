extends SceneTree
## Run with --headless --path . --script res://tools/validate_content.gd

const Database := preload("res://scripts/core/content_db.gd")


func _initialize() -> void:
	var db := Database.new()
	var directory := "res://data"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		directory = args[0]
	var result := db.load_directory(directory)
	if result.ok:
		print("Content valid: ", result.counts)
		quit(0)
	else:
		for error in result.errors:
			var location: String = error.path
			if error.has("line"):
				location += " (JSON line %s)" % error.line
			printerr("%s %s: %s" % [error.code, location, error.message])
		quit(1)
