class_name PillStack
extends RefCounted
## Quality and registered mutation form distinct stack dimensions.

const QUALITIES := ["common", "good", "superior", "legendary"]
const MUTATION_ID := "mutation_qingling"
const MUTATION_RECIPE := "recipe_niepan"


static func key(recipe_id: String, quality: String, mutation_id: String = "") -> String:
	return recipe_id + "|" + quality + "|" + mutation_id


static func create(recipe_id: String, quality: String, quantity: int, mutation_id: String = "") -> Dictionary:
	return {"recipe_id": recipe_id, "quality": quality, "mutation_id": mutation_id, "quantity": quantity}


static func valid_mutation(recipe_id: String, value: Variant) -> bool:
	return value == null or value is String and (value.is_empty() or value == MUTATION_ID and recipe_id == MUTATION_RECIPE)
