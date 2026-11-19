extends RefCounted
## Public commands acquire, brew, and discover every new recipe at its rank gate.
const GearRoute := preload("res://tests/helpers/equipment_route.gd")
const Model := preload("res://tools/balance/catalog_model.gd")
const Sources := preload("res://scripts/core/material_sources.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
var gear := GearRoute.new()
var error := ""
var records: Array[Dictionary] = []
var checkpoints: Dictionary = {}

func run(stop_at: int = 10) -> Dictionary:
	var result := gear.driver.run("stable", stop_at, true, null, _milestone)
	return {"ok": result.ok and error.is_empty(), "error": error if not error.is_empty() else result.error, "session": gear.driver.session, "records": records.duplicate(true), "checkpoints": checkpoints.duplicate(true)}

func _milestone(rank_value: int) -> bool:
	if not gear._milestone(rank_value):
		error = gear.error
		return false
	# Rank zero side recipe is acquired after the first certification as an optional purchase.
	for source in Model.proposal().recipes:
		if source.required_rank != rank_value and not (source.required_rank == 0 and rank_value == 1): continue
		var recipe: Dictionary = gear.driver.session.content.get_item(source.id)
		if not gear._fund(recipe.unlock.price) or not _accept(gear.driver.session.buy_shop(recipe.id, 1)): return false
		var attempts := 0
		var succeeded := false
		while attempts < 64:
			if not ensure_items(recipe.materials): return false
			if rank_value == 2 and recipe.id == "recipe_gushen" and attempts == 0:
				checkpoints["before_gushen"] = _point()
			var session: RefCounted = gear.driver.session
			var receipt: Dictionary = session.begin_brew(recipe.id, Model.setup(session.state(), recipe, "stable"))
			if not _accept(receipt) or not _accept(session.finish_brew()): return false
			attempts += 1
			if receipt.result.success:
				succeeded = true
				records.append({"recipe": recipe.id, "rank": rank_value, "attempts": attempts, "quality": receipt.result.quality, "quantity": receipt.result.quantity, "unlock_price": recipe.unlock.price})
				break
		if not succeeded:
			error = "Recipe demonstration exceeded 64 attempts: " + recipe.id
			return false
		if gear.driver.session.quote_products().ok and not _accept(gear.driver.session.sell_products()): return false
	checkpoints[rank_value] = _point()
	return true

func ensure_items(costs: Dictionary) -> bool:
	var session: RefCounted = gear.driver.session
	# Reserve an entire batch before purchases; funding cannot consume the new rare materials.
	var budget := 0
	for id in costs:
		var item: Dictionary = session.content.get_item(id)
		var missing: int = maxi(costs[id] - session.state().inventory.get(id, 0), 0)
		if item.shop_available:
			budget += Lineage.buy_price(session.content, session.state(), item, item.buy_price) * missing
		else:
			var source := Sources.cheapest(session.content, session.state(), id)
			if source.is_empty():
				error = "No unlocked deterministic source: " + id
				return false
			budget += int(ceil(float(missing) / source.quantity)) * source.cost_stones
	if not gear._fund(budget):
		error = gear.error
		return false
	for id in costs:
		var item: Dictionary = session.content.get_item(id)
		while session.state().inventory.get(id, 0) < costs[id]:
			var missing: int = costs[id] - session.state().inventory.get(id, 0)
			if item.shop_available:
				if not _accept(session.buy_shop(id, missing)): return false
			else:
				var source := Sources.cheapest(session.content, session.state(), id)
				var entered: Dictionary = session.enter_event(source.event_id)
				if not _accept(entered) or not _accept(session.resolve_event(entered.result.instance_id, source.option_id)): return false
	return true

func _point() -> Dictionary:
	var session: RefCounted = gear.driver.session
	return {"state": session.state(), "meta": session.meta(), "history": session.history()}

func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok
