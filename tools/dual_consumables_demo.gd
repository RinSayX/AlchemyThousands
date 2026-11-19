extends SceneTree
## Obtains everything through public commands, then buys/brews three paired builds.
const Catalog := preload("res://tests/helpers/catalog_route.gd")
const Saves := preload("res://scripts/services/save_manager.gd")
const Sources := preload("res://scripts/core/material_sources.gd")
var catalog := Catalog.new()
var error := ""

func _initialize() -> void:
	var route: Dictionary = catalog.gear.run(8)
	if not route.ok:
		printerr(route.error)
		quit(1)
		return
	var session: RefCounted = route.session
	var records: Array = []
	for build in [
		{"id": "stable", "recipe": "recipe_juling", "setup": {"furnace_id": "furnace_qingmu", "flame_id": "flame_earth", "strategy": "stable", "consumable_ids": ["consumable_wendan", "consumable_juling"]}},
		{"id": "recovery", "recipe": "recipe_bingxin", "setup": {"furnace_id": "furnace_xuanbing", "flame_id": "flame_hansui", "strategy": "stable", "consumable_ids": ["consumable_bingpo", "consumable_yanjiu"]}},
		{"id": "rush", "recipe": "recipe_niepan", "setup": {"furnace_id": "furnace_jiulong", "flame_id": "flame_zixiao", "strategy": "rush", "consumable_ids": ["consumable_jiuzhuan", "consumable_shuangsheng"], "mutation_id": "mutation_qingling"}}
	]:
		if build.recipe not in session.state().unlocked_recipes:
			var price: int = session.content.get_item(build.recipe).unlock.price
			if not catalog.gear._fund(price) or not _accept(session.buy_shop(build.recipe, 1)): break
		var materials: Dictionary = session.content.get_item(build.recipe).materials
		var budget := 0
		for id in build.setup.consumable_ids: budget += session.content.get_item(id).unlock.price
		for id in materials:
			var item: Dictionary = session.content.get_item(id)
			if item.shop_available: budget += item.buy_price * materials[id]
			else:
				var source := Sources.cheapest(session.content, session.state(), id)
				budget += int(ceil(float(materials[id]) / source.quantity)) * source.cost_stones
		if not catalog.gear._fund(budget): break
		if not catalog.ensure_items(materials):
			error = catalog.error
			break
		var quote: Dictionary = session.quote_consumables(build.setup)
		if not _accept(quote): break
		if not _save(session, "before_" + build.id): break
		if not _accept(session.buy_consumables(build.setup)): break
		var before: Dictionary = session.state()
		var receipt: Dictionary = session.begin_brew(build.recipe, build.setup)
		if not _accept(receipt) or not _accept(session.finish_brew()): break
		for id in build.setup.consumable_ids:
			if session.state().inventory.get(id, 0) != before.inventory.get(id, 0) - 1: error = "Consumable not charged exactly once"
		if not error.is_empty(): break
		records.append({"build": build.id, "recipe": build.recipe, "success": receipt.result.success, "quality": receipt.result.quality, "mutation_id": receipt.result.mutation_id, "consumed": receipt.result.consumed, "research": receipt.result.research_gained})
		if not _save(session, "after_" + build.id): break
	if error.is_empty() and not catalog.gear.error.is_empty(): error = catalog.gear.error
	if not error.is_empty() or records.size() != 3:
		printerr(error if not error.is_empty() else "Incomplete dual consumable route")
		quit(1)
		return
	print("Dual route passed: rank=", session.state().rank, " brews=", session.state().statistics.alchemy_attempts, " actions=", session.state().action_count, " stones=", session.state().spirit_stones, " records=", records)
	quit(0)

func _accept(result: Dictionary) -> bool:
	if not result.ok: error = result.error_code + ": " + result.message
	return result.ok

func _save(session: RefCounted, key: String) -> bool:
	return _accept(Saves.new(session.content, "res://test-output/p8-dual/%s.json" % key).save_run(session.state(), session.history(), session.meta()))
