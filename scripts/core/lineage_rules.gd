class_name LineageRules
extends RefCounted
## Pure runtime transforms. Static data is validated; no previews consume RNG.
const QUALITIES := ["common", "good", "superior", "legendary"]


static func valid_ids(db: RefCounted, state: Dictionary) -> bool:
	for pair in [["equipped_inheritances", "inheritances", 2], ["world_modifiers", "world_modifiers", 2]]:
		var ids: Variant = state.get(pair[0], [])
		if not ids is Array or ids.size() > pair[2]:
			return false
		var seen: Array = []
		for id in ids:
			if not id is String or id not in db.get_ids(pair[1]) or seen.has(id):
				return false
			seen.append(id)
	var worlds: Array = state.get("world_modifiers", [])
	for id in worlds:
		for other in worlds:
			if other in db.get_item(id).exclusive_with:
				return false
	return true


static func inheritance(db: RefCounted, state: Dictionary, effect: String) -> float:
	var amount := 0.0
	for id in state.get("equipped_inheritances", []):
		var item: Dictionary = db.get_item(id)
		if item.effect == effect:
			amount += item.amount
	return amount


static func world(db: RefCounted, state: Dictionary, field: String, fallback: Variant = 0.0) -> Variant:
	for id in state.get("world_modifiers", []):
		var item: Dictionary = db.get_item(id)
		if item.changes.has(field):
			return item.changes[field]
	return fallback


static func alchemy(db: RefCounted, state: Dictionary, recipe: Dictionary, setup: Dictionary) -> Dictionary:
	var world_bonus: float = world(db, state, "success_bonus")
	var transfer := 0.0
	if "fire" in recipe.tags:
		world_bonus += world(db, state, "fire_success_bonus")
		transfer += world(db, state, "fire_legendary_transfer")
	if setup.flame_id == "flame_normal":
		world_bonus += world(db, state, "normal_flame_success")
	var heritage_bonus := inheritance(db, state, "basic_furnace_success") if setup.furnace_id == "furnace_basic" else 0.0
	if setup.strategy == "rush":
		var rushed := inheritance(db, state, "rush_transfer")
		heritage_bonus -= rushed * 0.01
		transfer += rushed
	return {"world_success": world_bonus, "heritage_success": heritage_bonus, "legendary_transfer": transfer, "suppress_flame": world(db, state, "suppress_special_flames", false) and setup.flame_id != "flame_normal", "base_research": int(world(db, state, "research_per_attempt")), "discovery_research": int(inheritance(db, state, "discovery_research"))}


static func buy_price(db: RefCounted, state: Dictionary, item: Dictionary, price: int) -> int:
	if item.get("category") == "herb":
		return int(ceil(price * float(world(db, state, "herb_buy_multiplier", 1.0))))
	return price


static func sell_price(db: RefCounted, state: Dictionary, id: String, price: int) -> int:
	if id == "material_danzha":
		var multiplier := inheritance(db, state, "residue_multiplier")
		if multiplier > 0:
			return int(price * multiplier)
	return price


static func quest(db: RefCounted, state: Dictionary, template: Dictionary) -> Dictionary:
	var result := template.duplicate(true)
	var first := true
	for instance in state.quest_instances.values():
		if instance.template_id == template.id and instance.status == "completed":
			first = false
	var stones: int = template.reward_spirit_stones
	if template.id == "quest_juling_supply" and first:
		stones += int(inheritance(db, state, "first_quest_stones"))
	result.reward_spirit_stones = int(floor(stones * float(world(db, state, "quest_stones_multiplier", 1.0))))
	var shift := int(world(db, state, "quest_quality_shift")) if template.id != "quest_juling_supply" else 0
	shift -= int(inheritance(db, state, "quest_quality"))
	result.min_quality = QUALITIES[clampi(QUALITIES.find(template.min_quality) + shift, 0, 3)]
	return result


static func option(db: RefCounted, state: Dictionary, event_id: String, source: Dictionary) -> Dictionary:
	var option := source.duplicate(true)
	if event_id == "event_earth_fire" and option.id == "choice_ritual":
		option.cost_stones = int(ceil(option.cost_stones * (1.0 - inheritance(db, state, "ritual_discount"))))
	var bonus := int(world(db, state, "exploration_herb_bonus"))
	if bonus > 0:
		for field in ["success_items", "failure_items"]:
			for id in option[field]:
				if db.get_item(id).get("category") == "herb":
					option[field][id] += bonus
	return option
