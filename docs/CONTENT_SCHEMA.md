# 静态内容格式与接口（P1～P8）

适用于 Godot `4.5.stable.official.876b29033`，内容格式版本 `schema_version: 1`。内容库只定义并校验静态内容，交易、炼丹与资源结算分别由业务服务执行。原始设计文档不变，未定数值的首批配置记录在 BALANCE.md。

## 文件和通用字段

固定读取 `data/recipes.json`、`materials.json`、`furnaces.json`、`flames.json`、`consumables.json`、`quests.json`、`exploration_events.json`、`ranks.json`、`talents.json`、`inheritances.json`、`world_modifiers.json` 十一张表，全部必需。每张表格式为：

```json
{"schema_version": 1, "items": [{"id": "recipe_example"}]}
```

上例仅展示封套；条目仍须提供完整字段。空表、缺表、未知表、未知字段、不支持的版本和错误类型均不接受。验证器不会将错误值自动修正为有效配置。

所有条目必填：

| 字段 | 约束 |
|---|---|
| `id` | 全局唯一，正则 `^[a-z][a-z0-9]*(_[a-z0-9]+)+$`；不使用中文名称做索引 |
| `name`、`description` | 非空字符串；面向玩家使用中文 |
| `tier` | 整数 1～9 |
| `tags` | 不重复的非空字符串组成的数组；标签格式 `^[a-z][a-z0-9_]*$`，允许空数组 |
| `unlock` | 下表中一种条件；仅描述后续解锁，P1 不发放任何内容 |

| `unlock.type` | 其余必填字段 |
|---|---|
| `initial` | 无 |
| `rank` | `required_rank` |
| `shop` | `required_rank`、`price` |
| `exploration` | `required_rank` |

`required_rank` 的范围为整数 0～10（丹童至大宗师）。`price` 为非负整数。`exploration` 表示获取类别及资格；P5 的具体事件、确定性获取路径见 `exploration_events.json`，不执行任意脚本。

价格与数量上限统一为 `2147483647`。此边界保证单项整数能安全转换，不代表后续批量交易可忽略乘法/累计上限校验。JSON 数字被 Godot 解析为浮点数：验证器接受数值为整数的浮点数，拒绝小数、布尔值、数值字符串、NaN 与无穷；ContentDB 校验通过后把整数语义字段转换为 `int`，不修改传入原文档。

## 丹方

除通用字段外，必填：

| 字段 | 约束 |
|---|---|
| `required_rank` | 整数 0～10，表示可炼制品阶 |
| `base_success_rate` | 有限数值 [0,1]，此处存基础值；5%～95% 最终限幅在 P3 计算 |
| `materials` | 非空对象，材料 ID → 正整数数量；所有引用须存在于材料表 |
| `quality_weights` | 恰好 `common`、`good`、`superior`、`legendary` 四项；每项有限且非负，总和为有限正数；不要求总和为 100 |
| `base_sell_price` | 非负整数，凡品丹药售价基数，区别于丹方购买价 `unlock.price` |
| `special_rules` | 效果 ID 数组；P1 尚无已注册处理器，必须为空 |

解锁资格和可炼制资格是不同字段，P1 分别校验其格式和范围，不执行资格判断，也不将二者强行设为同一值。

## 材料

除通用字段外，必填：

| 字段 | 约束 |
|---|---|
| `category` | `herb`、`mineral`、`beast`、`spirit` 之一 |
| `buy_price`、`sell_price` | 非负整数；可购材料卖价不得高于买价 |
| `shop_available` | 布尔值，须与 `sources` 是否包含 `shop` 一致 |
| `sources` | 非空、不重复数组；允许 `shop`、`forage`、`exploration`、`quest`、`research`，P3 新增 `alchemy` 来源用于丹渣 |
| `repeatable` | 布尔值，描述是否能重复获取 |

不可购材料的 `buy_price: 0` 是非售卖占位值，不表示可免费购买。是否允许购买必须结合 `shop_available`，由 P2 服务校验。

## 丹炉、异火与消耗品

三类共用以下必填修正字段，丹炉/异火购买价如有则放在 `unlock.price`：

| 字段 | 约束 |
|---|---|
| `success_bonus` | 有限数值 [-1,1]，表示百分点加法修正；负值合法 |
| `quality_transfers` | 目标品质 → 非负有限权重点数；目标仅为 `good`、`superior`、`legendary`，允许空对象，总和须有限 |
| `material_refund_bonus` | 有限数值 [0,1]，表示返还率加法修正 |
| `extra_pill_chance` | 有限数值 [0,1] |
| `effect_tags` | 与 `tags` 相同的数组格式；空表示通用，非空表示丹方含任一指定标签时应用这件装备的修正 |
| `effect_ids` | P1 必须为空；未知效果 ID 或脚本字符串均拒绝 |

