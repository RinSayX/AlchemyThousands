extends SceneTree
## Disposable P2 demonstration. Does not load/write player saves or use RNG.

const Database := preload("res://scripts/core/content_db.gd")
const Economy := preload("res://scripts/services/economy_service.gd")
const Inventory := preload("res://scripts/services/inventory_service.gd")
const Shop := preload("res://scripts/services/shop_service.gd")


func _initialize() -> void:
	var db := Database.new()
	if not _show(db.load_directory(), "加载配置"):
		return
	var economy := Economy.new(db)
	var created := economy.create_economy_state()
	if not _show(created, "创建临时经济状态"):
		return
	var state: Dictionary = created.result.state
	var shop := Shop.new(db)
	var inventory := Inventory.new(db)
	var cart := [{"item_id": "herb_lingcao", "quantity": 2}, {"item_id": "herb_qinghua", "quantity": 1}]
	var quote := shop.quote_buy(state, cart)
	if not _show(quote, "购买报价"):
		return
	print("初始灵石：", state.spirit_stones, "；灵草×2＋青花×1 报价：", quote.result.total)
	if not _show(shop.buy_batch(state, cart, "demo-buy"), "批量购买"):
		return
	print("购买后：", state.spirit_stones, " 灵石；背包：", state.inventory)
	var repeated := shop.buy_batch(state, cart, "demo-buy")
	if repeated.ok or repeated.error_code != "ACTION_DUPLICATE":
		printerr("重复提交防护未生效。")
		quit(1)
		return
	print("重复提交被拒绝：", repeated.error_code, "；余额仍为 ", state.spirit_stones)
	print("以下丹药由演示脚本注入，用于验证售丹；尚未实现炼丹。")
	if not _show(inventory.add_pill(state, "recipe_juling", "good", 1, "demo-pill-fixture"), "注入演示丹药"):
		return
	var sold := shop.sell_pill(state, "recipe_juling", "good", 1, "demo-sell")
	if not _show(sold, "出售良品聚灵丹"):
		return
	print("售出良品聚灵丹×1，收入 ", sold.result.total, " 灵石；最终余额：", state.spirit_stones)
	quit(0)


func _show(result: Dictionary, action: String) -> bool:
	if result.ok:
		return true
	printerr("%s失败：%s" % [action, result])
	quit(1)
	return false
