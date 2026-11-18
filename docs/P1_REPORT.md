# P1 静态内容与校验交付记录

日期：2026-11-18。引擎仍为本机 `4.5.stable.official.876b29033`。本次仅执行设计第 16.3、18.2 节的 P1，不进入 P2 交易或 P3 炼丹。

## 文件清单与实现

| 文件 | 修改内容 |
|---|---|
| `data/recipes.json` | 聚灵丹、止血丹、凝神丹、淬体丹、筑基丹、养魂丹，共 6 条 |
| `data/materials.json` | 灵草、青花、止血草、凝神花、赤血参、铁精砂、百年灵芝、养魂露，共 8 条 |
| `data/furnaces.json` | 凡铁丹炉、青木灵炉、赤炎丹炉，共 3 条 |
| `data/flames.json` | 凡火、地心灵火，共 2 条 |
| `data/consumables.json` | 稳丹符、聚灵符、护炉玉，共 3 条 |
| `scripts/core/content_db.gd` | 五表读取、JSON 解析、校验后整体提交缓存、ID/分类查询、整数转换与深副本隔离 |
| `scripts/core/content_validator.gd` | 纯校验器，聚合带代码、字段路径和中文信息的诊断 |
| `tools/validate_content.gd` | 独立无头校验入口，可指定其他完整配置目录 |
| `tests/test_content.gd` | 正常配置、坏数据、查询隔离、缓存重载、临时文件故障测试 |
| `tests/test_runner.gd` | 纳入 P1 内容测试，增加 `--content-only`，保留全部 P0 检查 |
| `project.godot` | 阶段版本元数据更新为 `0.1.1-p1`，引擎、主场景和 Autoload 不变 |
| `README.md` | 当前阶段、验证命令、目录与 P2 下一步 |
| `docs/CONTENT_SCHEMA.md` | 五类字段、约束、接口、错误语义、后续导出注意事项 |
| `docs/BALANCE.md` | 记录首批候选价格与装备效果，注明尚未做平衡模拟 |
| `docs/CHANGELOG.md`、`docs/P1_REPORT.md` | 阶段交付与实际验证记录 |
| `data/.gitkeep`、`tools/.gitkeep` | 目录已有实际文件，删除占位标记 |

新增 GDScript 的 `.uid` 文件随代码提交。原始完整设计文档、现有界面和 AGENTS.md 未修改。

ContentDB 采用显式实例持有的 RefCounted 类，后续可直接注入业务服务，不新增尚无界面使用方的全局单例。所有加载先解析并校验五张表，再构造完整新索引；成功才替换旧缓存，首次失败保持空库。查询和输入均与缓存隔离。

验证涵盖：必填及未知字段、全局唯一英文 ID、材料引用、四品质权重及总和、价格和材料数量的整数与上下限、品阶/境界、有限数值、概率及修正范围、标签、来源、解锁条件、商店可购性与买卖价格关系。未注册的特殊效果与脚本字符串均拒绝。

## 实际验证

均在项目根目录执行，无外部测试框架。

| 命令 | 实际结果 |
|---|---|
| `godot --headless --version` | 退出码 0，仍为 `4.5.stable.official.876b29033` |
| `godot --headless --path . --editor --quit --log-file /tmp/alchemy-p1-import.log` | 退出码 0，资源导入和脚本解析正常 |
| `godot --headless --path . --script res://tools/validate_content.gd --log-file /tmp/alchemy-p1-cli-valid.log` | 退出码 0，输出 6 / 8 / 3 / 2 / 3 条内容 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p1-tests.log` | 退出码 0，**128 项通过、0 失败**，含原有 22 项 P0 菜单检查 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p1-content-only.log -- --content-only` | 退出码 0，单独内容检查 **106 项通过、0 失败** |
| `godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p1-startup.log` | 退出码 0，主场景正常启动退出 |
| `godot --headless --path . --script res://tools/validate_content.gd --log-file /tmp/alchemy-p1-cli-invalid.log -- /tmp/alchemy-p1-invalid-v0q01ty6` | **预期退出码 1**；临时表加入不存在的材料引用，输出 `MISSING_REFERENCE recipes.items[0].materials.herb_missing` |

内容测试实际覆盖：重复 ID（同表及跨表）、缺材料、非法版本和根类型、缺字段及拼写错误、空数组/对象、不合规品阶/境界、负数/零数量/小数/超上限整数、布尔值及字符串冒充数字、NaN/无穷/权重溢出、零总权重、缺品质、未知标签/来源/效果、倒卖价差、未知查询、输入和输出深副本、合法边界值、无归一化要求的权重、多表错误聚合、失败首次加载、旧索引替换、缺文件和坏 JSON。临时文件测试使用 `test-output/`，正常结束后清理。

本阶段未改界面，不重复进行 P0 图形人工检查；菜单回归由原 22 项测试覆盖。没有运行经济/概率模拟、游戏导出或 Windows 实机测试，也没有注入操作系统级读盘中断与权限故障。

## 遇到的问题与修正

- Godot 4.5 不接受初稿中数组拼接构成的常量表达式；改为字面量字段表后解析通过。清理了首次解析失败遗留的无头进程。
- 首轮集成测试发现 JSON 中的整数在 Godot 中被解析成 float，导致整数字典基线比较失败。ContentDB 在验证后显式转换价格、数量、品阶及境界；不把错误的小数强制截断成有效值。修复后补充整数类型回归，完整测试 128 项全部通过。
- 为防止数值单项有限但求和溢出，品质权重和转移权重都检查总和有限性。

## 设计细化、未实现与下一步

原有聚灵丹 80% 成功率、14 灵石材料成本、65/25/9/1 品质权重，以及青木灵炉 +8 个百分点保持不变。未指定的首批素材、售价、装备/消耗品效果填入候选值并记录在 BALANCE.md，尚未确认经济平衡或体验时长。

CONTENT_SCHEMA.md 细化全局 ID、整数上限、解锁条件格式、按标签应用修正和品质转移的数据表达。探索条件暂不引用不存在的事件表；具体事件和保底路线在 P5 补齐。P1 中的效果字段只存数据，效果处理器、概率预览、抽取和材料返还在 P3 实现。没有声称玩家已能获取或使用这些物品。

P1 验收已达到：内容规模符合要求、可按 ID 查询、坏配置提供精确诊断、内容测试及既有回归通过。下一步 **P2 背包与经济服务**：物品堆叠、材料/消耗品购买、丹药出售、批量交易与失败不改状态的事务校验，不要求完整商店 UI。

本阶段提交说明：`feat: add validated static content database for P1`。
