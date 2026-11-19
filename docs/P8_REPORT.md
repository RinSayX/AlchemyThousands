# P8 分析批次验收 · 2026-11-19

本机版本先复核为 `4.5.stable.official.876b29033`，开始时工作区干净。按 DEVELOPMENT_PLAN.md §18.9 完成P8的模拟与报告批次：先建立证据，再确认数值依据。本次未修改正式游戏data、运行时业务脚本、存档格式或版本号，游戏保持0.1.7-p7；P8整体内容/时长目标尚未完成。

## 文件与功能

- tools/balance/economy_probe.gd：正式概率预览/抽样、单位取整售价、确定性稀有来源、回收机会价值、合格丹等待量与现金分位数。
- tools/balance/campaign_route.gd：受控首世/后世开局，此后用正式服务完成资金、材料、装备、委托、自然考核/研制、晋升，记录每阶段和现金账；区分事务错误、步数上限与资源死锁。
- tools/balance/experiment.gd：21场景、四政策、原始轨迹与分组汇总、输入哈希、零资源恢复和免费矿脉旁路。
- tools/balance_simulator.gd：独立无头入口、参数/输出限制；tools/balance_sensitivity.gd：同境界不同丹炉与护炉玉的补充对照。
- tests/test_balance.gd、test_runner.gd：新增38项分析专项及--balance-only，纳入全量。
- docs/P8_SIMULATOR.md、P8_BALANCE_REPORT.md：方法、假设、结论和待确认提案；P8_BALANCE_RESULTS.json、P8_BUILD_SENSITIVITY.json：原始生成数据。README、BALANCE、CHANGELOG同步本批范围。

## 实际执行

以下命令成功退出0：

```sh
godot --headless --version
godot --headless --path . --editor --quit --log-file /tmp/alchemy-p8-import-final.log
godot --headless --path . --script res://tools/validate_content.gd --log-file /tmp/alchemy-p8-content-final.log
godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p8-focused-final.log -- --balance-only
godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p8-tests-final.log
godot --headless --path . --script res://tools/balance_simulator.gd --log-file /tmp/alchemy-p8-simulation-final.log -- --samples 10000 --seeds 8 --output res://docs/P8_BALANCE_RESULTS.json
godot --headless --path . --script res://tools/balance_sensitivity.gd --log-file /tmp/alchemy-p8-sensitivity-final.log -- --output res://docs/P8_BUILD_SENSITIVITY.json
godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p8-startup-final.log -- --save-path res://test-output/p8-no-save.json
```

全量 **826项检查，0失败**，其中新增平衡专项 **38项，0失败**。内容仍为11表74条且校验通过。最终导入、内容、专项、全量、敏感性、启动日志无SCRIPT ERROR/ERROR/FAIL。

正式模拟统计和校验见 P8_BALANCE_REPORT.md 及JSON：21场景×4政策×8种子，672条政策均通关、672条破产压力均恢复，真实通关开炉119138次，现金账全部一致。840个逐品阶探针各10000炉，敏感性61个代表构筑各100000炉，合计1450万次规则抽样；完整现金事务炉次另计。输入哈希与报告参数保留，可按命令复现；所有数据/核心/服务文件运行前后相同。

参数拒绝检查实际运行，预期退出1且未生成对应报告：

```sh
godot --headless --path . --script res://tools/balance_simulator.gd -- --samples 0 --output res://test-output/invalid-zero.json
godot --headless --path . --script res://tools/balance_simulator.gd -- --output res://data/recipes.json
```

也实际运行了--smoke和每组单种子的全矩阵预演，均在修正路线后通过；这些不替代最终8种子报告。

## 发现与修正

模拟路线最初会先保留考核聚灵丹，后在补历练时把它交给主线供丹，导致晋升拒绝；改为先完成主线供丹，再保留认证丹。筹资炼丹还会消耗之前备好的材料/护炉玉，改为补足整炉物品并重新检查，不把库存当作恒定。修改只发生在分析驱动，未改业务服务。

专项第一次解析发现快照子字段需显式Dictionary类型，已修正。敏感性最初把未被政策实际选用的赤炎炉当强制装备，导致所有权拒绝；修正为只比较实际会选择的火属性冲品赤炎行，并保持默认装备与所有权一致。最终对应日志均通过。

经济上发现免费矿脉采集后直接出售可稳定获得7灵石/次，真实100次得700灵石且0炉；护炉玉的边际收益随材料堆叠和失败率变化，低阶普遍不抵价格；高阶冲品到5%下限时出现负单炉期望。具体数据、构筑偏差和未应用调整候选在平衡报告中完整说明。

本批没有更改游戏UI，未重新做实机游玩或真人时长测试。全量保留既有UI场景回归，隔离启动成功；P7实机轮回记录仍是上一阶段证据，不能标作P8真人体验验证。

## 未完成与后续

本批完成的是P8首批分析交付，未完成25丹方/更多装备材料/隐藏结局/试炼、真人首世4～8小时与后世2～3小时。通关政策、世界等量条件样本、有限8种子及后世传承夹具不代表所有真实玩家，也没有模拟完整永久解锁过程。

下一批应先审阅报告和具体候选，在隔离实验中逐项验证rush天赋/赤炎调整与按边际价值用玉的政策，再决定正式修改和内容扩充顺序。不能通过堆经验门槛或强制动画把模拟炉数伪装成目标时长。
