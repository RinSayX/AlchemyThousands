# 百炼成丹 · Alchemy Thousands

单机、离线、2D UI 驱动的炼丹经营游戏。当前已完成 **P0～P7**，已打通丹童到大宗师、领取传承、轮回至下一世的完整流程，包含资源循环、天赋、永久图鉴、天地变数与统一跨世存档。P8 已新增经济模拟与首批平衡报告，正式内容和数值仍保留 P7 基线。

## 引擎与启动

本机实测版本：**Godot 4.5 stable**，完整标识 `4.5.stable.official.876b29033`（见 `.godot-version`）。使用 GDScript 和 Compatibility 渲染器，无插件或第三方依赖。

在 Godot 中导入本目录的 `project.godot`，按 **F5** 运行主场景；或在本目录执行：

```sh
godot --headless --version
godot --path .
```

macOS 应用位于 `/Applications/Godot.app`；本机 `godot` 链接到其可执行文件。也可执行：

```sh
open -na /Applications/Godot.app --args --path "$PWD"
```

## 当前功能

- 国风主菜单：旧丹炉、山景、烟雾和流光，均由代码绘制为占位美术。
- “启程入宗”→“入丹房 · 点燃凡火”，进入真实炼丹房；山门及丹房均可查看实际丹药品质图鉴。
- 行动后自动保存，返回山门或关闭程序后均可继续；损坏时尝试有效备份。重新入宗保留永久记录和本世携带传承/世界，只重置本世修行；完成结局后通过轮回开启下一世。
- 设置支持沉静模式（本机保存）及全屏切换（本次会话）。
- Tab / Shift+Tab 导航，Enter / Space 确认，Esc 关闭弹层；关闭后恢复焦点。
- 1280×720 设计视口，960×540 最小窗口，可调整窗口大小。
- 静态配置：12 丹方、9 材料（含丹渣）、3 丹炉、2 异火、3 消耗品、5 委托模板、5 秘境事件、11 个品阶、9 个天赋、9 项传承、6 条天地变数，共 74 条。
- ContentDB 支持 ID 查询、深副本隔离和全量校验后替换缓存；非法配置提供字段路径诊断。
- 三栏炼丹房支持丹方搜索/品阶筛选、材料与缺口、装备/符箓/策略、公开概率和成本、购药/购符、习得可购买丹方、出售全部丹药与丹渣。
- 开炉立即锁定操作，五秒动画可跳过；快速揭晓与沉静模式跳过等待。结果弹层和最近二十炉记录来自引擎回执，动画不再次掷骰或提前透露结果。
- 丹房底部进入坊市、委托、秘境、采药、丹师、图鉴、存档、轮回八个页签；坊市覆盖材料、符箓、丹方、丹炉和异火分类，支持数量购买与普通物品出售，按境界及来源限制获取。
- 委托模板生成独立实例；交付实际消耗达标丹药并一次发奖，高品质可替代低品质，可重复委托需重新接取。
- 秘境支持公开权重随机寻访或指定地点，卡片先展示费用、成功率与两种结果；百年灵芝、养魂露有确定性获取选项，地心灵火有一品境界确定性路径。
- 免费采药只补齐一炉聚灵丹的缺少材料，每趟三次，耗尽可免费休整，无金钱或实时等待门槛；连续失败也可出售丹渣恢复购买资金。
- 丹童至九品再到大宗师逐级认证，检查历练、已炼/研制成就、考核丹药及阶段委托/异火前置；晋升解锁丹方和已有境界商品。
- 三品、六品、九品各三选一天赋：稳妥策略成功/返还、冲品策略风险/品质转移、定式研制折扣/普通药材替代稀有素材。
- 当前考核丹可消耗公开药材与研究心得确定性研制，获得指定品质和历练；不使用随机流，不增加概率炼丹次数。失败开炉也有研究收益，通关不要求随机抽中极品。
- 完成大宗师认证展示标准结局和固定通关统计，可留在本世继续图鉴收集；交付与出售不清除品质发现。
- 结局永久归档，每世选择一项新传承；第一世后可携带一项，完成两世后可携带两项。九项全部解锁后领取永久心得，后续开局最多额外 10 点。
- 第一世固定标准世界；第二世起生成两条相容变数，至少一条机会规则。预览与取消不消耗实际随机流，刷新和切换传承不会重抽世界。
- 轮回明确确认后重置灵石、背包、境界、临时天赋、丹方权限和本世记录，保留永久图鉴、传承、成就、历史成绩及跳过序章/快速揭晓便利；保存完整新旧世关系成功后才切换。
- 业务层支持材料/消耗品堆叠、丹药分品质堆叠、购买出售和批量交易；包含境界校验、操作防重放和失败不改状态的事务边界。
- 炼丹服务提供概率/缺口预览、三种策略、装备/符箓效果、成功后品质与多丹、失败回收和丹渣、经验/研究/统计。RNG 三流独立，支持种子和状态快照；失败事务不消耗实际随机流。

中文使用操作系统字体：macOS 苹方/宋体、Windows 微软雅黑/宋体，另提供 Noto 字体候选。目标平台为 Windows/macOS；尚未验证 Windows 排版及导出。

