# P8 装备与资源试炼验收 · 2026-11-19

历史验收版本0.1.9-p8-equipment，提交db412f6；原始结果保留。后续25丹方/25材料扩充见 P8_CATALOG_REPORT.md。

交付版本0.1.9-p8-equipment，承接fa48859。依据 DEVELOPMENT_PLAN.md §18.9，本批先分析独立提案，再追加正式配置；补齐6丹炉/5异火及对应稳定获取路径。P8仍有丹方材料扩充、隐藏结局、完整资金消耗和平衡/真人时长验收待做。

## 实现与范围

原11张表74条定义保持0.1.8原值，追加玄冰/紫霄/九龙丹炉、青莲/寒髓/紫霄异火、青莲/霜渊/紫霄/九龙四事件，共84条。正式参数与成本表见 BALANCE.md。本批试炼是公开材料/费用交换的确定性资源试炼，未增加战斗或限时小游戏。紫霄火焰只提供已注册品质效果，不声称实现变异。

新增可选 effect_strategy 限制整件装备的所有效果；与丹方标签同时匹配后参与正式预览/执行。紫霄炉/火仅rush激活，九龙火/魂丹成功后20%额外成丹。没有新效果脚本、附加依赖或不可见概率。两枚同品质丹只扣一批材料，成长、发现和尝试计数结算一次。

事件选项 requires_unowned_reward 为布尔，开启时强制100%成功并恰奖励一种丹炉/异火。预览/结算在收费前按本世所有权拦截重复。部分完成仍可进场选其他奖励；全完成返回 EVENT_EXHAUSTED，不收费、不消耗行动/RNG，也不再进入随机池。普通旧事件仍可重复。坊市说明稳定来源，已取得选项禁用并说明本世不再扣费，列表显示“试炼已完成”；入境将滚动位置归零。

沿用schema2，无新存档字段。完成状态由 owned_furnaces / owned_flames 推导；旧档不自动得到新装备。轮回清除本世装备与试炼进度，保留永久发现/传承/成绩。

## 隔离实验与数值证据

冻结基线 tests/fixtures/p8_v1_content.json 加 combined 调优，再叠加 tests/fixtures/p8_equipment_proposal.json。equipment_model.gd 不读取玩家档、不修改data；正式内容测试逐条比对完整84条定义，原74条另保留数值回归。

提案分析每组100000次概率采样，另100000次收益采样，九组合计180万次；调用正式 AlchemyService 预览及共用 AlchemyRules.roll。每组成功率误差≤1个百分点，条件品质/多丹用六倍标准误差，净收益均值用已有有界抽样门槛，全部通过。报告保留种子、配置哈希、理论/观测及判定。

| 条件构筑 | 理论成功 | 成功条件下极品 | 成功后多丹观测 | 单炉理论净收益 |
|---|---:|---:|---:|---:|
| qinglian_wood | 85.0% | 0.0% | 0.000% | 86.81 |
| ice_recovery | 63.0% | 0.0% | 0.000% | 152.90 |
| thunder_mid_rush | 20.0% | 38.0% | 0.000% | 263.68 |
| thunder_late_rush | 5.0% | 43.0% | 0.000% | 54.40 |
| dragon_rush | 8.0% | 28.0% | 20.055% | 147.66 |
| dragon_stable | 47.0% | 0.0% | 20.144% | 665.31 |
| dragon_forbidden_fire | 10.0% | 18.0% | 20.122% | 151.82 |
| dragon_inactive_wood | 90.0% | 1.0% | 0.000% | 16.95 |
| thunder_inactive_stable | 34.0% | 0.0% | 0.000% | 359.66 |

上述收益扣除逐材料可重复获取价值和失败返还后的成本，按现有售价计产物；不摊销固定装备取得费用。各组采用报告中的品阶、天赋、丹方、策略、异火及世界条件，不能跨组把差值都归因于丹炉，也不按世界自然出现概率加权。冰套包含已有stable天赋的回收，新增两件本身贡献45个百分点。未适用属性和非rush组不触发新效果；禁火抑制特殊异火，九龙自身仍可生效。

## 正常获取路线

