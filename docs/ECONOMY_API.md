# P2 背包与经济接口

适用于本机 Godot `4.5.stable.official.876b29033`。服务均为 RefCounted 实例，由协调方持有；不新增 Autoload，不依赖 Control、场景或 RNG。P2 是内存业务层，主菜单尚未接入真实游戏。

## 初始化与状态

```gdscript
const Database = preload("res://scripts/core/content_db.gd")
const Economy = preload("res://scripts/services/economy_service.gd")
const Shop = preload("res://scripts/services/shop_service.gd")

var db = Database.new()
var loaded = db.load_directory()
if loaded.ok:
    var economy = Economy.new(db)
    var created = economy.create_economy_state()
    if created.ok:
        var state = created.result.state
        var shop = Shop.new(db)
        var purchase = shop.buy_item(state, "herb_lingcao", 2, "purchase-001")
```

`create_economy_state()` 创建独立的经济状态快照：丹童、200 灵石、灵草×5、青花×3、空丹药栏、配置中的初始丹方/丹炉/异火以及空操作记录。它不是完整新周目，也不会创建 RNG、存档或修改现有状态。完整 RunState 由后续协调层组合。

| 状态字段 | 运行时类型与约束 |
|---|---|
| `rank` | int，0～10，P2 只读取、不负责晋升 |
| `spirit_stones` | int，0～2147483647 |
| `inventory` | 材料/消耗品 ID → int 数量，0～2147483647；消耗至零时移除条目 |
| `pills` | 堆叠键 → 丹药对象，数量 1～2147483647；消耗至零时移除条目 |
| `unlocked_recipes` | 已解锁丹方 ID 数组，不重复、引用有效 |
| `owned_furnaces`、`owned_flames` | 对应装备 ID 数组，不重复、引用有效 |
| `completed_actions` | 已提交操作 ID 数组，不重复 |

上述字段均必需，允许存在额外的 RunState 字段。经济服务保留经验、统计、RNG 等额外字段；P3 状态带有 bool 类型的 needs_save 时，成功经济事务将其置 true。P3 的 AlchemyService 已通过共享 StateTransaction 扩展统一结算，具体边界见 ALCHEMY_API.md，普通经济方法仍不提交炼丹成长或 RNG 改动。

运行时数量和金额必须是真正的 `int`，小数、布尔值、数字字符串、NaN/无穷全部拒绝。读取 JSON 存档时的整数恢复/迁移属于后续 SaveManager 的职责，P2 不静默修复输入状态。

## 返回值和事务

业务服务统一返回：

```gdscript
{
    "ok": true,
    "error_code": "",
    "message": "",
    "state_changes": {"spirit_stones": {"before": 200, "after": 192}},
    "result": {}
}
```

成功时 `state_changes` 记录变化字段的前后完整值，`result` 提供报价、交易总价等业务结果。返回内容与实际状态没有可变引用共享。失败时错误码和中文说明非空，`state_changes`、`result` 都为空，原始状态不变。

所有修改方法都要求调用方传入 `action_id`：非空文本、最多 128 字符，每个逻辑操作在本世唯一。成功后写入 `completed_actions`；重复调用返回 `ACTION_DUPLICATE`，即使通过不同服务提交也不能重复结算。校验失败不占用 ID。不同 ID 表示不同的合法购买/奖励；调用方应把同一事件的重试绑定到同一 ID。

服务在单一线程中同步执行，不含 await：先验证原状态和操作 ID，复制候选状态并完成所有核算，验证结果，再提交变化和操作记录。提交前不发布事件，也不写文件。此原子性指内存业务事务，不代表已实现崩溃恢复、跨线程锁或存档事务。

`EconomyService.prepare()` 和 `commit()` 为可信业务服务提供组合事务基础；`commit()` 不能修改境界和既有操作历史。后续委托若同时发放物品和灵石，应组合候选状态后一次提交，而非用同一 ID 分别调用两个修改方法。

## 背包与货币

构造：`EconomyService.new(db)`、`InventoryService.new(db)`。

- `change_stones(state, delta, action_id)`：非零整数加减，支持扣至零；不足或溢出时拒绝。
- `add_items(state, quantities, action_id)` / `consume_items(...)`：`quantities` 为非空的 ID → 正整数对象；整批成功或整批失败。
- `add_pill(state, recipe_id, quality, quantity, action_id, mutation_id = "")` / `consume_pill(...)`：同丹方/品质堆叠，品质仅支持 common、good、superior、legendary。
- `plan_items(state, quantities, remove = false)` / `plan_pill(state, recipe_id, quality, quantity, remove = false, mutation_id = "")`：只生成独立候选状态，返回在 `result.candidate`，不实际提交或消耗 ID，供可信服务组合事务。

