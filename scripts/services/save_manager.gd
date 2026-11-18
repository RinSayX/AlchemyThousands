class_name SaveManager
extends RefCounted
## Versioned run envelope. Temporary write/readback, validated backup, rename.

const State := preload("res://scripts/core/progression_state.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const Result := preload("res://scripts/core/transaction_result.gd")
const SCHEMA := 1
const MAX_BYTES := 16 * 1024 * 1024
var path: String
var _state: State


func _init(content: RefCounted, save_path: String) -> void:
	_state = State.new(content)
	path = save_path


func load_run() -> Dictionary:
	var primary := _read(path)
	if primary.ok:
		primary.result["recovered"] = false
		return primary
	var backup := _read(path + ".bak")
	if backup.ok:
		backup.result["recovered"] = true
		backup.result["warning"] = "主存档不可用，已读取上一份有效备份。"
		return backup
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return Result.failure("NO_SAVE", "尚无修行存档。")
	return Result.failure(primary.error_code, "存档与备份均无法读取：" + primary.message)


func save_run(state: Dictionary, history: Array = []) -> Dictionary:
	var checked := _validate_payload({"run": state, "history": history})
	if not checked.ok:
		return checked
	var run := state.duplicate(true)
	run.needs_save = false
	var payload := JSON.stringify({"run": run, "history": history})
	var envelope := {"schema_version": SCHEMA, "engine_version": Context.ENGINE_VERSION, "saved_at": Time.get_datetime_string_from_system(true), "payload": payload, "checksum": payload.sha256_text()}
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		return Result.failure("SAVE_WRITE_FAILED", "无法建立存档目录：" + error_string(directory_error))
	var error := _write_file(path + ".tmp", JSON.stringify(envelope))
	if error != OK or not _read(path + ".tmp").ok:
		return Result.failure("SAVE_WRITE_FAILED", "存档临时写入或读回校验失败，原存档保留。")
	# A corrupt primary must never replace a good backup.
	if _read(path).ok:
		error = DirAccess.copy_absolute(absolute, absolute + ".bak.tmp")
		if error != OK or not _read(path + ".bak.tmp").ok:
			return Result.failure("SAVE_BACKUP_FAILED", "备份读回失败，原存档保留。")
		error = _replace(path + ".bak.tmp", path + ".bak")
		if error != OK:
			return Result.failure("SAVE_BACKUP_FAILED", "备份替换失败，原存档保留。")
	error = _replace(path + ".tmp", path)
	if error != OK:
		return Result.failure("SAVE_REPLACE_FAILED", "正式存档替换失败，原存档与备份保留。")
	if not _read(path).ok:
		# Restore through a temporary file if post-replacement verification fails.
		if _read(path + ".bak").ok:
			if DirAccess.copy_absolute(absolute + ".bak", absolute + ".restore.tmp") == OK:
				_replace(path + ".restore.tmp", path)
		return Result.failure("SAVE_VERIFY_FAILED", "正式存档校验失败，已尝试恢复有效备份。")
	return Result.success({}, {"saved_at": envelope.saved_at, "path": path})


func _write_file(file_path: String, text: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


func _replace(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))


func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return Result.failure("NO_SAVE", "文件不存在。")
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return Result.failure("SAVE_READ_FAILED", "无法读取文件。")
	if file.get_length() > MAX_BYTES:
		file.close()
		return Result.failure("INVALID_SAVE", "存档文件超过容量限制。")
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return Result.failure("SAVE_READ_FAILED", "存档读取不完整。")
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return Result.failure("INVALID_SAVE", "存档 JSON 不完整（行 %d）。" % parser.get_error_line())
	var envelope: Variant = _normalize(parser.data)
	if not envelope is Dictionary or envelope.size() != 5:
		return Result.failure("INVALID_SAVE", "存档封套不完整。")
	if not Economy.valid_integer(envelope.get("schema_version"), 0) or envelope.schema_version != SCHEMA:
		return Result.failure("UNSUPPORTED_SAVE_VERSION", "此存档版本尚不支持，不会覆盖原文件。")
	if not envelope.get("engine_version") is String or envelope.engine_version != Context.ENGINE_VERSION:
		return Result.failure("ENGINE_MISMATCH", "存档引擎版本与本机锁定版本不同。")
	if not envelope.get("payload") is String or not envelope.get("checksum") is String or not envelope.get("saved_at") is String or envelope.payload.sha256_text() != envelope.checksum:
		return Result.failure("INVALID_SAVE", "存档校验和或保存信息不合法。")
	if parser.parse(envelope.payload) != OK:
		return Result.failure("INVALID_SAVE", "存档内容 JSON 不完整。")
	var data: Variant = _normalize(parser.data)
	var checked := _validate_payload(data)
	if not checked.ok:
		return checked
	return Result.success({}, {"state": data.run, "history": data.history, "saved_at": envelope.saved_at})


func _validate_payload(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size() != 2 or not data.get("run") is Dictionary or not data.get("history") is Array or data.history.size() > 20:
		return Result.failure("INVALID_SAVE", "修行状态或最近记录不完整。")
	var checked := _state.validate(data.run)
	if not checked.ok:
		return checked
	for record in data.history:
		if not record is Dictionary or not record.get("snapshot") is Dictionary or record.snapshot.get("recipe_id") not in _state.db.get_ids("recipes") or not record.get("success") is bool or not record.get("new_quality") is bool:
			return Result.failure("INVALID_SAVE", "炼丹记录引用不合法。")
		if not record.get("quality") is String or not Economy.valid_integer(record.get("quantity"), 0, 2) or (record.success and (record.get("quality") not in Pills.QUALITIES or record.quantity == 0)) or (not record.success and (record.get("quality") != "" or record.quantity != 0)):
			return Result.failure("INVALID_SAVE", "炼丹记录品质或数量不合法。")
		for field in ["exp_gained", "research_gained"]:
			if not Economy.valid_integer(record.get(field), 0):
				return Result.failure("INVALID_SAVE", "炼丹记录奖励不合法。")
		for field in ["consumed", "returned"]:
			if not record.get(field) is Dictionary:
				return Result.failure("INVALID_SAVE", "炼丹记录物品不合法。")
			for id in record[field]:
				if not _state.resources.economy.is_stackable(id) or not Economy.valid_integer(record[field][id], 1):
					return Result.failure("INVALID_SAVE", "炼丹记录物品引用不合法。")
	return Result.success()


func _normalize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= Economy.MAX_VALUE:
		return int(value)
	if value is Dictionary:
		for key in value:
			value[key] = _normalize(value[key])
	elif value is Array:
		for i in range(value.size()):
			value[i] = _normalize(value[i])
	return value
