# 百炼成丹 · Alchemy Thousands

单机、离线、2D UI 驱动的炼丹经营游戏。当前已完成 **P0～P4**，可以在界面中完成选方、购药、炼丹、售丹的核心循环；完整成长、任务和存档仍在后续阶段。

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
- “启程入宗”→“入丹房 · 点燃凡火”，进入真实炼丹房；图鉴仍为占位空状态。
- 返回山门后可继续本次修行；关闭程序后进度不保留。重新入宗会先提示重置后果，尚无正式游戏存档。
- 设置支持沉静模式（本机保存）及全屏切换（本次会话）。
- Tab / Shift+Tab 导航，Enter / Space 确认，Esc 关闭弹层；关闭后恢复焦点。
- 1280×720 设计视口，960×540 最小窗口，可调整窗口大小。
- 静态配置：6 丹方、9 材料（含丹渣）、3 丹炉、2 异火、3 消耗品，共 23 条。
- ContentDB 支持 ID 查询、深副本隔离和全量校验后替换缓存；非法配置提供字段路径诊断。
- 三栏炼丹房支持丹方搜索/品阶筛选、材料与缺口、装备/符箓/策略、公开概率和成本、购药/购符、习得可购买丹方、出售全部丹药与丹渣。
- 开炉立即锁定操作，五秒动画可跳过；快速揭晓与沉静模式跳过等待。结果弹层和最近二十炉记录来自引擎回执，动画不再次掷骰或提前透露结果。
- 业务层支持材料/消耗品堆叠、丹药分品质堆叠、购买出售和批量交易；包含境界校验、操作防重放和失败不改状态的事务边界。
- 炼丹服务提供概率/缺口预览、三种策略、装备/符箓效果、成功后品质与多丹、失败回收和丹渣、经验/研究/统计。RNG 三流独立，支持种子和状态快照；失败事务不消耗实际随机流。

中文使用操作系统字体：macOS 苹方/宋体、Windows 微软雅黑/宋体，另提供 Noto 字体候选。目标平台为 Windows/macOS；尚未验证 Windows 排版及导出。

设置位于 Godot `user://settings.cfg`。本机路径为 `~/Library/Application Support/AlchemyThousands/settings.cfg`，不属于项目目录，也不包含游戏进度。

## 验证

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tools/economy_demo.gd
godot --headless --path . --script res://tools/alchemy_demo.gd
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --quit-after 3
```

测试入口无需测试框架，返回非零退出码表示检查失败；不写入真实用户偏好。可添加 `-- --content-only`、`-- --economy-only`、`-- --alchemy-only` 或 `-- --ui-only`，四种专项参数互斥。UI 专项含菜单、炼丹房和会话检查。旧 economy_demo 注入测试丹药；alchemy_demo 使用真实炼丹结果。最新记录见 `docs/P4_REPORT.md`。

概率报告可重新生成：

```sh
godot --headless --path . --script res://tools/alchemy_simulator.gd -- res://docs/P3_PROBABILITY_RESULTS.json
```

每组 100000 炉、五组合计 500000 炉，使用与实际执行相同的结果抽样函数；不代表已经完成经济平衡或真人时长验证。

## 目录与文档

- `scenes/`：主场景、菜单与炼丹房；`scripts/ui/`：呈现、输入和占位美术。
- `scripts/main/game_shell.gd`：场景切换；`scripts/core/game_session.gd`：持有本次状态、调用服务并返回界面用副本。
- `scripts/autoload/app_settings.gd`：唯一 Autoload，只管理呈现偏好。
- `scripts/core/content_db.gd`、`content_validator.gd`：由调用方显式持有的内容库与纯校验器，不依赖 UI。
- `scripts/services/`：货币、背包和商店服务；`scripts/core/transaction_result.gd`、`pill_stack.gd`：统一结果与普通丹药堆叠格式。
- `themes/`、`assets/icons/`：基础主题与原创矢量图标。
- `data/`：五张 schema-v1 JSON 表；`tools/validate_content.gd`：独立内容校验入口。
- `tests/`：内容与无头菜单集成测试；临时数据写入被 Git 忽略的 `test-output/` 并在正常结束时清理。
- `docs/CONTENT_SCHEMA.md`：字段格式、数值范围、接口和失败处理。
- `docs/ECONOMY_API.md`：经济状态、交易接口、操作 ID、防溢出和丹药定价规则。
- `docs/ALCHEMY_API.md`：炼丹接口、RNG 复现、快照、回收及统一结算；`docs/P3_PROBABILITY_RESULTS.json`：实际统计产物。
- `docs/P4_UI.md`：玩家操作、会话和动画边界。
- `docs/GAME_DESIGN.md`、`TECHNICAL_DESIGN.md`、`DEVELOPMENT_PLAN.md`、`BALANCE.md`：从完整设计文档拆出的基线；保留原章节编号。
- `AGENTS.md`：依据原设计第 17 章建立的项目约定。

根目录的原始设计文档保持不变。设计文档中的功能、概率和时长是目标，不代表已实现或实测。

## 后续阶段

下一步 **P5 资源与任务闭环**：材料商店、宗门委托、秘境事件、免费采药和零资源恢复路线。P4 只提供与当前丹方相关的购药/符箓和售丹操作，尚无完整商店/背包页、委托、探索、晋升、正式存档或轮回，也未接入变异和天地规则。当前为丹童阶段与可购买基础丹方，不宣称已达到 20～40 分钟原型或完整一周目。
