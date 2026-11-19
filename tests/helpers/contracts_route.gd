extends RefCounted
const Catalog := preload("res://tests/helpers/catalog_route.gd")
const Model := preload("res://tools/balance/contracts_model.gd")
const Policy := preload("res://tools/balance/catalog_model.gd")
var catalog := Catalog.new()
var deliveries: Array[Dictionary] = []
var before_delivery: Dictionary = {}
var error := ""

func run() -> Dictionary:
	catalog.on_recipe_completed = _orders
	var result := catalog.run()
	return {"ok": result.ok and error.is_empty(), "error": error if not error.is_empty() else result.error, "session": result.session, "deliveries": deliveries, "before_delivery": before_delivery}

func _orders(recipe_id: String) -> bool:
	for quest in Model.proposal().quests:
		if quest.required_recipe_id == recipe_id and not _deliver(quest.id): return false
	return true

func _deliver(id: String) -> bool:
	var session: RefCounted = catalog.gear.driver.session
	if not _accept(session.accept_quest(id)): return false
	var quest: Dictionary = session.content.get_item(id)
	var recipe: Dictionary = session.content.get_item(quest.required_recipe_id)
	for attempt in range(256):
		var offer: Dictionary = {}
		for row in session.quest_board().result.rows:
			if row.template.id == id: offer = row
		if offer.delivery.can_deliver:
			if before_delivery.is_empty():
				before_delivery = {"state": session.state(), "meta": session.meta(), "history": session.history()}
			var result: Dictionary = session.deliver_quest(offer.active_id)
			if not _accept(result): return false
			deliveries.append({"quest": id, "rank": session.state().rank, "attempts_after_first_pill": attempt, "stones": result.result.spirit_stones, "items": result.result.items})
			return true
		if not catalog.ensure_items(recipe.materials):
			error = catalog.error
			return false
		if not _accept(session.begin_brew(recipe.id, Policy.setup(session.state(), recipe, "stable"))) or not _accept(session.finish_brew()): return false
	error = "Commission exceeded real furnace bound: " + id
	return false

func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok
