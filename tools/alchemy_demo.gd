extends SceneTree
## Real P3 buy -> brew -> sell loop, using local disposable seeded state.

const Database := preload("res://scripts/core/content_db.gd")
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")


func _initialize() -> void:
	var db := Database.new()
	if not _ok(db.load_directory()):
		return
	var service := Alchemy.new(db)
	var created := service.create_state(20261118)
	if not _ok(created):
		return
	var state: Dictionary = created.result.state
	var shop := Shop.new(db)
	if not _ok(shop.buy_batch(state, [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}], "demo-buy")):
		return
	var preview := service.preview_alchemy(state, "recipe_juling")
	if not _ok(preview):
		return
	print("聚灵丹：成功率 %.1f%%，成功后极品率 %.1f%%，单炉极品率 %.2f%%；材料价值 %d 灵石。" % [preview.result.success_rate * 100, preview.result.quality_probabilities.legendary * 100, preview.result.legendary_per_attempt * 100, preview.result.material_shop_cost])
	var brewed := service.execute_alchemy(state, "recipe_juling", {}, "demo-brew")
	if not _ok(brewed):
		return
	print("真实开炉结果：", brewed.result.success, "；品质：", brewed.result.quality, "；数量：", brewed.result.quantity, "；经验：", brewed.result.exp_gained)
	var sold: Dictionary
	if brewed.result.success:
		sold = shop.sell_pill(state, "recipe_juling", brewed.result.quality, brewed.result.quantity, "demo-sell")
	else:
		sold = shop.sell_item(state, "material_danzha", 1, "demo-sell")
	if not _ok(sold):
		return
	print("出售收入：", sold.result.total, "；余额：", state.spirit_stones, "；行动数：", state.action_count, "；需要保存：", state.needs_save)
	var repeat := service.execute_alchemy(state, "recipe_juling", {}, "demo-brew")
	if repeat.ok or repeat.error_code != "ACTION_DUPLICATE":
		printerr("Duplicate action guard failed")
		quit(1)
		return
	print("再次提交已拒绝：", repeat.error_code)
	quit(0)


func _ok(result: Dictionary) -> bool:
	if result.ok:
		return true
	printerr(result)
	quit(1)
	return false
