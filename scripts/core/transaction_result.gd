class_name TransactionResult
extends RefCounted


static func success(changes: Dictionary = {}, payload: Dictionary = {}) -> Dictionary:
	return {"ok": true, "error_code": "", "message": "", "state_changes": changes.duplicate(true), "result": payload.duplicate(true)}


static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "message": message, "state_changes": {}, "result": {}}
