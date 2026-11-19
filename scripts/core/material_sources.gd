extends RefCounted
## Pure discovery of repeatable, guaranteed cash-only sources. Never enters events.
const Lineage := preload("res://scripts/core/lineage_rules.gd")

static func entries(db: RefCounted, state: Dictionary, item_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if item_id not in db.get_ids("materials"): return rows
	for event in db.get_items("exploration_events"):
		for source in event.options:
			if source.success_rate != 1 or not source.cost_items.is_empty() or source.success_stones != 0: continue
			if source.get("requires_unowned_reward", false) or not source.get("reward_flame", "").is_empty() or not source.get("reward_furnace", "").is_empty(): continue
			if not source.success_items.has(item_id): continue
			var option := Lineage.option(db, state, event.id, source)
			var heritage: String = source.get("required_heritage", "")
			rows.append({"event_id": event.id, "event_name": event.name, "option_id": option.id, "option_name": option.name, "required_rank": event.unlock.required_rank, "cost_stones": option.cost_stones, "quantity": option.success_items[item_id], "unlocked": state.rank >= event.unlock.required_rank and (heritage.is_empty() or heritage in state.get("equipped_inheritances", []))})
	return rows

static func cheapest(db: RefCounted, state: Dictionary, item_id: String) -> Dictionary:
	var best: Dictionary = {}
	for row in entries(db, state, item_id):
		if not row.unlocked: continue
		if best.is_empty() or float(row.cost_stones) / row.quantity < float(best.cost_stones) / best.quantity:
			best = row
	return best
