class_name AlchemyRules
extends RefCounted
## Pure preview math and the one shared sampling algorithm used by execution.

const Context := preload("res://scripts/core/rng_context.gd")
const QUALITIES := ["common", "good", "superior", "legendary"]
const STRATEGIES := {"normal": 0.0, "stable": 0.10, "rush": -0.15}


static func calculate(recipe: Dictionary, rank: int, furnace: Dictionary, flame: Dictionary, consumable: Dictionary, strategy: String, talents: Array = [], effects: Dictionary = {}) -> Dictionary:
	var weights: Dictionary = recipe.quality_weights.duplicate(true)
	var bonuses := {"base": recipe.base_success_rate, "rank": minf(maxi(rank - recipe.required_rank, 0) * 0.02, 0.10), "furnace": 0.0, "flame": 0.0, "consumable": 0.0, "material": 0.0, "world": 0.0, "strategy": STRATEGIES[strategy]}
	var refund := 0.0
	var extra := 0.0
	var transfers: Array[Dictionary] = []
	var equipment := {"furnace": furnace, "flame": flame, "consumable": consumable}
	for source in ["furnace", "flame", "consumable"]:
		var item: Dictionary = equipment[source]
		if item.get("effect_strategy", strategy) != strategy:
			continue
		if source == "flame" and effects.get("suppress_flame", false):
			continue
		if item.is_empty() or not _matches(item.effect_tags, recipe.tags):
			continue
		bonuses[source] = item.success_bonus
		refund += item.material_refund_bonus
		extra += item.extra_pill_chance
		for target in ["good", "superior", "legendary"]:
			if item.quality_transfers.has(target):
				var amount: float = item.quality_transfers[target]
				transfers.append({"source": source, "target": target, "requested": amount, "applied": transfer_up(weights, target, amount)})
	bonuses.world = effects.get("world_success", 0.0)
	if effects.get("heritage_success", 0.0) != 0.0:
		bonuses["inheritance"] = effects.heritage_success
	if effects.get("legendary_transfer", 0.0) > 0.0:
		transfers.append({"source": "lineage", "target": "legendary", "requested": effects.legendary_transfer, "applied": transfer_up(weights, "legendary", effects.legendary_transfer)})
	for talent in talents:
		if talent.style != strategy:
			continue
		bonuses["talent"] = bonuses.get("talent", 0.0) + talent.success_bonus
		refund += talent.material_refund_bonus
		if talent.legendary_transfer > 0:
			transfers.append({"source": talent.id, "target": "legendary", "requested": talent.legendary_transfer, "applied": transfer_up(weights, "legendary", talent.legendary_transfer)})
	if strategy == "stable":
		var amount := minf(weights.legendary, 1.0)
		weights.legendary -= amount
		weights.common += amount
		transfers.append({"source": "stable", "target": "common", "requested": 1.0, "applied": amount})
	elif strategy == "rush":
		transfers.append({"source": "rush", "target": "legendary", "requested": 5.0, "applied": transfer_up(weights, "legendary", 5.0)})
	var raw := 0.0
	for bonus in bonuses.values():
		raw += float(bonus)
	var total := 0.0
	for quality in QUALITIES:
		total += float(weights[quality])
	var distribution: Dictionary = {}
	for quality in QUALITIES:
		distribution[quality] = float(weights[quality]) / total
	var success := clampf(raw, 0.05, 0.95)
	return {"raw_success_rate": raw, "success_rate": success, "success_breakdown": bonuses, "quality_weights": weights, "quality_probabilities": distribution, "legendary_per_attempt": success * distribution.legendary, "quality_transfers": transfers, "material_refund_rate": clampf(refund, 0, 1), "extra_pill_chance": clampf(extra, 0, 1), "mutation_chance": 0.0}


static func transfer_up(weights: Dictionary, target: String, amount: float) -> float:
	var remaining := amount
	var applied := 0.0
	for donor in QUALITIES:
		if donor == target:
			break
		var moved := minf(float(weights[donor]), remaining)
		weights[donor] -= moved
		weights[target] += moved
		remaining -= moved
		applied += moved
	return applied


static func _matches(required: Array, tags: Array) -> bool:
	if required.is_empty():
		return true
	for tag in required:
		if tags.has(tag):
			return true
	return false


static func roll(snapshot: Dictionary, rng: Context) -> Dictionary:
	if rng.next_float() >= snapshot.success_rate:
		return {"success": false, "quality": "", "quantity": 0, "mutation_id": "", "extra_pill": false}
	var quality := pick_quality(snapshot.quality_weights, rng.next_float())
	var extra: bool = snapshot.extra_pill_chance > 0 and rng.next_float() < snapshot.extra_pill_chance
	return {"success": true, "quality": quality, "quantity": 2 if extra else 1, "mutation_id": "", "extra_pill": extra}


static func pick_quality(weights: Dictionary, draw: float) -> String:
	var total := 0.0
	for quality in QUALITIES:
		total += float(weights[quality])
	var ticket := draw * total
	var threshold := 0.0
	var last_positive := ""
	for quality in QUALITIES:
		if weights[quality] <= 0:
			continue
		last_positive = quality
		threshold += float(weights[quality])
		if ticket < threshold:
			return quality
	return last_positive