设置位于 Godot `user://settings.cfg`。本机路径为 `~/Library/Application Support/AlchemyThousands/settings.cfg`，不属于项目目录，也不包含游戏进度。修行进度位于同一用户目录的 `run_save.json`，上一有效版本在 `run_save.json.bak`。schema 2 在同一封套保存本世、永久记录和最近炉次；支持读取 P6 schema 1 并安全迁移，使用版本/引擎/校验和、临时文件读回与备份替换。

## 验证

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tools/economy_demo.gd
godot --headless --path . --script res://tools/alchemy_demo.gd
godot --headless --path . --script res://tools/progression_demo.gd
godot --headless --path . --script res://tools/rebirth_demo.gd
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --quit-after 3
```

测试入口无需测试框架，返回非零退出码表示检查失败；不写入真实用户偏好。可添加 `-- --content-only`、`-- --economy-only`、`-- --alchemy-only`、`-- --resources-only`、`-- --progression-only`、`-- --rebirth-only`、`-- --balance-only` 或 `-- --ui-only`，八种专项参数互斥。资源专项含零资源恢复和探索抽样；成长专项含真实通关和存档故障；轮回专项含两世通关、传承/变数、复现、迁移和保存故障；平衡专项核验成本、收益、回收取整、模拟确定性、真实事务和统计口径；UI 专项覆盖轮回确认/取消/失败重试及第二世重启。所有场景测试均禁用默认用户存档或使用隔离测试路径。最新全量结果为 **826 项检查，0 失败**，见 `docs/P8_REPORT.md`。

概率报告可重新生成：

```sh
godot --headless --path . --script res://tools/alchemy_simulator.gd -- res://docs/P3_PROBABILITY_RESULTS.json
```

每组 100000 炉、五组合计 500000 炉，使用与实际执行相同的结果抽样函数；不代表已经完成经济平衡或真人时长验证。

P8 独立经济实验可运行：

```sh
godot --headless --path . --script res://tools/balance_simulator.gd -- --samples 10000 --seeds 8 --output res://docs/P8_BALANCE_RESULTS.json
godot --headless --path . --script res://tools/balance_sensitivity.gd -- --output res://docs/P8_BUILD_SENSITIVITY.json
```

包含首世、九传承、全部相容机会世界对和双传承的条件化场景；比较稳丹、冲品、回收与研究对照。实际通关事务与单炉期望探针分开，保留原始数据、现金收支、阶段指标、破产恢复及输入哈希。操作说明与假设见 `docs/P8_SIMULATOR.md`，结论和待确认提案见 `docs/P8_BALANCE_REPORT.md`。模拟不能代替真人时长。

## 目录与文档

- `scenes/`：主场景、菜单与炼丹房；`scripts/ui/`：呈现、输入和占位美术。
- `scripts/main/game_shell.gd`：场景切换；`scripts/core/game_session.gd`：持有本次状态、调用服务并返回界面用副本。
- `scripts/autoload/app_settings.gd`：唯一 Autoload，只管理呈现偏好。
- `scripts/core/content_db.gd`、`content_validator.gd`：由调用方显式持有的内容库与纯校验器，不依赖 UI。
- `scripts/services/`：货币、背包和商店服务；`scripts/core/transaction_result.gd`、`pill_stack.gd`：统一结果与普通丹药堆叠格式。
- `themes/`、`assets/icons/`：基础主题与原创矢量图标。
- `data/`：十一张 schema-v1 JSON 表；`tools/validate_content.gd`：独立内容校验入口。
- `tests/`：内容与无头菜单集成测试；临时数据写入被 Git 忽略的 `test-output/` 并在正常结束时清理。
- `docs/CONTENT_SCHEMA.md`：字段格式、数值范围、接口和失败处理。
- `docs/ECONOMY_API.md`：经济状态、交易接口、操作 ID、防溢出和丹药定价规则。
- `docs/ALCHEMY_API.md`：炼丹接口、RNG 复现、快照、回收及统一结算；`docs/P3_PROBABILITY_RESULTS.json`：实际统计产物。
- `docs/P4_UI.md`：炼丹操作、会话和动画边界；`docs/P5_RESOURCES.md`：资源操作、服务接口、委托实例和探索随机流。
- `docs/P6_PROGRESSION.md`、`SAVE_API.md`：晋升、研制、天赋和存档接口/格式/恢复边界。
- `docs/P7_REBIRTH.md`、`P7_REPORT.md`：永久档案、传承、世界生成、跨世事务及实际验收结果。
- `tools/balance/`、`balance_simulator.gd`、`balance_sensitivity.gd`：P8离线分析工具；`docs/P8_BALANCE_RESULTS.json`、`P8_BUILD_SENSITIVITY.json`：可复查的生成数据。
- `docs/GAME_DESIGN.md`、`TECHNICAL_DESIGN.md`、`DEVELOPMENT_PLAN.md`、`BALANCE.md`：从完整设计文档拆出的基线；保留原章节编号。
- `AGENTS.md`：依据原设计第 17 章建立的项目约定。

根目录的原始设计文档保持不变。设计文档中的功能、概率和时长是目标，不代表已实现或实测。

## 后续阶段

接下来继续 **P8 内容与平衡**：审阅本批报告的假设、风险与提案，确认依据后再调整配置、扩充内容并重新模拟。现有 12 张丹方已覆盖一至九品通关，仍未扩充至正式内容目标；隐藏结局、变异、首世 4～8 小时及后续 2～3 小时真人时长、最终美术音效和 Windows 导出尚未验证或完成。
