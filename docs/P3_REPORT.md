# P3 炼丹引擎交付记录

日期：2026-11-18。运行基准保持本机 `4.5.stable.official.876b29033`。范围依据设计第 16.5、18.4 节：完成概率炼丹业务与验证，不进入 P4 界面。

## 文件清单

| 文件 | 修改内容 |
|---|---|
| `scripts/core/alchemy_rules.gd` | 纯概率计算、装备/标签/策略、品质转移、品质抽取及额外成丹 |
| `scripts/core/rng_context.gd` | 三条独立流、真实种子初始化、版本化快照、int64 字符串保存和原子恢复 |
| `scripts/core/state_transaction.gd` | 提交已经验证的候选状态，并生成独立回执快照 |
| `scripts/services/alchemy_service.gd` | 初始炼丹状态、资格验证、缺口/成本预览、执行、回收、奖励、统计、操作 ID、RNG 和 needs_save 一体提交 |
| `scripts/services/economy_service.gd` | P2 复用提交原语，扩展状态有 needs_save 时同步置脏标记 |
| `data/materials.json` | 新增丹渣，材料数 8→9，卖价 3、不可购买 |
| `scripts/core/content_validator.gd` | 新增 alchemy 材料来源枚举 |
| `tests/test_alchemy.gd` | 确定性、公式/边界、资源、奖励、回收、多丹、重放、溢出及检查点恢复回归 |
| `tests/helpers/sequence_rng.gd` | 仅供规则边界测试的固定抽样序列；实际业务不接收注入骰子 |
| `tests/alchemy_probability.gd` | 与实际执行共享抽样代码的五组十万炉统计检验 |
| `tests/test_content.gd`、`tests/test_runner.gd` | 更新内容规模断言，纳入 P3 和 alchemy-only，专项参数互斥 |
| `tools/alchemy_simulator.gd` | 独立概率检验和 JSON 报告输出 |
| `tools/alchemy_demo.gd` | 不注入丹药的真实购买→开炉→出售演示 |
| `project.godot` | 阶段版本 `0.1.3-p3`，其他项目设置保持原样 |
| `README.md`、`docs/CHANGELOG.md` | 当前功能、验证方式和下一阶段 |
| `docs/ALCHEMY_API.md` | 实际接口、状态、规则顺序、返回值与未接入部分 |
| `docs/CONTENT_SCHEMA.md`、`docs/ECONOMY_API.md`、`docs/BALANCE.md` | 来源、事务范围和数值细化同步 |
| `docs/P3_PROBABILITY_RESULTS.json`、`docs/P3_REPORT.md` | 实际生成的完整统计产物和阶段记录 |

新增脚本 `.uid` 随代码提交。根目录原设计文档、现有场景/界面和原有丹方/装备配置未修改，无外部插件或依赖。

## 完成的行为

提供 preview_alchemy / execute_alchemy。预览纯计算并公开成功率、品质条件分布、单炉极品率、消耗/缺口、返还与价值；执行重新计算快照，不采用 UI 自报概率或结果。

成功率加法修正并限幅 5%～95%，实现 normal/stable/rush、境界熟练、丹炉、异火、标签匹配及每炉一个符箓。品质从低向高转移，固定顺序、无负权重、不足时只转移实际可用量。成功后一次判品质，可选后续多丹抽取，额外一枚沿用品质。

失败产出真实丹渣、按比例向下取整返还材料、不返还符箓；成功/失败都结算公开的经验和研究。本世首次丹方/品质发现只发一次额外心得，同时维护尝试/成功/失败统计与行动数。

所有资源、产物、奖励、统计、操作历史和 RNG 快照在同一内存事务提交。错误、重复操作或抽取后发生的容量溢出都保持原状态不变，包括随机流；成功事务置 needs_save。三条 RNG 的 seed/state 用字符串无损经过 JSON，独立于 UI。规则和服务不依赖 Control。

## 实际运行与结果

| 命令 | 实际结果 |
|---|---|
| `godot --headless --version` | 退出码 0；`4.5.stable.official.876b29033` |
| `godot --headless --path . --editor --quit --log-file /tmp/alchemy-p3-import-final.log` | 退出码 0；资源扫描与注册完成 |
| `godot --headless --path . --script res://tests/test_runner.gd --log-file /tmp/alchemy-p3-tests-final.log` | 退出码 0；**330 项通过、0 失败** |
| `godot --headless --path . --script res://tools/alchemy_simulator.gd --log-file /tmp/alchemy-p3-simulation.log -- res://docs/P3_PROBABILITY_RESULTS.json` | 退出码 0；五组各 100000 炉，共 **500000 炉**，全部通过并写出报告 |
| `godot --headless --path . --script res://tools/alchemy_demo.gd --log-file /tmp/alchemy-p3-demo.log` | 退出码 0；真实炼丹闭环完成，重复操作拒绝 |
| `godot --headless --path . --script res://tools/validate_content.gd --log-file /tmp/alchemy-p3-content.log` | 退出码 0；内容规模为 6 / 9 / 3 / 2 / 3 |
| `godot --headless --path . --quit-after 3 --log-file /tmp/alchemy-p3-startup.log` | 退出码 0；主场景启动退出正常 |

