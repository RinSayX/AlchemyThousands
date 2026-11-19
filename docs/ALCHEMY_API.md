# 炼丹引擎接口（P3～P8）

引擎固定为本机 `4.5.stable.official.876b29033`。纯业务炼丹与 UI 分离；GameSession 协调成长、传承、天地变数和保存。

## 接口草图与使用

```gdscript
const Database = preload("res://scripts/core/content_db.gd")
const Alchemy = preload("res://scripts/services/alchemy_service.gd")

var db = Database.new()
var loaded = db.load_directory()
if loaded.ok:
    var service = Alchemy.new(db)
    var created = service.create_state(20261118)
    if created.ok:
        var state = created.result.state
        var setup = {"strategy": "stable"}
        var preview = service.preview_alchemy(state, "recipe_juling", setup)
        var result = service.execute_alchemy(state, "recipe_juling", setup, "furnace-001")
```

- `create_state(seed_value: int)`：在 P2 经济状态上增加炼丹字段，初始化真实 RNG seed/state，返回 `result.state`；只创建独立内存状态，不覆盖现有玩家进度，不执行存档。
- `validate_state(state)`：同时校验经济和炼丹字段。
- `preview_alchemy(state, recipe_id, setup = {})`：纯计算，不读取或抽取 RNG、不消耗资源、不改变存档脏标记。
- `execute_alchemy(state, recipe_id, setup, action_id)`：重新计算并冻结快照，一炉一操作 ID，完整结算后一次提交。

`setup` 仅允许 `furnace_id`、`flame_id`、`consumable_id`、`strategy`。装备默认来自状态的 `equipped_furnace` / `equipped_flame`，消耗品默认为空，策略默认 normal。每炉至多选择一个消耗品 ID；不接受数组、调用方自报概率或额外加成。选择本炉装备不修改永久装备选择。

## 状态与概率

在经济字段之外，必需：

| 字段 | 含义 |
|---|---|
| `exp`、`research_points` | 非负 int，范围沿用 P2 上限 |
| `action_count` | 玩法行动计数，开炉增加 1；普通购买不增加 |
| `statistics` | 必含 alchemy_attempts / alchemy_successes / alchemy_failures，尝试数等于成功＋失败 |
| `alchemy_discoveries` | 本世首次丹方/品质的堆叠键记录，服务用来防止重复发放发现奖励，尚非完整图鉴系统 |
| `equipped_furnace`、`equipped_flame` | 当前装备，须已拥有 |
| `rng_states` | 下节的版本化三流快照 |
| `needs_save` | bool，初始 false，成功提交的开炉、购买/出售等经济事务置 true；预览与被拒绝操作不修改 |

普通材料没有额外纯度加成，材料修正为 0。未注册效果仍由 ContentValidator 拒绝。P7 支持已注册且相容的 world_modifiers 与 equipped_inheritances，未知 ID 显式拒绝；完整存档还由 ProfileState 校验历史所有权、周目与装备栏。talent_choices 经过引用、品阶和每组唯一选择校验，稳丹/冲品天赋只在对应策略激活，研究天赋由 ProgressionService 处理。空传承/世界/天赋维持 P3 概率不变。

成功率按基础、境界熟练、丹炉、异火、符箓、传承、世界、天赋及策略加法求和，最后限幅 5%～95%。境界熟练为超过丹方要求的每阶 +2 个百分点，上限 +10；不满足境界时禁止炼制。天地禁火仅跳过特殊异火修正，不删除异火所有权、不阻断收服或认证。

品质转移顺序：丹炉 → 异火 → 符箓 → 传承/世界 → 天赋 → 策略。每件装备依次处理 good、superior、legendary 目标；从目标以下品质按 common → good → superior 顺序搬移。不足时只转移可用权重，不产生负数或扩充总权重；预览披露请求和实际点数。stable 最后把最多 1 点 legendary 转回 common；rush 最后向 legendary 转移最多 5 点。

normal 无策略修正；stable 成功率 +0.10；rush -0.15。装备 `effect_tags` 为空时通用，非空时丹方含任一标签才应用该装备所有修正。可选 `effect_strategy` 还要求当前策略匹配，否则整件装备的所有修正不激活；未配置该字段保持通用。失败返还率和多丹概率相加后限幅 [0,1]。

预览返回原始/最终成功率与来源、四品质原始权重和成功条件下分布、单炉极品率、额外成丹率、返还比例及逐材料数量、材料/符箓消耗、缺口、can_execute 和经验/研究规则。不可购材料的商店价值记为 null，不把 0 占位买价当免费；总商店价值超过 P2 数值上限时也返回 null。价值仅作参考，开炉不另扣灵石。

材料不足时仍返回概率和缺口，`can_execute` 为 false；未知/未解锁丹方、不合格境界、非法配置等返回明确错误。持有物使用与商店资格分开，奖励获得的符箓可使用，不再次要求商店购买境界。灵草枯竭的草药价格按实际商店修正报价，预览成本与购买执行一致。