普通丹药对象保持设计字段：`recipe_id`、`quality`、`mutation_id`、`quantity`。P2 的无变异堆叠键为 `recipe_id|quality|`，输入 `null` 或空字符串都表示无变异，新增/合并后保存为空字符串。未注册的非空变异 ID 返回 `UNSUPPORTED_MUTATION`，不会被静默按普通丹药出售。

持有和内部奖励不受商店境界限制，因此未来委托可发放稀有材料；商店的购买资格独立验证。P2 的内部增减方法是后续业务服务的基础，不是面向玩家的任意发奖界面。

## 商店

构造：`ShopService.new(db)`。

| 方法 | 内容 |
|---|---|
| `quote_buy(state, lines)` / `quote_sell(state, lines)` | 纯预览；按当前余额、库存、境界检查整单是否可执行，成功返回单价、每行小计、总价、余额变化和交易后余额 |
| `buy_batch(state, lines, action_id)` / `sell_batch(...)` | 重算报价并结算，拒绝任何一行错误；一次购物车记一个操作 ID |
| `buy_item(state, item_id, quantity, action_id)` | 单商品购买，包装批量接口 |
| `sell_item(state, item_id, quantity, action_id)` | 材料/消耗品出售 |
| `sell_pill(state, recipe_id, quality, quantity, action_id, mutation_id = "")` | 指定品质丹药出售 |

购买清单每行恰好包含 `item_id`、`quantity`。出售清单可混合普通物品行和丹药行；丹药行必含 `recipe_id`、`quality`、`quantity`，可选 `mutation_id`。报价/交易清单包含 1～128 行。不接受用户传入的 `unit_price` 等字段，价格以 ContentDB 为准。

重复的可堆叠商品行逐行累计，不会绕过数量限制；同一永久物品重复出现会让整单失败。购买和出售使用独立清单，不用本单售出金额垫付另一笔购买。

购买资格与价格：

- 材料须 `shop_available: true`，解锁类型为 initial/rank/shop，并满足配置的 `required_rank`；价格取 `buy_price`。
- 消耗品须可购且 `unlock.type == shop`；永久丹方/丹炉/异火也须 shop 解锁；价格取 `unlock.price`，均检查境界。
- 永久物品数量只能为 1，重复拥有时拒绝；购买后加入解锁/所有权数组，不自动装备，不赠送丹药。
- `shop_available: false` 的材料即使 `buy_price: 0` 也不可购买；探索火焰、初始物品、晋升奖励不能误作免费商品。
- 普通材料/消耗品按 `sell_price` 出售；出售持有物不受购买境界限制。永久物品不允许出售。

丹药单位售价按设计倍率 1、1.5、2.5、6 计算，**每枚先向下取整，再乘数量**。例如凡品基价 25 的良品单位售价 37，卖 2 枚共 74；批量与逐枚结果一致。普通丹药目前没有变异加价。

所有单价、数量、行小计、清单总价和结算余额都检查上限。先检查单位售价，再乘数量，避免极高基价乘品质倍率和极大数量时发生 int64 溢出。任何溢出都拒绝整个交易，不截断收益、不消耗物品。

## 主要错误码

`INVALID_STATE`、`INVALID_ACTION_ID`、`ACTION_DUPLICATE`、`INVALID_AMOUNT`、`INVALID_QUANTITY`、`INVALID_CART`、`UNKNOWN_ITEM`、`UNKNOWN_RECIPE`、`INVALID_QUALITY`、`UNSUPPORTED_MUTATION`、`RANK_LOCKED`、`NOT_FOR_SALE`、`NOT_SELLABLE`、`ALREADY_OWNED`、`INSUFFICIENT_ITEMS`、`INSUFFICIENT_PILLS`、`NOT_ENOUGH_STONES`、`AMOUNT_OVERFLOW`。

## 演示与检查

```sh
godot --headless --path . --script res://tools/economy_demo.gd
godot --headless --path . --script res://tests/test_runner.gd -- --economy-only
godot --headless --path . --script res://tests/test_runner.gd
```

演示只创建局部状态，展示买材料、拒绝重复提交、测试注入一枚良品丹药并出售的过程，不读取或保存用户进度，也不运行炼丹判定。
