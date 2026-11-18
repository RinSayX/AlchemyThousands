# 百炼成丹 · Alchemy Thousands

单机、离线、2D UI 驱动的炼丹经营游戏。当前已完成 **P0 工程初始化与 P1 静态内容及校验**，还不是可游玩的炼丹原型。

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
- 静态配置：6 丹方、8 材料、3 丹炉、2 异火、3 消耗品，共 22 条。
- ContentDB 支持 ID 查询、深副本隔离和全量校验后替换缓存；非法配置提供字段路径诊断。

中文使用操作系统字体：macOS 苹方/宋体、Windows 微软雅黑/宋体，另提供 Noto 字体候选。目标平台为 Windows/macOS；尚未验证 Windows 排版及导出。

设置位于 Godot `user://settings.cfg`。本机路径为 `~/Library/Application Support/AlchemyThousands/settings.cfg`，不属于项目目录，也不包含游戏进度。

## 验证

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tools/validate_content.gd
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --quit-after 3
```

测试入口无需测试框架，返回非零退出码表示检查失败；不写入真实用户偏好。加 `-- --content-only` 可只运行内容检查。实际结果见 `docs/P1_REPORT.md`；已有菜单图形检查记录见 `docs/P0_REPORT.md`。

## 目录与文档

- `scenes/`：主场景和菜单场景；`scripts/ui/`：导航和占位绘制。
- `scripts/autoload/app_settings.gd`：唯一 Autoload，只管理呈现偏好。
- `scripts/core/content_db.gd`、`content_validator.gd`：由调用方显式持有的内容库与纯校验器，不依赖 UI。
- `themes/`、`assets/icons/`：基础主题与原创矢量图标。
- `data/`：五张 schema-v1 JSON 表；`tools/validate_content.gd`：独立内容校验入口。
- `tests/`：内容与无头菜单集成测试；临时数据写入被 Git 忽略的 `test-output/` 并在正常结束时清理。
- `docs/CONTENT_SCHEMA.md`：字段格式、数值范围、接口和失败处理。
- `docs/GAME_DESIGN.md`、`TECHNICAL_DESIGN.md`、`DEVELOPMENT_PLAN.md`、`BALANCE.md`：从完整设计文档拆出的基线；保留原章节编号。
- `AGENTS.md`：依据原设计第 17 章建立的项目约定。

根目录的原始设计文档保持不变。设计文档中的功能、概率和时长是目标，不代表已实现或实测。

## 后续阶段

下一步 **P2 背包与经济**：基于现有配置实现背包堆叠、购买出售、批量交易和事务校验；确保失败不改变状态，不出现负余额或负库存。之后按 P3 炼丹引擎、P4 炼丹 UI 推进核心闭环。当前尚未实现背包、交易、炼丹、委托、探索、晋升或轮回；P1 配置中的解锁条件和效果只是定义，尚未执行。
