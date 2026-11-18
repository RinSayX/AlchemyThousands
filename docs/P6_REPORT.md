# P6 单周目成长与结局交付记录

完成日期：2026-11-19（Asia/Shanghai）。开始前检查本机 Godot 为 `4.5.stable.official.876b29033`，继续作为工程基准；项目版本 `0.1.6-p6`。本次执行设计第 16.8、18.7 节，并按 P6 验收补齐基础保存读取，不进入 P7 轮回。

## 文件清单

| 文件 | 改动 |
|---|---|
| `data/recipes.json` | 保留旧六方，补四至九品六方，覆盖完整晋升路线 |
| `data/ranks.json`、`data/talents.json` | 11 个品阶、10 次逐级考核、9 个分组天赋及候选门槛 |
| `scripts/core/content_validator.gd`、`content_db.gd` | 九表、完整品阶/三选一/引用/考核可达性验证，整数规范化 |
| `scripts/core/progression_state.gd`、`talent_rules.gd` | 完整成长状态、天赋/待选/结局一致性与共享校验 |
| `scripts/services/progression_service.gd` | 条件预览、考核扣丹晋升、定式研制、天赋确认、图鉴与固定结局快照 |
| `scripts/core/alchemy_rules.gd`、`scripts/services/alchemy_service.gd` | 已选天赋进入同一预览/抽样规则，按策略激活；保留独立随机流与空天赋旧规则 |
| `scripts/services/save_manager.gd` | 版本/引擎/校验和封套、临时写入读回、有效备份与替换、损坏恢复和错误结果 |
| `scripts/core/game_session.gd` | P6 初始化/接口、行动后自动保存、读档、动画期结算保存、从提交状态派生操作 ID |
| `scripts/main/game_shell.gd` | 重启继续、默认/隔离存档路径、待选事件恢复、退出保存失败保护与焦点恢复 |
| `scripts/ui/main_menu.gd` | 真实存档继续、重开替换说明、实际图鉴、退出请求协调 |
| `scripts/ui/alchemy_screen.gd` | 丹师/图鉴/存档三入口、章节、保存状态和天赋概率提示 |
| `scripts/ui/resource_hub.gd` | 晋升条件、研制费用、天赋三选一、结局、图鉴、存读档确认与结果，滚动位置与页签恢复 |
| `tests/test_progression.gd`、`test_save_load.gd`、`test_progression_ui.gd` | 成长/内容/概率/真实通关、存档故障注入、真实场景交互、退出失败与结局恢复 |
| `tests/helpers/progression_route.gd`、`tools/progression_demo.gd` | 只用正常命令的完整通关驱动及隔离复核检查点 |
| `tests/test_runner.gd` | 纳入 P6 服务/界面/存档，新增 progression-only 互斥专项 |
| `tests/test_content.gd`、`test_economy.gd`、`test_alchemy.gd`、`test_alchemy_ui.gd`、`test_resources_ui.gd` | 旧夹具适配九表/十二方、P6 引用约束，全部场景显式隔离真实用户存档 |
| `project.godot` | 版本元数据 0.1.6-p6 |
| `README.md`、`docs/CONTENT_SCHEMA.md`、`ALCHEMY_API.md`、`BALANCE.md`、`CHANGELOG.md` | 当前范围、操作、格式、候选数值及规则变化 |
| `docs/P6_PROGRESSION.md`、`SAVE_API.md`、`P6_REPORT.md` | 接口、恢复边界、操作路径与实际验证证据 |

新增脚本的 `.uid` 随代码提交。没有外部依赖、插件或新增 Autoload。原有六方的价格/基础概率、材料与装备数值不变；原始完整设计文档保持不变。

## 已实现与设计细化

- 丹童→一至九品→大宗师共十次认证，不能越级。累计历练、已炼/研制成就、符合品质的交付丹药及指定委托/异火均经过验证后一次提交；晋升扣丹，自动解锁 rank 类丹方和既有境界商品。
- 三品、六品、九品各一次三选一：稳丹天赋影响 stable 的成功/返还，烈火天赋影响 rush 的成功/极品转移，百草天赋改变定式研制折扣与稀有素材替代；每阶段只能选择一个，前一抉择未完不能晋下一阶。
- 主线有确定性“定式研制考核丹”路线，消耗公开药材和心得，产出指定品质与历练；完全不抽 RNG，不伪造概率炼丹结果，单独记录 research_crafts。失败开炉也能积累心得，素材可走稳定秘境，避免稀有品质/掉落永久卡主线。
- 本世基础图鉴记 12×4 品质发现，炼制/研制都有效，出售与交付不清除。最终认证固定 `ending_grandmaster` 的通关统计，之后可继续当前修行收集，统计快照不重复结算。
- 行动后自动存档和手动存读档；山门识别真实有效档，重启继续不再发起始资源。新修行/手动读档均有明确替换说明。
- 默认存档 user://run_save.json，校验和和引擎/版本约束、整数规范化、临时读回、有效备份与替换后检查；坏档尝试备份，双坏档保留原文件并给出错误，不静默新开。
- 保存失败保留脏内存和原有效档，页脚/存档页提示；退出前保存失败允许返回重试或明确放弃未存进度，不直接退出丢数据。
- 炼丹在动画前已结算，存档记录该结果与扣费状态，重启不重掷或重复发奖；原秘境 instance_id、待选天赋及结局可恢复。三个 RNG seed/state 和操作防重放记录完整保存。