完整检查包括 P1 内容 106 项、P2 经济 117 项、P3 炼丹 85 项和 P0 菜单 22 项。最终日志无脚本错误；没有把早期修复前的中间结果当作最终通过。

确定性检查实际覆盖：同种子同操作重放、额外预览不扰动、JSON RNG 快照往返、三流独立、临时二进制文件检查点读取后继续同一炉结果、恢复后重复操作拒绝、输出/丹渣/经验溢出时 RNG 回滚。公式/边界覆盖成功上下限、策略与标签、权重不足及巨大有限请求、零权重、精确判定边界、品质单次抽取和多丹后继抽取。临时检查点使用 test-output，正常结束后删除。

实际演示用种子 20261118：200 灵石买入 14 灵石药材后剩 186；展示 80% 成功率、成功后极品 1%、单炉极品 0.8%；真实开炉获得凡品聚灵丹×1和经验 10；按 26 出售，余额 212，行动数 1，needs_save=true；重复 action_id 返回 ACTION_DUPLICATE。没有像 P2 演示那样注入测试丹药，没有写入玩家存档。

## 概率检验

| 构筑 | 炉数 | 理论成功率 | 实测成功率 | 结论 |
|---|---:|---:|---:|---|
| 普通聚灵丹 | 100000 | 80% | 79.786% | 通过 |
| 稳妥＋青木炉＋地心火 | 100000 | 95% | 94.922% | 通过 |
| 赤炎炉＋火属性冲品 | 100000 | 52% | 51.849% | 通过 |
| 护炉玉回收 | 100000 | 80% | 79.977% | 通过 |
| 正多丹概率夹具 | 100000 | 80% | 80.011% | 通过 |

正多丹夹具的成功后额外成丹理论 35%，实测 34.7727%。该夹具不修改正式装备。四品质只在成功样本中统计；另检验单炉极品率。成功率偏差门槛为 ±1 个百分点，条件品质/多丹采用按样本量计算的 6 倍标准误差；概率为 0/1 的项目要求精确符合。所有明细、种子、样本数、期望和容差均在 JSON 产物中。

模拟调用与实际执行完全相同的 AlchemyRules.roll，但不逐次运行五十万次背包/完整历史事务；端到端事务由功能测试覆盖。此检验不能替代 P8 经济模拟，更不能证明 4～8 小时的真人体验。

## 遇到的问题与处理

- 初稿测试的 Variant 返回值不能用隐式类型推断，补充 Dictionary 类型后解析正常。
- 测试夹具用字典点语法新增物品 ID 时生成 StringName 键，被严格运行态验证拒绝；改用字符串索引构造夹具，保留生产校验，不把错误状态当合法输入。
- 巨大有限的品质转移请求会让“请求量－剩余量”丢失小量精度，改为累加真实转移量并加入回归。
- seed/state 超过 JSON 精确整数范围的问题用规范十进制字符串解决，恢复前检查全部流和锁定引擎；不使用 JSON 数字保存 RNG int64。
- 编辑器自动格式化 project.godot 后恢复原格式，避免混入无关设置变化。

## 设计细化、未实现与下一步

新增丹渣内容；明确熟练度每超阶 +2 个百分点/上限 +10、品质转移的下位补足与不足截量、失败返还向下取整、成功经验品阶×10/失败×3、基础研究 +1/首次品质额外 +2。都已记录在 BALANCE.md，旧配置数值不变。这些是候选初值，并非经济平衡结论。

未定义的材料纯度加成为 0；当前无变异内容，mutation_chance=0，跳过变异抽取；非空天赋/天地变数显式拒绝。正多丹已经实现，但现有正式内容仍未配置非零机会。未提前添加后期效果或声称它们已可获得。

目前只实现业务层和命令行演示，未接入炼丹房、动画、正式图鉴/任务、存档迁移/坏档恢复。needs_save 只是待保存标记；检查点测试不是完整 SaveManager。没有重复进行图形人工检查、Windows 实机或发布导出。

P3 验收达到：预览/执行同规则、确定性可复现、耗材/返还/奖励正确、独立 RNG 可恢复、概率模拟通过。下一步 **P4 炼丹房 UI**，接入现有服务形成鼠标/键盘可操作的买材料→炼丹→售丹循环，并展示结果与最近记录。

本阶段提交说明：`feat: implement deterministic alchemy engine for P3`。
