# P2 背包与经济交付记录

日期：2026-11-18。引擎：本机 `4.5.stable.official.876b29033`。范围依据设计第 16.4、18.3 节：实现内存背包、货币和商店服务，不进入 P3 炼丹或正式商店 UI。

## 文件清单

| 文件 | 内容 |
|---|---|
| `scripts/core/transaction_result.gd` | 统一成功/失败结构，返回独立回执快照 |
| `scripts/core/pill_stack.gd` | 四品质普通丹药的堆叠键与数据格式 |
| `scripts/services/economy_service.gd` | 初始经济快照、状态校验、灵石增减、候选状态准备和提交、操作防重复 |
| `scripts/services/inventory_service.gd` | 材料/消耗品与丹药获取、堆叠、消耗和纯计划接口 |
| `scripts/services/shop_service.gd` | 权威报价、购买/出售、批量事务、境界限制、永久内容解锁和品质售价 |
| `tests/test_economy.gd` | 经济专项回归、原子性快照比较、整数边界与重放检查 |
| `tests/test_runner.gd` | 加入 P2、专项选择参数和执行完成检查，拒绝互斥参数同时使用 |
| `tools/economy_demo.gd` | 不读写玩家存档的临时状态交易演示 |
| `project.godot` | 版本元数据 `0.1.2-p2`；引擎、主场景与 Autoload 不变 |
| `docs/ECONOMY_API.md` | 状态、接口、事务、错误码、数量限制和定价规则 |
| `README.md`、`docs/CHANGELOG.md` | 当前功能、运行命令和下一阶段 |
| `docs/BALANCE.md`、`docs/P2_REPORT.md` | 结算细化及阶段交付记录 |

新增脚本的 `.uid` 文件一同提交。原始设计文档、现有界面、P1 静态内容与价格未修改，无新增依赖或全局单例。

## 完成的功能

- 材料/消耗品按 ID 堆叠；普通丹药按丹方、品质堆叠；支持整批获取和消耗，耗尽移除条目。
- 按配置购买材料和消耗品；满足商店及境界要求时可购买永久丹方/装备，已有永久物品不重复购买，也不作为堆叠品出售。
- 材料/消耗品使用卖价；丹药使用四档倍率，单枚先向下取整后累计。未注册的变异不会被当成普通丹药出售。
- 购买/出售购物车最多 128 行，全量校验后一次提交。重复商品行累计核算，任何行失败时余额、库存、丹药、所有权、操作记录均不变。
- 操作 ID 在各服务之间共用，成功后记录，重试不重复扣款或奖励；失败不占用 ID。
- 余额、库存、售价及总价检查 `2147483647` 上限，并保护品质倍率和数量乘法，拒绝小数/布尔值/无穷/字符串冒充数量。
- 报价不修改资源、RNG 或操作记录，执行时重新核算；回执和候选快照不与实际经济集合共享可变引用。

## 实际验证

以下在项目根目录运行。最终成功日志无脚本错误或引擎错误。

| 命令 | 结果 |
|---|---|
| `godot --headless --version` | 退出码 0；仍为 `4.5.stable.official.876b29033` |
| `godot --headless --path . --editor --quit --log-file /tmp/alchemy-p2-import-final.log` | 退出码 0；资源导入完成 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p2-economy-fixed.log -- --economy-only` | 退出码 0；**117 项专项检查通过、0 失败** |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p2-tests-final.log` | 退出码 0；**245 项检查通过、0 失败**，含 P1 的 106 项及 P0 的 22 项回归 |
| `godot --headless --path . --script res://tools/economy_demo.gd --log-file /tmp/alchemy-p2-demo.log` | 退出码 0；临时交易路径完成，详见下文 |
| `godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p2-startup.log` | 退出码 0；主场景启动并退出 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p2-flags.log -- --content-only --economy-only` | **预期退出码 1**，提示只选择一个专项，避免零检查被误认为通过 |

专项覆盖：正常买入/卖出、精确余额归零、资金/库存不足、重复奖励、跨服务重放、失败 ID 重用、库存消耗至零、批量后置错误、重复行超卖、稀有材料零占位买价、境界锁、未知商品/品质/变异、伪造价格、永久内容重复购买、数量及金额溢出、四品质定价、奇数基价取整、报价纯度、旧报价重新校验、回执引用隔离、非法状态和额外 RNG/元数据保留。被拒绝操作比较序列化前后快照，验证原状态完全不变。

实际命令行演示：200 灵石购买灵草×2＋青花×1，总价 14，余额 186；相同 ID 再提交返回 ACTION_DUPLICATE，余额仍 186；演示脚本明确注入一枚良品聚灵丹，按 39 出售，余额 225。注入丹药只为验证 P2 售丹功能，没有运行炼丹或 RNG，也没有写入游戏存档。

本次未修改界面，不重复进行图形人工检查。未执行 Windows 实机、发布导出、经济模拟、多线程竞态或持久化崩溃恢复测试。

## 问题与解决

- 首轮测试代码使用了 Godot 4.5 Array 不支持的方法，改为 resize/fill 生成长购物车夹具；对购物车行及成员判断补充显式类型，修正 GDScript 推断错误。
- 实际发现部分脚本编译/运行错误并不保证 Godot 返回非零退出码，因此 P2 测试增加各组和整套执行完成检查，并检查最终日志；未把那次中断产生的部分检查结果当作通过。最终 117/245 项结果来自修正后的实际运行。
- 清理首次解析失败遗留的无头测试进程，仅匹配本次精确命令。

## 设计细化与边界

保留 P1 所有静态数值。采用原设计初始资源和品质倍率，明确单枚售价向下取整、经济字段上限、购物车行数上限及永久物品交易规则，已写入 BALANCE.md 和 ECONOMY_API.md。

经济状态是 RunState 的子集，不是完整新周目；操作历史目前只在内存中，序列化恢复测试也不代表游戏存档功能已实现。后续存档需保留操作历史并恢复整数类型。P3 的经验、研究、统计和 RNG 需在该阶段扩展事务边界，P2 不承诺它们已能随经济字段一起提交。

尚未实现：实际炼丹、装备效果/策略、游戏协调器、商店/背包界面、完整存档、委托、探索、晋升或轮回。P2 服务不自行派发未接入的事件，也不引入假游戏进度。

P2 验收已达到：背包和交易可通过服务操作、价格正确、失败不改状态、无负余额/库存及重复提交结算。下一步 **P3 炼丹引擎**：预览/执行统一规则，独立 RNG 和快照恢复，成功/品质判定、装备/符箓/策略、失败回收、经验研究及十万次概率验证。

本阶段提交说明：`feat: implement transactional inventory and economy for P2`。