候选门槛、六方与天赋数值均已写 BALANCE.md。只扩充通关必需丹方，未提前扩充至 P8 正式版 25 方或完整内容量。

## 实际自动验证

在项目根目录执行；Godot 使用访问本机字体所需的权限。测试不写默认用户进度，全部场景指定空/隔离存档路径。

| 命令 | 实际结果 |
|---|---|
| `godot --headless --version` | 退出码 0；4.5.stable.official.876b29033 |
| `godot --headless --path . --editor --quit --log-file /tmp/alchemy-p6-import-final.log` | 退出码 0；新脚本注册与资源导入完成 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p6-tests-final.log` | 退出码 0；**650 项检查，0 失败** |
| `godot --headless --path . --script res://tools/validate_content.gd --log-file /tmp/alchemy-p6-content-final.log` | 退出码 0；九表 12 / 9 / 3 / 2 / 3 / 5 / 5 / 11 / 9，共 59 条 |
| `godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p6-startup-final.log -- --save-path res://test-output/p6-no-save.json` | 退出码 0；隔离无存档路径主场景正常启动 |
| `godot --headless --path . --script res://tools/progression_demo.gd --log-file /tmp/alchemy-p6-route.log -- --write-checkpoints` | 退出码 0；正常命令完整通关，写出隔离复核档 |
| `godot --headless --path . --script res://tools/progression_demo.gd --log-file /tmp/alchemy-p6-final-ready.log -- --prepare-final` | 退出码 0；正常命令备齐九品最终复核药材/心得，56 心得、待选九品天赋 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p6-progression-fixed2.log -- --progression-only` | 中间版本 107 项通过；最终回归增加两组天赋统计及一项坏历史记录类型检查，成长/存档组 110 项 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p6-ui.log -- --ui-only` | 中间版本 134 项通过；最终回归再增加退出保存失败/恢复焦点两项，UI 合计 136 项 |
| `git diff --check` | 退出码 0；无空白错误 |

完整 650 项：内容 110、经济 117、炼丹 85、P5 资源 92、P6 成长/存档 110、菜单 22、P4 UI/会话 49、P5 资源 UI 35、P6 UI 30。九表使旧内容临时文件检查新增两项；P5 508 项之后共增加 142 项。

重点覆盖非法/缺失/重复品阶与天赋组、引用与晋升前可用丹方、预览纯度、逐级认证/旧按钮/重放、品质与发现前置、研制消耗/溢出回滚、三个天赋效果/替代/上限/重选、完整通关与结局后继续；存档整数/RNG/历史、失败命令后 ID 一致性、动画/事件/天赋/结局恢复、坏版本/引擎/校验和/状态拒绝、临时写入中断、备份/正式替换失败、替换后损坏恢复及两档均坏的中文错误。UI 验证双击、焦点、读档确认、退出失败可重试、960×540/1280×720/1920×720 新页边界。

## 可达性与概率结果

所有完整通关均从真实新状态出发，仅调用公开会话命令，无资源、品阶、经验或丹药注入。使用固定种子 20261119：

| 天赋组合 | 概率开炉数 | 行动数 | 结果 |
|---|---:|---:|---|
| 三次百草衍化 | 241 | 581 | 标准结局，定式研制10次，真实完成基础委托与地心灵火路径 |
| 三次丹心稳固 | 421 | 1030 | 同上，完整状态验证通过 |
| 三次烈火淬丹 | 421 | 1030 | 同上，完整状态验证通过 |

三条验证脚本统一以基础 stable 炼制积累资金/心得，以确定性研制完成考核，证明三套天赋选择都不会阻断通关；不是最优打法、流派收益比较或真人时长。稳丹/冲品天赋激活后的数值效果另由精确预览检查和实际共用 roll 抽样验证。

