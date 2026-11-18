class_name StateTransaction
extends RefCounted
## Trusted service primitive. Callers validate their complete candidate first.

const Result := preload("res://scripts/core/transaction_result.gd")


static func commit(state: Dictionary, candidate: Dictionary, fields: Array, payload: Dictionary = {}) -> Dictionary:
	var next := candidate.duplicate(true)
	var changes: Dictionary = {}
	for field in fields:
		if state[field] != next[field]:
			changes[field] = {"before": state[field], "after": next[field]}
	var receipt := Result.success(changes, payload)
	for field in changes:
		state[field] = next[field]
	return receipt
