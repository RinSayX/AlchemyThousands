class_name PillStack
extends RefCounted
## P2 supports the four ordinary qualities; mutation definitions arrive later.

const QUALITIES := ["common", "good", "superior", "legendary"]


static func key(recipe_id: String, quality: String) -> String:
	return recipe_id + "|" + quality + "|"


static func create(recipe_id: String, quality: String, quantity: int) -> Dictionary:
	return {"recipe_id": recipe_id, "quality": quality, "mutation_id": "", "quantity": quantity}