P8 允许三类装备添加可选 `effect_strategy`：仅接受 `normal`、`stable`、`rush`，省略时不限制策略。该条件与 `effect_tags` 同时满足才激活该件装备的全部修正；非匹配策略不触发成功、品质、回收或多丹。

`quality_transfers` 描述从低品质向目标品质转移的请求量，而非向总权重直接加值。P3 已实现并验证固定顺序、下位品质补足与不足截至可用量，详见 ALCHEMY_API.md。内容验证器仍只验证结构、目标和有限非负点数，不将所有构筑组合的运行态计算放在静态验证器中。

消耗品另须包含 `effect_category`（`success` / `quality` / `refund`）、`shop_available`（须与 `unlock.type == shop` 一致）、`sell_price`（非负整数，可购商品卖价不得高于 `unlock.price`）。MVP 的每炉数量限制在 P3 实现，不在内容库中管理玩家库存。

## P5 委托与探索

`quests` 除通用字段外必填：`required_recipe_id`（存在的丹方 ID）、`min_quality`（四档品质）、`quantity`（正整数）、`reward_spirit_stones` / `reward_exp`（非负整数）、`reward_items`（物品数量映射，可空）、`reward_flame`（存在的异火 ID 或空字符串）、`repeatable`（布尔）。`unlock` 必须使用带 `required_rank` 的 `rank` 条件。接取还要求已习得所需丹方。

`exploration_events` 除通用字段外必填 `weight`（有限数值 0.000001～2147483647）和非空 `options` 数组；`unlock` 必须使用 `rank` 条件。权重在当前境界可进入的地点中归一化，指定地点不抽取权重。

每个 option 必须提供以下字段：

| 字段 | 约束 |
|---|---|
| `id` | 英文下划线格式，同一事件内唯一 |
| `name` / `description` | 非空中文说明 |
| `cost_stones` / `success_stones` / `failure_stones` | 非负整数 |
| `cost_items` / `success_items` / `failure_items` | 物品 ID → 正整数，可空对象 |
| `success_rate` | 有限数值 [0,1]，独立于炼丹 5%～95% 限幅 |
| `reward_flame` | 成功时发放的异火 ID 或空字符串 |

P7 另允许可选 `required_heritage`（有效传承 ID 或空字符串）、`reward_furnace`（有效丹炉 ID 或空字符串）。前者控制选项资格，后者是成功后的独立永久装备奖励，不混入材料堆叠。未携带所需传承返回 OPTION_LOCKED；重复拥有奖励丹炉不叠加份数。P8 另允许布尔 `requires_unowned_reward`。为 true 时必须 `success_rate == 1`，且 reward_flame / reward_furnace 恰有一个非空有效引用。已持有该奖励时在收费前返回 REWARD_ALREADY_OWNED；全部选项完成的地点返回 EVENT_EXHAUSTED，并移出随机池。完成状态由本世装备所有权推导，轮回后重置；省略或 false 保留可重复事件行为。其他未知字段仍拒绝。

全部奖励/消耗物品映射只允许存在的材料或消耗品，不允许丹方、装备或任意脚本作为堆叠物品。数量、金额和经验不超过统一整数上限；加载后规范化为运行时 int。所有引用验证通过才替换缓存，非法事件不影响此前可用内容。委托实例和待处理秘境属于运行状态，不写入静态定义。

## P6 品阶和天赋

两表均保留通用字段，`unlock.type` 必须为 `rank`，数值字段校验后转换为 int。

`ranks` 另含：`rank_index`（0～10，每个序号唯一且完整）、`exp_required`（非负整数，按品阶不递减）、`exam_recipe_id`（存在的考核丹方，丹童条目为空）、`min_quality`（四档之一）、`quantity`、`research_cost`（非负整数，晋升条目必须为正）、`required_quest_id` / `required_flame`（存在的引用或空字符串）。考核丹方的炼制/解锁境界必须在晋升前可达，避免晋升所需丹方反而锁在晋升后。当前研制每次产一枚考核品质丹药，认证按 quantity 扣丹。

