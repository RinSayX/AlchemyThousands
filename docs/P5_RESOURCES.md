# P5 资源操作与接口

适用 `0.1.5-p5` / Godot `4.5.stable.official.876b29033`。静态内容见 CONTENT_SCHEMA.md，候选价格和奖励见 BALANCE.md。

## 玩家操作

进入丹房后点击底部“坊市 / 委托 / 秘境 / 采药”，打开“宗门行记”。四个页签可切换；Esc 或“返回丹房”关闭。秘境尚未处理时其他页签锁定，关闭面板会免费离开当前事件。

- 坊市：选择材料、符箓、丹方、丹炉、异火分类；普通物品一次 1～99 件，永久物品每次一件。购买、卖出先查权威报价，境界、来源、余额和库存不足时禁用并提供原因。丹药仍在丹房或结果弹层中出售；可以收丹留作委托。
- 委托：接取后显示尚缺合格丹药数；达到数量后“交付并领取”一次扣丹与领奖。允许更高品质，优先使用最低达标品质；完成的基础委托可再接一单，生成新实例。
- 秘境：可随缘按公开权重寻访，也可直接前往已开放地点。卡片列出消耗、成功率、成功/失败物品；随机选项失败仍支付公开成本。百年灵芝、养魂露有稳定选项；一品地火仪式或委托提供地心灵火。
- 采药：免费补齐一炉聚灵丹所需的缺口；已有足量时不发。每趟三次，用尽后可免费休整恢复全部次数，无需实时等待或灵石。采药后返回丹房正常炼制，成功可交单或出售，失败可出售丹渣。

本阶段没有晋升入口，一品商品/委托/事件保持正常锁定。正式保存读取还未实现，关闭程序会丢失本次进度。

## 状态与事务

`ResourceState.create_state(seed)` 在 P3 初始状态上增加：

```gdscript
{
    "quest_instances": {}, # quest_run_N -> {template_id, status, serial}
    "quest_serial": 0,
    "pending_exploration": {}, # 或 {event_id, instance_id: event_run_N, serial}
    "exploration_serial": 0,
    "forage_uses": 0,
    "resource_stats": {"forages": 0, "rests": 0, "explorations": 0, "quests_completed": 0}
}
```

状态只保存模板引用，不能执行配置脚本。实例序号、模板存在性、状态、唯一进行中/一次性实例、采药次数与整数边界均验证。正式存档封套/迁移不属于本阶段。

服务接收外部状态字典并注入 ContentDB，先验证和产生候选，再用统一 StateTransaction 原子提交经济、进度、RNG 与 P5 字段。结果沿用 `{ok, error_code, message, state_changes, result}`；回执深复制。成功写入 `completed_actions` 和 `needs_save`；失败不改任何字段或 RNG。操作 ID 跨服务共享去重。

| 服务 | 查询（纯） | 命令 |
|---|---|---|
| QuestService | `board(state)`、`preview_delivery(state, instance_id)` | `accept(state, template_id, action_id)`、`deliver(state, instance_id, action_id)` |
| ExplorationService | `destinations(state)`、`preview_option(state, instance_id, option_id)` | `enter(state, action_id, event_id="")`、`resolve(state, instance_id, option_id, action_id)`、`leave(state, instance_id, action_id)` |
| ForageService | `preview(state)` | `forage(state, action_id)`、`rest(state, action_id)` |

`ForageService.preview` 返回本次缺口、剩余机会、是否可采/可休整、基础材料是否充足及恢复路线可用标记。基础方缺失/锁定时明确报 `RECOVERY_UNAVAILABLE`；正常新会话固定拥有基础方，不会因接单耗材失去该方。

GameSession 创建 P5 状态，持有服务并生成唯一 action_id；UI 只读 `state()` 副本与回执。炼制揭晓前或待选秘境中，协调层阻止交易、采药、委托、另开炉和重置会话。待选事件只可 resolve/leave；即使换新 action_id，旧实例也不能重新发奖。UI 同帧操作锁与服务层实例/操作防重放共同保护重复点击。

## 随机流

直接选地点不抽地点 RNG；随机进入在当前境界的开放事件中按 weight 抽一次 exploration。随机结果 `draw < success_rate`，0/100% 确定性结果不抽。Alchemy/world 流保持不动。使用临时 RNGContext 恢复快照，只有交易最终成功才提交新快照；金额/物品溢出在抽样后也会完整回滚成本、实例和 RNG。

`ExplorationRules.pick_event` 与 `succeeds` 为纯区间函数，实际服务与统计测试共享。相同引擎、种子、状态、命令序列可复现；改变探索次数不改变后续炼丹抽样序列。

## 验证入口

```sh
godot --headless --path . --script res://tests/test_runner.gd -- --resources-only
godot --headless --path . --script res://tests/test_runner.gd -- --ui-only
```

资源专项包含非法内容、领取/交付、品质/数量、实例防重放、溢出回滚、独立 RNG、稳定稀有素材/异火、连续失败恢复和十万次分布抽样。UI 专项以真实场景和信号检查四页行为、焦点、重复点击、状态保护与窗口边界。完整命令及实际结果见 P5_REPORT.md。

## P8 稀有素材稳定来源

0.1.10新增月华泽（二品）、寒玉药园（四品）、雷鸣山隘（六品）、太古灵台（八品）。每处两项固定灵石费用的100%成功素材交换，允许反复获取，不采用装备试炼的一次性规则；未到境界和付不起费用时保持原子失败。

`GameSession.material_sources(item_id) -> Array[Dictionary]` 在已有修行中纯查询，底层 MaterialSources.entries 接收有效内容与状态；每行含 event_id/event_name、option_id/option_name、required_rank、cost_stones、quantity、unlocked。只接受材料ID，未知/其他类别返回空数组；返回内容为副本，不收费、不入境、不改变RNG。它扫描无物品费用、无灵石返还/装备奖励、非一次性且成功率100%的事件，按当前世界变换后的实际数量说明稳定供给。cheapest 仅从已开放项按每份灵石成本选择最便宜来源，用于分析和可达性工具，不替玩家自动执行。

坊市显示来源费用/数量与资格，丹方材料栏给出地点及境界；混有不可购材料的整批商店报价仍会失败，不跳过费用或自动兑换。实际获取继续调用 enter_event / resolve_event，并沿用防重放与存档事务边界。完整清单见 P8_CATALOG_REPORT.md。
