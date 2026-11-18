# P6 单周目成长与操作

适用 `0.1.6-p6` / Godot `4.5.stable.official.876b29033`。本世从丹童到大宗师，按累计历练、已炼/研制成就、考核丹药和特定委托/异火前置逐级认证。候选门槛见 BALANCE.md，配置见 ranks.json / talents.json。

## 操作路径

1. 在丹房炼丹或前往宗门行记补给、接取“宗门日常供丹”；收丹交付。失败仍获得研究心得，可免费采药/休整继续。
2. 打开底部“丹师”，查看下一品阶的历练、成就、交丹和阶段前置。满足后“交丹认证”，实际消耗最低达标品质的一枚丹药，高品质可替代低品质。
3. 若迟迟没有合格丹药，可在同页“定式研制考核丹”。先习得配方、备齐显示药材与心得，点击后必得指定品质与历练，随后再交丹认证。此路径公开且完全不掷骰；不会伪装成概率炉的隐藏保底。
4. 达到三品、六品、九品，各有一次三选一天赋；本世不可重选。未选时可继续积累资源，但不能通过下一次认证。稳妥与冲品天赋只在相应策略生效；研究天赋降低定式成本并支持灵草替代缺少的不可购物品。
5. 逐级解锁凝神丹、筑基丹及四至九品古方。坊市旧有一品商品和秘境/委托随真正晋升开放。地心灵火可用 P5 固定仪式或委托取得，灵芝与养魂露都有指定地点固定选项。
6. 九品完成太初造化丹考核后晋升大宗师，在丹师页显示标准结局、行动/概率开炉/研制/委托/历练的通关快照。返回丹房仍能收集图鉴，后续行动不会重写通关统计。

“图鉴”展示 12 丹方×4 品质的实际发现；出售、交付均不删除记录。山门图鉴也能只读查看当前会话或磁盘保存的发现。图鉴为本世状态；P7 的永久图鉴和轮回尚未实现。

“存档”可立即保存或确认后读取。普通行动自动保存，重启在山门选择“读取修行存档”；保存失败时页脚和存档页显示原因，退出前也会保留重试/返回机会。保存及恢复规则见 SAVE_API.md。

## 接口与状态

`ProgressionState.create_state(seed)` 在 P5 状态上增加：

```gdscript
{
    "talent_choices": [],
    "pending_talent_rank": 0, # 0 / 3 / 6 / 9
    "research_crafts": 0,
    "ending": {} # 完成认证后为固定结局统计，不在后续行动重写
}
```

`ProgressionService` 注入 ContentDB，提供纯查询 `preview(state)`、`preview_study(state)`、`collection(state)`；命令 `study_exam(state, target_rank, action_id)`、`promote(state, target_rank, action_id)`、`choose_talent(state, talent_id, action_id)`。target_rank 必须为当前下一阶，防止旧界面在新境界误执行。配置引用、完整状态与前置检查通过后才提交候选；失败不改资源、品阶、图鉴、操作记录或 RNG。

定式研制消耗公开配方与折扣后心得，获得一枚考核品质丹药、品阶×10 历练、research_crafts/action_count 各+1；记录在 alchemy_discoveries（目前表示全部炼制/研制品质发现），不增加 alchemy_attempts 或普通成功计数。实际开炉的首次品质奖励会参考同一发现记录，不对研究已发现品质重复发首次奖励。

晋升不扣经验，扣考核丹，rank/action_count 各+1；自动发放 unlock.type=rank 且门槛已达到的丹方，不免费发放商店丹方、装备或异火。天赋确认不计额外行动。最终认证生成 `ending_grandmaster` 统计快照。

AlchemyService 校验天赋 ID、可选境界、每里程碑唯一性；完整 ProgressionState 还验证此前天赋已选、当前待选标记和结局一致性。AlchemyRules 加入已选天赋列表，空列表维持 P3 全部概率；预览与执行沿用同一计算/抽样，UI 只显示回执和快照。

## 可达性与边界

`tests/helpers/progression_route.gd` 从固定新状态出发，只调用公开会话命令，使用实际免费补给/交易/委托/探索/开炉、研制和认证完成通关，不写 rank、库存或经验。三套天赋选择均已通过；演示命令：

```sh
godot --headless --path . --script res://tools/progression_demo.gd
godot --headless --path . --script res://tests/test_runner.gd -- --progression-only
```

可用 `-- --write-checkpoints` 写出三品、九品、大宗师隔离复核档；`-- --prepare-final` 通过正常命令额外积累资源，生成九品待选且可做最终考核的 `res://test-output/p6-demo/final-ready.json`。这些为测试产物，不碰默认 user:// 存档。

P6 不实现轮回、MetaSave、传承、天地变数、变异或最终内容规模。新游戏仍会重置本世图鉴与天赋，必须在明确确认后才替换存档。本阶段完成的是标准单周目可达性，尚未验证 4～8 小时真人体验或完整经济平衡。
