# P0 工程初始化交付记录

日期：2026-11-18。范围依据原始设计第 16.2、18.1、20 章：本次完成 P0，不提前实现 P1～P9。

## 文档分析与实施决策

项目初始仅有完整设计文档，没有 Godot 工程或 Git 仓库。设计的核心是公开概率炼丹、经营、装备构筑和轮回，按 P0～P9 分阶段实现。规则与 UI 必须分离，预览不消耗 RNG，交易先验证后提交，失败和零资源都要有恢复路径。

本次先建立可启动、可验证的导航外壳，为后续纯业务层保留空间。只添加实际使用的 AppSettings Autoload；ContentDB、游戏状态、RNG、存档和各业务服务在对应阶段再建立，避免空壳单例被误认为功能已完成。

本机 `godot` 位于 `/usr/local/bin/godot`，链接到 `/Applications/Godot.app/Contents/MacOS/Godot`。实测版本为 `4.5.stable.official.876b29033`，已写入 `.godot-version`；`project.godot` 声明 4.5，选用 Compatibility 渲染器。未安装、替换或下载引擎。

## 文件清单

| 文件 | 用途 |
|---|---|
| `.godot-version`、`project.godot` | 引擎基准、窗口、主题、主场景与最小 Autoload |
| `.gitignore`、`.editorconfig`、`.gitattributes` | 排除缓存/构建/凭据、统一文本格式，保留 Markdown 硬换行 |
| `AGENTS.md` | 原设计第 17 章项目约定，更新项目名和本机引擎基准 |
| `README.md` | 启动、验证、目录、当前范围与下一阶段 |
| `docs/GAME_DESIGN.md` | 原设计第 1～11 章 |
| `docs/TECHNICAL_DESIGN.md` | 原设计第 12～15 章 |
| `docs/DEVELOPMENT_PLAN.md` | 原设计第 16、18～20 章 |
| `docs/BALANCE.md` | 原设计第 5、7、10 章数值基线 |
| `docs/CHANGELOG.md`、`docs/P0_REPORT.md` | 实施范围、验证和阶段记录 |
| `scenes/main/main.tscn` | 主场景入口 |
| `scenes/screens/main_menu.tscn` | 可独立运行的主菜单场景 |
| `scripts/ui/main_menu.gd` | 菜单、引导/图鉴占位页、设置弹层与键盘导航 |
| `scripts/ui/ink_landscape.gd` | 山景、丹炉与确定性装饰动画，无玩法随机数 |
| `scripts/autoload/app_settings.gd` | 沉静模式的本机偏好与变更信号 |
| `themes/alchemy_theme.tres` | 颜色、系统中文字体、控件状态与焦点样式 |
| `assets/icons/cauldron.svg` | 原创占位矢量图标 |
| `tests/test_runner.gd` | 无依赖的 P0 无头集成冒烟测试 |
| `data/.gitkeep`、`tools/.gitkeep` | 后续配置与数值模拟目录 |

Godot 生成的脚本 `.uid` 和 SVG `.import` 设置一并保留；`.godot/` 缓存不进入版本控制。根目录原始完整设计文档未修改。

## 已实现与未实现

已实现：可运行主菜单，中文主题和占位美术，入宗章节预览，图鉴空状态，无存档时禁用继续，沉静模式及设置写入错误提示，会话内全屏切换，Esc 关闭弹层和焦点恢复，最小窗口及宽屏适配。

未实现：P1 静态配置/ContentDB/验证器；P2 背包/交易；P3 概率引擎；P4 炼丹房；后续委托、秘境、晋升、存档和轮回。点击入宗只显示序章，不会创建周目。没有宣称实现 20～40 分钟原型或正式游戏。

## 实际执行的验证

以下命令在项目根目录执行；日志参数仅用于把诊断输出写入 `/tmp`。

| 命令 | 结果 |
|---|---|
| `godot --headless --version` | 退出码 0；`4.5.stable.official.876b29033` |
| `godot --headless --help` | 退出码 0；核对本机命令行支持的选项 |
| `godot --headless --path . --editor --quit --log-file /tmp/alchemy-p0-import.log` | 退出码 0；导入资源及解析脚本正常 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p0-tests.log` | 退出码 0；**22 项通过，0 失败** |
| `godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p0-startup.log` | 退出码 0；真实主场景无头启动并退出 |
| `open -na /Applications/Godot.app --args --path /Users/rinsay/projects/AlchemyThousands --position 80,80 --log-file /tmp/alchemy-p0-ui.log` | macOS 图形启动成功；OpenGL Compatibility / Apple M5 |
| `open -na /Applications/Godot.app --args --path /Users/rinsay/projects/AlchemyThousands --resolution 960x540 --position 80,80 --log-file /tmp/alchemy-p0-small.log` | 最小窗口图形启动成功 |

自动检查覆盖：场景加载、初始焦点、禁用继续、引导/图鉴/设置入口、Esc 关闭、焦点恢复、不可用按钮不参与键盘导航、沉静模式停止动画，以及 960×540 / 1280×720 / 1600×900 / 1920×720 下菜单和章节面板的布局边界。测试不写真实偏好文件。

实际图形检查：在 1280×720 查看中文标题、主菜单、丹炉、章节引导、图鉴和设置；使用 Enter/Tab/Esc 导航。在 960×540 查看菜单、打开章节引导并返回，未见文本截断或控件溢出。保留最小窗口的主菜单供查看。图形运行日志无脚本或渲染错误。

未执行：Windows 实机和导出；全屏切换的显示器兼容性；偏好文件损坏/写入失败的故障注入；真人游玩时长。P0 无音效和正式美术，使用目标系统字体，Linux 缺少 CJK 字体时需另行配置。

## 问题与处理

- 首次图形模式版本查询触发 macOS 图形初始化噪声，改用 `--headless --version` 得到版本；未将环境噪声当成项目错误。
- 命令行图形进程未被窗口检查工具正确识别，改用 macOS `open -na` 启动，并清理多余的后台实例。
- 窗口检查后修正禁用“继续修行”的键盘焦点策略，并增加回归检查。
- 修正宽屏缩放时丹炉阴影的坐标变换，并扩展布局检查到最小窗口及宽屏。
- 普通沙箱不允许创建 `.git`，通过受控提权建立本地仓库；未连接远程仓库或推送。

## 设计变更及下一阶段

唯一基准细化是将建议的 Godot 4.x 锁定为本机 Godot 4.5 stable。玩法、数值、经济和目标时长没有变更。设计拆分文档是规格，完成状态以本报告及 CHANGELOG 为准。

下一阶段 P1：提供 6 丹方、8 材料、3 丹炉、2 异火、3 消耗品 JSON，实现 ContentDB、ContentValidator，验证唯一 ID、引用、权重、品阶、价格与范围；不把概率公式放入 UI。

本阶段提交说明：`chore: initialize Godot 4.5 project and P0 menu shell`。