EquipmentRoute 从种子20261119的新修行开始，仅用公开 GameSession 命令：采药、免费休整、基础stable开炉、委托/出售筹资，正常考核晋升和三次rush天赋选择；在1品购青木/赤炎并收服地火，3/4/6/8品逐项支付新装备的材料与灵石。稀有药材由古木药圃/养魂灵泉固定选项取得，未注入钱、物品、境界或掉落。

实际完成：大宗师、6丹炉/5异火、七次装备事件（地火+六项新奖励，另有两次旧炉购买），421次概率炼丹、1061次行动、期末1105灵石。筹资脚本本批补足“装备支出后继续筹资支付考核材料”的处理。四试炼全部完成；新档读回保留所有权并拒绝再领；领奖后轮回只保留凡铁炉/凡火，试炼重新开放，永久传承和一世成绩保留。

演示写入 test-output/p8-equipment/ 的 rank-3/4/6/8/10.json 和 rank-before_ice.json；后者在第一次霜渊领奖前已通过正常操作备齐玄冰炉成本。后续GUI操作会更新它，重新执行demo可恢复原始演示点。工具不写默认用户存档。可达性路线不比较新装备效率，也不构成人类游玩时长或最优策略证据。

## 验证

本机Godot 4.5.stable.official.876b29033，Compatibility，macOS。

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --script res://tools/equipment_simulator.gd -- --output res://docs/P8_EQUIPMENT_ANALYSIS.json
godot --headless --path . --script res://tools/equipment_demo.gd
godot --headless --path . --quit-after 3
```

全量919项检查、0失败，日志 /tmp/alchemy-p8c-verified.log；导入、84条内容校验、启动和demo退出0，无脚本错误。专项入口为 --equipment-only，界面专项 --ui-only，两者在 -- 后提供且不能同时指定。

新增服务检查包含非法字段/策略/一次性奖励拒绝并保留缓存、完整提案匹配、条件激活、真正多丹事务、同种子完整重放、不激活装备不多抽RNG、品阶/钱/材料不足原子失败、重复action与新action领同一装备、部分/全完成地点、权重重新归一、全装备正常获取、schema2读回及轮回。原探索统计从固定五事件总权重更新为当前表总权重，九事件各十万次选择分布通过。

新增场景检查通过真实按钮信号获取玄冰炉，连续发出两次信号只扣费一次；重进保留禁用的已取得行；六炉五火选择器读取所有权；完成试炼面板在960×540、1280×720、1920×720内可用，并检查已滚动列表入境回到顶部。

macOS原生1280×720窗口载入隔离的四品试炼前存档：列表显示青莲已完成、霜渊可进入、紫霄未开放；霜渊展示1200灵石、铁精砂6、养魂露2和玄冰炉奖励。点击后灵石1210→10，再入境显示“已取得”且禁用，寒髓选项仍在但缺费用时禁用。复核发现旧列表滚动位置会裁掉新事件标题，已修复并由场景回归验证归零。

关闭并以960×540重启同一路径，读取后自动恢复进行中的霜渊事件，显示已取得玄冰炉且余额仍10。返回丹房后在选择器选中玄冰炉，免费休整/采药补齐材料并实际开炉：聚灵丹凡品1枚、消耗灵草2/青花1、历练+10/心得+1，结果框与按钮完整可见。日志 /tmp/alchemy-p8c-gui.log 与 /tmp/alchemy-p8c-gui-small.log 无脚本错误；该演示不修改默认用户修行档。

Windows导出和排版、首世4～8小时/后续2～3小时、全世界下新装备投资回收及后续完整内容暂未验收。历史 P8_BALANCE/TUNING 报告保留旧数据与提交口径，不覆盖成当前结果。

## 文件与职责

- data/{furnaces,flames,exploration_events}.json：装备参数与固定领取配置。
- scripts/core/{content_validator,alchemy_rules}.gd：注册字段与统一效果条件。
- scripts/services/exploration_service.gd：原子领取、地点可用性与权重。
- scripts/ui/resource_hub.gd：来源、领取状态、入境滚动。
- tests/test_equipment.gd、test_equipment_ui.gd、helpers/equipment_route.gd：业务/场景/正常获取回归。
- tools/equipment_{simulator,demo}.gd、balance/equipment_model.gd：可复现实验、演示和输出。
