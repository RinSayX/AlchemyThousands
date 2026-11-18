class_name ExplorationRules
extends RefCounted
## Shared deterministic interval rules; input definitions are validated content.


static func pick_event(events: Array, draw: float) -> String:
	var total := 0.0
	for event in events:
		total += event.weight
	var threshold := 0.0
	for event in events:
		threshold += event.weight
		if draw * total < threshold:
			return event.id
	return events[-1].id


static func succeeds(probability: float, draw: float) -> bool:
	return draw < probability
