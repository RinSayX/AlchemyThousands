extends RefCounted
const Session := preload("res://scripts/core/game_session.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const State := preload("res://scripts/core/progression_state.gd")
const Route := preload("res://tests/helpers/progression_route.gd")
var _check: Callable
var directory: String

class FaultSave:
	extends "res://scripts/services/save_manager.gd"
	var fail_write := false
	var fail_replace := false
	var fail_backup := false
	var corrupt_after_replace := false

	func _write_file(file_path: String, text: String) -> Error:
		if fail_write:
			super._write_file(file_path, text.substr(0, 12))
			return ERR_CANT_CREATE
		return super._write_file(file_path, text)

	func _replace(source: String, destination: String) -> Error:
		if (fail_replace and destination == path) or (fail_backup and destination == path + ".bak"):
			return ERR_CANT_CREATE
		var error := super._replace(source, destination)
		if error == OK and destination == path and corrupt_after_replace:
			corrupt_after_replace = false
			super._write_file(path, "broken")
		return error


func run(check: Callable) -> bool:
	_check = check
	directory = "res://test-output/p6-save-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_basic_and_rng()
	_faults()
	_roundtrip_progress()
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	return true


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _basic_and_rng() -> void:
	var path := directory.path_join("run.json")
	var session := Session.new(path)
	_check.call(session.saved_run().error_code == "NO_SAVE" and not session.has_run(), "P6 save: Fresh profile has no run or starter rewards")
	_check.call(session.new_run(12345).ok and session.save_status.ok and FileAccess.file_exists(path) and not session.state().needs_save, "P6 save: New run autosaves validated schema and clean dirty flag")
	var second := Session.new(path)
	_check.call(second.load_run().ok and session.state() == second.state(), "P6 save: Fresh process coordinator restores exact integer resources, progression and RNG")
	var before: Dictionary = session.state()
	session.preview("recipe_juling", {})
	_check.call(before == session.state(), "P6 save: Autosave wiring does not change preview purity")
	var left := session.begin_brew("recipe_juling", {})
	_check.call(left.ok and session.is_busy() and session.save_status.ok, "P6 save: Paid furnace is checkpointed before its animation reveals")
	var resumed := Session.new(path)
	_check.call(resumed.load_run().ok and not resumed.is_busy() and resumed.history().size() == 1 and resumed.state() == session.state(), "P6 save: Reload during animation resumes settled state/history without another roll or charge")
	_check.call(not resumed.finish_brew().ok, "P6 save: Reloaded settled furnace has no second reveal reward")
	session.finish_brew()
	left = session.begin_brew("recipe_juling", {"strategy": "stable"})
	var right := resumed.begin_brew("recipe_juling", {"strategy": "stable"})
	_check.call(left.ok and left == right and session.state() == resumed.state(), "P6 save: Reload continues the identical next furnace, action ID and all RNG streams")
	session.finish_brew()
	resumed.finish_brew()
	var entered := session.enter_event("event_qinglan")
	var checkpoint := Session.new(path)
	_check.call(entered.ok and checkpoint.load_run().ok and checkpoint.is_busy() and checkpoint.state().pending_exploration == session.state().pending_exploration, "P6 save: Unresolved exploration instance survives restart without being re-entered")
	var id: String = entered.result.instance_id
	left = session.resolve_event(id, "choice_deep")
	right = checkpoint.resolve_event(id, "choice_deep")
	_check.call(left.ok and left == right and session.state() == checkpoint.state(), "P6 save: Pending paid exploration continues the identical outcome after reload")
	var detached := checkpoint.saved_run()
	detached.result.state.inventory.herb_lingcao = 999
	_check.call(checkpoint.state().inventory.get("herb_lingcao", 0) != 999, "P6 save: Loaded and inspected file payloads cannot alias live session state")
	var gap_path := directory.path_join("gaps.json")
	var gap := Session.new(gap_path)
	gap.new_run(1)
	gap.buy_shop("herb_lingcao", -1)
	var gap_loaded := Session.new(gap_path)
	gap_loaded.load_run()
	_check.call(gap.begin_brew("recipe_juling", {}) == gap_loaded.begin_brew("recipe_juling", {}), "P6 save: A rejected command before restart cannot change the next committed action ID")
	var saved_before := FileAccess.get_file_as_string(path)
	checkpoint.buy_shop("herb_lingcao", -1)
	_check.call(FileAccess.get_file_as_string(path) == saved_before, "P6 save: Rejected command never rewrites a good save")


func _faults() -> void:
	var path := directory.path_join("fault.json")
	var session := Session.new()
	session.new_run(1)
	var manager := FaultSave.new(session.content, path)
	_check.call(manager.save_run(session.state()).ok, "P6 save: Fault fixture starts with a valid save")
	var previous := FileAccess.get_file_as_string(path)
	session.buy_shop("herb_lingcao", 1)
	manager.fail_write = true
	var result := manager.save_run(session.state())
	_check.call(not result.ok and result.error_code == "SAVE_WRITE_FAILED" and FileAccess.get_file_as_string(path) == previous and manager.load_run().ok, "P6 save: Partial temporary write failure preserves old primary")
	manager.fail_write = false
	manager.fail_replace = true
	result = manager.save_run(session.state())
	_check.call(not result.ok and result.error_code == "SAVE_REPLACE_FAILED" and FileAccess.get_file_as_string(path) == previous and FileAccess.file_exists(path + ".bak"), "P6 save: Rename failure preserves old primary and valid backup")
	manager.fail_replace = false
	manager.fail_backup = true
	result = manager.save_run(session.state())
	_check.call(not result.ok and result.error_code == "SAVE_BACKUP_FAILED" and FileAccess.get_file_as_string(path) == previous, "P6 save: Backup replacement failure cannot replace the primary")
	manager.fail_backup = false
	manager.corrupt_after_replace = true
	result = manager.save_run(session.state())
	_check.call(not result.ok and result.error_code == "SAVE_VERIFY_FAILED" and manager.load_run().ok and manager.load_run().result.state.spirit_stones == 200, "P6 save: Post-replacement corruption restores the previous valid backup")
	_check.call(manager.save_run(session.state()).ok and manager.load_run().result.state.spirit_stones == 196, "P6 save: Retry after failure writes the actual current state")
	_write(path, "truncated")
	var recovered := manager.load_run()
	_check.call(recovered.ok and recovered.result.recovered and recovered.result.state.spirit_stones == 200, "P6 save: Corrupt primary falls back to known-good previous revision")
	var backup_before := FileAccess.get_file_as_string(path + ".bak")
	_check.call(manager.save_run(session.state()).ok and FileAccess.get_file_as_string(path + ".bak") == backup_before, "P6 save: Saving after recovery never backs up a corrupt primary over the good backup")
	var malformed := session.state()
	malformed.spirit_stones = -1
	previous = FileAccess.get_file_as_string(path)
	_check.call(not manager.save_run(malformed).ok and FileAccess.get_file_as_string(path) == previous, "P6 save: Invalid runtime state is rejected before writing any primary bytes")
	# Unsupported and corrupt files without backup must not mutate the session or disk.
	var invalid_path := directory.path_join("invalid.json")
	var invalid := Session.new(invalid_path)
	var envelope: Dictionary = JSON.parse_string(previous)
	for kind in ["version", "engine", "checksum", "payload", "state", "history"]:
		var changed := envelope.duplicate(true)
		if kind == "version": changed.schema_version = 999
		if kind == "engine": changed.engine_version = "4.6"
		if kind == "checksum": changed.checksum = "bad"
		if kind == "payload": changed.payload = "[]"; changed.checksum = changed.payload.sha256_text()
		if kind == "state":
			var payload: Dictionary = JSON.parse_string(changed.payload)
			payload.run.pending_talent_rank = 9
			changed.payload = JSON.stringify(payload)
			changed.checksum = changed.payload.sha256_text()
		if kind == "history":
			var payload: Dictionary = JSON.parse_string(changed.payload)
			payload.history = [{"snapshot": {"recipe_id": "recipe_juling"}, "success": false, "new_quality": false, "quality": 1, "quantity": 0, "exp_gained": 3, "research_gained": 1, "consumed": {}, "returned": {}}]
			changed.payload = JSON.stringify(payload)
			changed.checksum = changed.payload.sha256_text()
		_write(invalid_path, JSON.stringify(changed))
		var bytes_before := FileAccess.get_file_as_bytes(invalid_path)
		_check.call(not invalid.load_run().ok and not invalid.has_run() and bytes_before == FileAccess.get_file_as_bytes(invalid_path), "P6 save: Bad " + kind + " does not create starter state or overwrite evidence")
	_write(invalid_path + ".bak", "bad backup")
	_check.call(not invalid.load_run().ok and not invalid.has_run(), "P6 save: Two corrupt files return a readable failure without silently starting over")
	var failure_path := directory.path_join("disabled.json")
	var failed := Session.new(failure_path)
	failed._saves = FaultSave.new(failed.content, failure_path)
	failed._saves.fail_write = true
	_check.call(failed.new_run(1).ok and not failed.save_status.ok and failed.state().needs_save, "P6 save: Autosave failure is exposed while committed gameplay remains dirty and recoverable")


func _roundtrip_progress() -> void:
	var report := Route.new().run("research", 3, false)
	if not report.ok:
		_check.call(false, "P6 save: Reachable talent checkpoint could not be prepared")
		return
	var session: RefCounted = report.session
	var path := directory.path_join("progress.json")
	var manager := Saves.new(session.content, path)
	_check.call(manager.save_run(session.state(), session.history()).ok, "P6 save: Talent checkpoint writes run and recent history")
	var loaded := Session.new(path)
	_check.call(loaded.load_run().ok and loaded.state().pending_talent_rank == 3 and loaded.progression().result.talents.size() == 3 and loaded.history().size() == session.history().size(), "P6 save: Pending milestone choice and history survive restart")
	loaded.choose_talent("talent_research_3")
	var again := Session.new(path)
	_check.call(again.load_run().ok and again.state().talent_choices == ["talent_research_3"] and again.state().pending_talent_rank == 0, "P6 save: Talent selection is persistent and cannot be selected a second time")
	var route := Route.new().run()
	session = route.session
	_check.call(route.ok and manager.save_run(session.state(), session.history()).ok, "P6 save: Actual completed route writes its ending checkpoint")
	_check.call(again.load_run().ok and again.state().ending == session.state().ending and again.collection().result.discovered == session.collection().result.discovered and State.new(again.content).validate(again.state()).ok, "P6 save: Ending, immutable statistics, discoveries and independent RNG survive disk round trip")