`talents` 另含：`choice_rank`（3 / 6 / 9，须与 unlock.required_rank 一致）、`style`（stable / rush / research）、`success_bonus`（[-1,1]）、`material_refund_bonus`（[0,1]）、`legendary_transfer`（[0,100]）、`research_discount`（[0,0.5]）、`substitution_ratio`（整数 0～10）。修正必须有限；每阶段恰好三项且三类各一，禁止缺选项或重复流派。仅已选天赋参与运行，具体激活策略和研制成本规则见 P6_PROGRESSION.md。

## P7 传承与天地变数

两表均保留通用字段，`unlock.type` 使用 `rank`；实际跨世资格还按以下周目字段判断。不能通过 JSON 注入脚本或任意表达式。

`inheritances` 必填 `effect`、`amount`、`min_completed_runs`（整数 1～2147483647）。注册效果为 discovery_research、basic_furnace_success、ritual_discount、first_quest_stones、rush_transfer、residue_multiplier、furnace_trace、quest_quality、shortage_supply。同一效果只能定义一次，避免多项传承隐式重复叠加。basic_furnace_success、ritual_discount 的 amount 为有限 [0,1]；其余为整数 1～100。整数语义加载后规范化。

`world_modifiers` 必填：

| 字段 | 约束 |
|---|---|
| `weight` | 有限数值 0.000001～2147483647 |
| `min_run_number` | 整数 2～2147483647 |
| `opportunity` | 布尔，标记机会规则 |
| `exclusive_with` | 不重复 ID 数组，不可引用自己，冲突必须双向声明 |
| `changes` | 非空对象，只接受下述注册字段 |

changes 中 success_bonus、fire_success_bonus、normal_flame_success 为有限 [-1,1]；herb_buy_multiplier、quest_stones_multiplier 为有限 [1,2]；exploration_herb_bonus、fire_legendary_transfer、quest_quality_shift、research_per_attempt 为整数 0～10；suppress_special_flames 为布尔。相容的两条世界不能重复定义同一修正字段，避免依赖数组顺序决定覆盖。必须存在第二世可用且至少含一条机会规则的相容组合。

当前共 12 丹方、9 材料、3 丹炉、2 异火、3 消耗品、5 委托、5 事件、11 品阶、9 天赋、9 传承、6 变数，合计 74 条。原有丹方价格与基础概率不变；P7 候选效果见 BALANCE.md，生成规则见 P7_REBIRTH.md。

## ContentDB 与诊断

ContentDB 为 `RefCounted` 类，路径 `scripts/core/content_db.gd`；由业务协调方显式持有并注入服务，P1 不添加未被界面使用的 Autoload。

```gdscript
const Database = preload("res://scripts/core/content_db.gd")
var db = Database.new()
var loaded = db.load_directory() # 默认 res://data
if loaded.ok:
    var recipe = db.get_item("recipe_juling")
    var materials = db.get_items("materials")
else:
    print(loaded.errors)
```

- `load_directory(directory)`：读十一个文件并解析，随后调用验证器。
- `load_documents(documents)`：接收分类 → 原始 JSON 文档的对象，可用于配置工具和测试。
- `has_item(id)`、`get_item(id)`、`get_ids(category)`、`get_items(category)`、`get_counts()`：不改变状态；未知 ID 或分类返回空结果；分类列表保留 JSON 顺序。
- 加载成功返回 `{ok: true, errors: [], counts: {...}}`，失败返回 `{ok: false, errors: [...]}`。
- 任一文件、字段或引用失败，均保留上一次完整有效缓存；首次失败保持空库。成功重载会替换旧索引。
- 缓存不保存调用方的可变引用，所有查询返回深副本或新建集合。
- `ContentValidator.validate_documents(documents)` 是纯校验，返回含 `code`、`path`、中文 `message` 的错误数组。路径如 `recipes.items[0].materials.herb_missing`；文件解析错误另含文件路径和 Godot JSON 的 `line` 字段。
- 内容库不管理玩家资源、不消耗 RNG、不执行配置中的任意代码。

## 命令行

```sh
# 校验项目配置，合法时返回 0，非法时打印诊断并返回 1
godot --headless --path . --script res://tools/validate_content.gd

# 校验另一份完整配置目录
godot --headless --path . --script res://tools/validate_content.gd -- /absolute/content/directory

# 仅跑内容测试，或移除末尾参数运行包含菜单检查的完整测试
godot --headless --path . --script res://tests/test_runner.gd -- --content-only
```

后续导出游戏时须将 `data/*.json` 作为非资源文件纳入导出包；P1 未配置或验证发布导出。
