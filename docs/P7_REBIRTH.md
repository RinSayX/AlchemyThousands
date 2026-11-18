# P7 轮回、传承与永久档案

基准 Godot `4.5.stable.official.876b29033`。本阶段只实现 P7，依赖 P6 标准大宗师结局；未实现其他结局或 P8 内容扩充。具体候选数值见 BALANCE.md。

## 玩家流程

丹房底部“轮回”打开第八个行记页签。未完成结局时可查看永久图鉴计数、已完成世数、最佳成绩、本世携带和世界规则。完成大宗师认证后，结局快照自动归入永久历史；可以留世继续修行，也可领取本世一次传承奖励。

候选来自配置顺序中前三项尚未解锁且满足完成世数要求的传承。剩余不足三项时展示全部，选择后立即安全保存；不能改选、重复领取或选择未展示条目。九项全解锁后改为永久心得 +1，新世初始研究心得最多额外 10 点。

领取后勾选下一世携带的已解锁传承，可空载；初始栏位 1，完成两世后为 2。只在新世创建时固定携带，本世不能随时换装。页面展示下一世编号、固定种子和两条世界描述，准备轮回后再明确确认：重置灵石、材料、丹药、丹炉、异火、丹方权限、境界、历练、研究、本世发现/委托/统计/天赋/行动/炉次历史，重新获得标准起始资源。取消留在原世，不扣物品、不抽实际 RNG。

保留永久图鉴、已解锁传承、成就、最佳成绩、历史结局、永久心得及便利功能。第一世完成后解锁跳过序章和快速揭晓；轮回直接回到可玩的丹房，清掉旧丹方搜索/筛选、符箓、策略、批次数和动画。新世默认凡铁炉、凡火、无符箓、正常炼制。

“重新入宗”对未结束修行只重开当前编号，保留永久档和当世固定世界/携带；结束后须走领奖/轮回流程。重开不会抹去永久档或把第二世变回第一世。

## 状态与接口

`scripts/core/profile_state.gd` 组合既有 ProgressionState，并增加严格永久档验证。状态和计划返回深副本，UI 不直接改动业务数据。

run 的 P7 字段为：

| 字段 | 含义 |
|---|---|
| `run_number` / `run_id` | 从 1 连续递增，标识为 run_N |
| `run_seed` | 规范十进制 int64 字符串 |
| `equipped_inheritances` | 本世固定携带传承 ID，最多两项且已解锁 |
| `world_modifiers` | 首世空数组，后续恰好两条相容、至少一条机会 |
| `heritage_reward` | 未领取为空，否则是本世所选传承 ID 或 legacy_insight |
| `resource_stats.heritage_supplies` | 元气初复本世使用数，0 或 1 |

meta 独立于临时 run：

| 字段 | 含义 |
|---|---|
| `highest_completed_run` / `records` | 完成世数及按世序连续的结局档案 |
| `discovered_pills` | 所有世的丹方/品质发现并集，不授予新世丹方使用权 |
| `unlocked_endings` | 当前仅 ending_grandmaster |
| `achievements` | first_ending、two_endings、all_inheritances |
| `best_records` | fewest_actions、fewest_furnaces，以固定结局统计计算 |
| `unlocked_inheritances` / `heritage_slots` | 永久传承与携带上限 |
| `legacy_insight` | 全池解锁后的永久心得奖励累计 |
| `tutorial_completed` / `quality_of_life_unlocks` | 序章完成及 skip_prologue、quick_reveal |

每条 records 保存 run_number、run_id、seed、ending、world_modifiers、equipped_inheritances、talents、reward、next_run。结局 snapshot 保持 P6 完成时统计，留世行动不会刷新最佳成绩；next_run=0 表示留世，成功转生才写下一世编号。发现记录独立合并，出售/交付/重开/轮回不清除永久图鉴。本世首次发现奖励仍用本世集合判定。

GameSession 暴露：

```gdscript
session.meta() # 深副本
session.rebirth_status() # 资格、候选、栏位、已解锁列表
session.claim_inheritance(source_run_number, inheritance_id)
session.preview_rebirth(loadout_ids) # 完整下一世候选，无写盘/实际抽样
session.begin_rebirth(source_run_number, loadout_ids)
```

`scripts/services/rebirth_service.gd` 的 preview、preview_next、plan_claim、plan_rebirth 只计算候选。源周目编号防止界面陈旧按钮跨世使用，操作 ID 和已领奖标记防重复。保存成功前不替换活动 run/meta，失败回到同一世可重试；有未结束炼制或秘境时拒绝。统一保存格式和迁移细节见 SAVE_API.md。

## 世界生成与共享规则

第一世固定标准世界。轮回先恢复旧世 RNG 副本，从其 world 流抽一次，下一世种子为 `int(value * 2147483646) + 1`；新 seed 建立三流，先按权重选择有相容伙伴的机会规则，再从相容规则中按权重选第二条。新 world 流推进两次，alchemy/exploration 保持新种子的初始快照。预览仅操作副本；切换携带不改变世界，失败保存不影响重试的种子/规则。

兼容性来自双向 exclusive_with，不能重复、不能自斥；配置必须有第二世可用的机会组合。各权重当前均为 1，算法不承诺无序组合等概率。每次只生成新世开局一次，服务不靠 UI 随机数或动画决定结果。

`scripts/core/lineage_rules.gd` 集中处理纯修正：炼丹成功/品质/研究、草药买价、丹渣卖价、委托品质/奖励、秘境奖励/仪式成本；服务预览、UI展示和实际事务均调用相同结果。古炉寻踪选项按传承资格过滤，奖励装备不进入堆叠物品；元气初复优先使用每世一次补给，后续回到普通三次采药/休整循环。全部效果有真实服务执行测试。

天地禁火仅抑制异火炼丹加成，保留异火收服及认证资格；丹道盛世不提高基础供丹品质。这两条保护既有确定性主线路径。未知传承/规则和任何溢出仍拒绝整笔事务，不隐藏修正显示概率。

## 演示与边界

```sh
godot --headless --path . --script res://tools/rebirth_demo.gd -- --write-checkpoints
godot --headless --path . --script res://tests/test_runner.gd -- --rebirth-only
```

演示通过公开命令从第一世新档完成结局，领取百草通灵，生成第二世，读档并真实开炉对照复现；检查点写在忽略目录 test-output/p7-demo。测试另正常跑完第二世，验证第三世双栏位。第3～10世全池和替代奖励使用有效历史夹具，不等同十次正常通关。完整平衡、目标时长、其他结局、正式美术、Windows 导出均留待后续阶段。
