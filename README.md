# 百炼成丹 · Alchemy Thousands

单机、离线、2D UI 驱动的炼丹经营游戏。当前已完成 **P0～P3：工程、静态内容、经济服务与炼丹引擎**；尚未将真实炼丹接入界面。

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
- “启程入宗”打开第一章引导占位页；图鉴显示空状态。
- 没有游戏存档时禁用“继续修行”。P0 不创建周目或游戏存档。
- 设置支持沉静模式（本机保存）及全屏切换（本次会话）。
- Tab / Shift+Tab 导航，Enter / Space 确认，Esc 关闭弹层；关闭后恢复焦点。
- 1280×720 设计视口，960×540 最小窗口，可调整窗口大小。
- 静态配置：6 丹方、9 材料（含丹渣）、3 丹炉、2 异火、3 消耗品，共 23 条。
- ContentDB 支持 ID 查询、深副本隔离和全量校验后替换缓存；非法配置提供字段路径诊断。
- 业务层支持材料/消耗品堆叠、丹药分品质堆叠、购买出售和批量交易；包含境界校验、操作防重放和失败不改状态的事务边界，尚未接入菜单。
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

测试入口无需测试框架，返回非零退出码表示检查失败；不写入真实用户偏好。可添加 `-- --content-only`、`-- --economy-only` 或 `-- --alchemy-only`，三种专项参数互斥。旧 economy_demo 注入测试丹药；新增 alchemy_demo 使用真实炼丹结果完成购买→开炉→出售。实际结果见 `docs/P3_REPORT.md`；已有菜单图形检查记录见 `docs/P0_REPORT.md`。

概率报告可重新生成：

```sh
godot --headless --path . --script res://tools/alchemy_simulator.gd -- res://docs/P3_PROBABILITY_RESULTS.json
```

每组 100000 炉、五组合计 500000 炉，使用与实际执行相同的结果抽样函数；不代表已经完成经济平衡或真人时长验证。

## 目录与文档

- `scenes/`：主场景和菜单场景；`scripts/ui/`：导航和占位绘制。
- `scripts/autoload/app_settings.gd`：唯一 Autoload，只管理呈现偏好。
- `scripts/core/content_db.gd`、`content_validator.gd`：由调用方显式持有的内容库与纯校验器，不依赖 UI。
- `scripts/services/`：货币、背包和商店服务；`scripts/core/transaction_result.gd`、`pill_stack.gd`：统一结果与普通丹药堆叠格式。
- `themes/`、`assets/icons/`：基础主题与原创矢量图标。
- `data/`：五张 schema-v1 JSON 表；`tools/validate_content.gd`：独立内容校验入口。
- `tests/`：内容与无头菜单集成测试；临时数据写入被 Git 忽略的 `test-output/` 并在正常结束时清理。
- `docs/CONTENT_SCHEMA.md`：字段格式、数值范围、接口和失败处理。
- `docs/ECONOMY_API.md`：经济状态、交易接口、操作 ID、防溢出和丹药定价规则。
- `docs/ALCHEMY_API.md`：炼丹接口、RNG 复现、快照、回收及统一结算；`docs/P3_PROBABILITY_RESULTS.json`：实际统计产物。
- `docs/GAME_DESIGN.md`、`TECHNICAL_DESIGN.md`、`DEVELOPMENT_PLAN.md`、`BALANCE.md`：从完整设计文档拆出的基线；保留原章节编号。
- `AGENTS.md`：依据原设计第 17 章建立的项目约定。

根目录的原始设计文档保持不变。设计文档中的功能、概率和时长是目标，不代表已实现或实测。

## 后续阶段

下一步 **P4 炼丹房 UI**：丹方列表、装备/符箓/策略选择、概率与成本、开炉反馈和最近记录，接入现有服务完成玩家可操作的循环。当前尚未实现真实炼丹/商店/背包界面、委托、探索、晋升、正式游戏存档或轮回。炼丹引擎为内存业务层；变异内容和天地规则尚未接入。