新增两组各十万炉：三品稳丹构筑成功 74.722%（理论75%），三品冲品构筑 43.872%（44%）；全部四档成功后条件品质通过六倍标准误差门槛，成功率采用原有±1个百分点门槛，零概率要求精确无产出。完整回归也包含 P3 五组各十万炉和 P5 十万地点/各选项抽样，不重写历史 P3 产物。

## 实际图形核验

本机 Compatibility / OpenGL 4.1 / Apple M5。使用正常命令生成的隔离检查点，以下为实际正确启动命令：

```sh
open -na /Applications/Godot.app --args --path /Users/rinsay/projects/AlchemyThousands --resolution 1280x720 --position 80,80 --log-file /tmp/alchemy-p6-gui.log -- --save-path res://test-output/p6-demo/rank-3.json
open -na /Applications/Godot.app --args --path /Users/rinsay/projects/AlchemyThousands --resolution 960x540 --position 80,80 --log-file /tmp/alchemy-p6-gui-small.log -- --save-path res://test-output/p6-demo/final-ready.json
open -na /Applications/Godot.app --args --path /Users/rinsay/projects/AlchemyThousands --resolution 960x540 --position 80,80 --log-file /tmp/alchemy-p6-gui-restart.log -- --save-path res://test-output/p6-demo/final-ready.json
```

通过实际鼠标/键盘并读取窗口图像：

- 山门从磁盘继续至三品，显示历练379、心得0、灵石1114、待选天赋。三选一说明完整可读，选择百草衍化后只保留已选天赋。
- 图鉴显示真实发现5/48；存档页展示 UTC 时间，手动保存反馈成功；读取先展示覆盖确认，确认后资源保持、天赋不再可重选。
- 960×540 恢复九品待选档，历练3085、心得56、灵石7832；选第三层研究天赋后定式研制价格为25心得，配方允许灵草×24替代缺少的灵芝/养魂露，另需赤血参×4。
- 拖动实际滚动条查看并执行定式研制，心得56→31、历练3085→3175、行动651→652，获得上品太初造化丹；认证按钮启用。
- 点击认证，晋升大宗师、行动653，展示标准结局。结算为概率开炉272次、定式研制10次、交委托1单、历练3175。该复核路线在九品额外积累资源以保留待选天赋，区别于最短验证脚本的241炉。
- 退出并重启同一隔离存档，继续后仍为大宗师，灵石7832、心得31、历练3175、结局统计完整一致，未再给初始奖励或重复结算。

图形检查以检查点执行节点和重启恢复，未声称从零手工玩完241炉；从零可达性由正常命令自动路线验证。三份图形日志和最终自动日志已读取检查，无脚本或渲染错误。最终保留最小窗口的结局面板供查看。未触碰默认 user:// 修行进度。

## 问题与处理

- Godot JSON 将数字解析为 float，整数枚举/字典键不能直接当作 int 使用；先数值验证再规范化，存档封套与运行状态同样处理，并补类型错误和非法配置回归。
- 首次存档失败时新周目也必须保持脏标记，已在初始化设为待存，成功读回后才清除；故障注入确认可重试。
- 原会话计数器会因失败命令产生不落盘的编号空洞，改为从已提交操作记录派生下一 ID，读档后下一次真实炼丹回执保持一致。
- 存档检查改用 JSON.parse 的结构化错误，不以会在控制台打印错误的快捷解析处理预期坏档；错误数据被拒绝且不产生运行时异常。
- 动画中的资源已结算，保存时补入该炉历史，重启将其作为已完成记录，避免再次发奖/掷骰；待选事件按原实例恢复。
- 退出保存失败的返回路径需要恢复原模态焦点，按丹房当前 phase 选择正确焦点并加入真实场景重试检查。
- 静态考核引用新增后，旧“极端境界边界”夹具需使用不作为考核前置的测试丹方；仍检查原数值边界，同时保留新的晋升可达性约束。

## 范围边界与下一步

P6 达到：丹童到大宗师标准结局可达；剧情/炼丹动画不强制等待；三次天赋有效；图鉴与结局可查看；基础存读档、随机流延续和有效备份保护已验证。

本版图鉴/天赋均为本世数据；确认新修行会重置，不提供轮回或永久 MetaSave。未实现传承、天地变数、变异、隐藏结局、跨版本存档迁移、正式版全部内容、最终美术音效、Windows 实机/导出测试或断电全窗口原子保证；未完成真人时长与 P8 平衡验收。

下一阶段 **P7：轮回与元进度**，实现结局后主动轮回、永久记录、传承、世界规则和跨周目安全保存。

本阶段提交说明：`feat: add single-run progression endings and reliable saves for P6`。
