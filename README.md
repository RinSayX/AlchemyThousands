# 百炼成丹 · Alchemy Thousands

单机、离线、2D UI 驱动的炼丹经营游戏。当前已完成 **P0 工程初始化**，还不是可游玩的炼丹原型。

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

中文使用操作系统字体：macOS 苹方/宋体、Windows 微软雅黑/宋体，另提供 Noto 字体候选。目标平台为 Windows/macOS；尚未验证 Windows 排版及导出。

设置位于 Godot `user://settings.cfg`。本机路径为 `~/Library/Application Support/AlchemyThousands/settings.cfg`，不属于项目目录，也不包含游戏进度。

## 验证

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --quit-after 3
```

测试入口无需测试框架，返回非零退出码表示检查失败；不写入真实用户偏好。实际结果和图形检查记录见 `docs/P0_REPORT.md`。

## 目录与文档

- `scenes/`：主场景和菜单场景；`scripts/ui/`：导航和占位绘制。
- `scripts/autoload/app_settings.gd`：唯一 Autoload，只管理呈现偏好。
- `themes/`、`assets/icons/`：基础主题与原创矢量图标。
- `data/`、`tools/`：保留后续静态数据和数值工具目录。
- `tests/`：无头集成冒烟测试。
- `docs/GAME_DESIGN.md`、`TECHNICAL_DESIGN.md`、`DEVELOPMENT_PLAN.md`、`BALANCE.md`：从完整设计文档拆出的基线；保留原章节编号。
- `AGENTS.md`：依据原设计第 17 章建立的项目约定。

根目录的原始设计文档保持不变。设计文档中的功能、概率和时长是目标，不代表已实现或实测。

## 后续阶段

下一步 **P1 静态数据与校验**：至少 6 丹方、8 材料、3 丹炉、2 异火、3 消耗品，实现 ContentDB 和引用/范围验证。之后按 P2 交易、P3 炼丹引擎、P4 炼丹 UI 推进核心闭环。当前尚未实现背包、交易、炼丹、委托、探索、晋升或轮回。