## RNG 与复现

`RNGContext` 有 alchemy / exploration / world 三条独立 RandomNumberGenerator。初始化以世界种子异或固定盐值分别设 seed；UI 不可使用这些流制作装饰动效。

快照含 schema_version、完整 engine_version，以及每条流的 seed/state。**seed/state 使用规范十进制字符串**，避免 JSON 把大于 2^53 的 int64 四舍五入；恢复时先设置 seed，再设置 state。恢复前整体验证版本、结构、整数格式及范围，失败不修改任一流。非本机锁定引擎版本不允许恢复。

抽样用 `randi() / 2^32` 得到 [0,1)，所有概率判断使用 `<`：

1. 一次成功抽取；失败后停止抽取品质和多丹。
2. 成功后一次品质抽取，四档按固定顺序及半开区间判定，跳过零权重。
3. 额外成丹率 > 0 时，再抽一次；额外一枚沿用同一品质。

当前未定义变异内容，预览 mutation_chance 明确为 0，不消耗变异抽样，也不声称已接入变异系统。P8九龙神炉正式启用20%多丹，仅火/魂丹激活；成功后多得一枚同品质丹药，材料仅扣一批，经验、心得、首次发现和炉次各只结算一次。实际事务、精确重放及每组十万炉检查见 P8_EQUIPMENT_REPORT.md。

服务不接受 UI 传入的已抽结果或可变 RNG。执行从 `state.rng_states` 恢复局部 RNG，只有完整结果验证通过才把新快照提交。即使抽样后才发现输出堆叠或奖励溢出，也不会推进实际状态中的 RNG。

## 结算与事务

成功：获得 1 枚或额外 1 枚同品质丹药；经验为品阶×10，基础研究 +1，首次发现本丹方/品质额外 +2。

失败：每种材料返还 `floor(消耗量×返还率)`，符箓不返还；丹渣×1，经验为品阶×3，基础研究 +1。丹渣是新增的第 9 种材料，卖价 3、不可购买；本阶段不实现丹渣研究兑换，因此不会对同一份丹渣重复兑现出售和兑换价值。失败基础研究是独立的尝试奖励。

P7 上古遗迹在每次概率开炉的基础研究再加 1，成功失败都生效；百草通灵在本世首次发现的额外研究再加 1，永久图鉴中已发现不妨碍新世首次奖励。定式研制不叠加概率开炉奖励。研究预览和冻结回执来自同一规则，界面按实际值显示。残灰归元将丹渣出售单价从 3 改为 6，由商店权威报价。

一次合法炉次统一提交材料/符箓、返还、丹药/丹渣、经验、研究、发现记录、成功失败统计、行动数、操作历史、RNG 快照和 needs_save。由共享 StateTransaction 提交已验证候选状态并生成独立前后快照；P2 也复用该提交原语，仍保留其独立经济状态接口。

返回结构沿用 TransactionResult。`ok: true` 表示合法操作结算完成，`result.success: false` 表示炼制失败；两者不可混淆。返回包含 action_id、冻结规则快照、品质、数量、消耗/返还和成长奖励。结果仅是展示用副本，修改它不会更改库存、配置或下一次概率。

非法输入、资源不足、重复 ID、未知规则或任何溢出均返回 `ok: false`，完整原状态保持不变。回执和日志不再次掷骰。暂不提供批量炼丹入口，未来批量功能须逐炉调用并使用独立操作 ID。

## 运行与验证

```sh
godot --headless --path . --script res://tools/alchemy_demo.gd
godot --headless --path . --script res://tests/test_runner.gd -- --alchemy-only
godot --headless --path . --script res://tools/alchemy_simulator.gd -- res://docs/P8_TUNING_PROBABILITY_RESULTS.json
```

模拟以执行引擎相同的 Rules.roll 为入口，每构筑十万炉，覆盖普通、稳妥、火属性冲品、回收及正多丹概率测试夹具。统计的是概率规则，不运行五十万次完整背包/日志事务，也不替代 P8 经济模拟或人工时长测试。

已测试 RNG 的 JSON 往返、临时检查点和 P6 实际存档恢复后继续开炉。SaveManager 的封套、备份及失败保护见 SAVE_API.md；自动保存失败仍保留 needs_save，UI 显示失败而非成功。P6 定式研制走独立显式命令，不修改概率炼丹的显示/抽样，也不计入 alchemy_attempts。

## P8首轮调优

冲品天赋仅增加3/4/5点极品转移，不再额外降低成功率；rush策略自身−15个百分点不变。赤炎炉只对火丹增加3个百分点成功率并转移8点上品权重，仍须持有。实际预览与结算共用现有规则，未新增隐藏保底或改动5%～95%限幅。正式字段与候选证据见P8_TUNING_REPORT.md。旧炉次保留原回执，旧档未来炉次使用新内容，跨数值版本不承诺结果一致。
