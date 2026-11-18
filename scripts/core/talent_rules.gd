class_name TalentRules
extends RefCounted
## Pure validation shared by alchemy and complete run-state validation.

static func valid_choices(db: RefCounted, state: Dictionary) -> bool:
	var choices: Variant = state.get("talent_choices", [])
	if not choices is Array:
		return false
	var groups: Array = []
	for id in choices:
		if not id is String or id not in db.get_ids("talents"):
			return false
		var talent: Dictionary = db.get_item(id)
		if talent.choice_rank > state.rank or groups.has(talent.choice_rank):
			return false
		groups.append(talent.choice_rank)
	return true


static func definitions(db: RefCounted, state: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in state.get("talent_choices", []):
		found.append(db.get_item(id))
	return found
