# P7～P8 本世与永久进度存档

Godot `4.5.stable.official.876b29033`，当前存档 schema 2，兼容读取 P6 schema 1。默认 `user://run_save.json`，上一有效修订为 `.bak`，设置独立放在 settings.cfg。macOS 用户目录为 `~/Library/Application Support/AlchemyThousands/`。

P8首轮调优沿用schema2。装备和天赋ID不变，旧库存/永久档/RNG照常读取，不重算已结算炉次或补发奖励；历史快照保留其JSON精度下的原值，未来开炉使用当前内容。引擎版本相同不代表跨两套数值配置仍生成相同未来结果，复现须同时固定内容版本。

P8装备扩充仍使用schema2。新装备ID保存于本世 owned_furnaces / owned_flames；四处试炼完成状态由这些所有权推导，不增存档字段、不补发旧玩家未取得的装备。部分领取、全部领取和进行中事件均按已有结构保存。读档不能重复扣费领奖；轮回清除本世装备后试炼重新开放，永久档案继续保留。

P8目录扩充仍不变更schema2。新材料沿用inventory整数堆叠，新丹方权限在unlocked_recipes，品质发现在本世/永久发现列表。读取0.1.9存档不自动追加新配方、材料或重抽RNG；未来正常购买/取材后可保存。轮回重置本世配方和材料，已发现的新丹品质继续保留。

## 封套与内容

主文件是 JSON 对象：

```json
{"schema_version":2,"engine_version":"4.5.stable.official.876b29033","saved_at":"UTC date-time","payload":"JSON string","checksum":"SHA-256 of exact payload string"}
```

payload 恰含 `run`、`meta` 与最多二十条 `history`。run 保存经济、成长、天赋、本世发现、委托、操作记录、采药、待处理秘境、三个 RNG、结局及 P7 周目标识/携带传承/世界规则/已选奖励。meta 保存永久发现、历史结局、成就、最佳记录、已解锁传承、栏位、永久心得与便利功能，字段详见 P7_REBIRTH.md。两部分同一封套提交，避免拆成两个文件后只写成功一半。

读取先验证封套、支持的版本/引擎、校验和，再将整数语义 JSON float 规范化为 int，验证完整 ProfileState 和历史显示字段。seed/state 和 run_seed 使用规范十进制字符串，避免 int64 精度丢失。文件上限 16 MiB。校验和检测意外损坏，不作为防玩家修改的安全措施。

除既有物品、数量、天赋、结局、RNG 校验外，还验证永久记录连续性、当前周目与历史对应关系、结局快照一致性、历史装备在当时是否已解锁、栏位解锁时机、奖励唯一性、全部传承解锁前不可领取替代奖励，以及首世无变数/后续两条相容且含机会规则。schema 2 缺少 meta 时拒绝，不通过补空对象掩盖丢失。

## P6 旧档迁移

schema 1 payload 为 `{run, history}`。先验证完整 P6 状态，再在内存将其作为第一世标准世界：从原 alchemy 流 seed 与固定盐恢复原始 int64 种子，不重抽任何随机流；现有资源、成长、天赋、待选事件、最近炉次和结局不变。将本世发现归入新永久档，已有结局生成未领奖的第一世记录。

读取迁移不改写磁盘。下一次成功保存才写 schema 2，并将原有效 schema 1 保留为备份。主档和备份可分别为两种已支持版本，主档损坏时可以恢复旧版本备份。未知版本/不匹配引擎保留文件并报错，不猜测迁移。

## 写入顺序

1. 完整验证候选 run/meta/history；复制 run，将序列化副本 needs_save 置 false。
2. 写 `.tmp`、flush、关闭并读回验证。
3. 若正式文件有效，复制到 `.bak.tmp`，读回后替换 `.bak`；坏主档不覆盖有效备份。
4. 重命名 `.tmp` 替换正式文件，再读回验证。
5. 替换后校验失败，尝试通过 `.restore.tmp` 恢复有效备份；整条流程成功才报告保存成功。

写入、备份或替换失败保留先前有效档。读取先主档后 `.bak`；备份成功带 recovered/warning 并在界面提示。两者均失败不自动创建周目、不发资源、不改文件。遗留临时文件不当作已提交存档。Windows 文件替换只做故障注入，未实机验证，不宣称所有平台和断电窗口完全原子。

## 会话与事务边界

`SaveManager.new(content_db, path)` 提供 `save_run(state, history=[], meta=null)` 和 `load_run()`，沿用 TransactionResult；读取返回 state、meta、history、migrated 等信息。兼容省略 meta 的旧调用仅适用于未领取传承的第一世，后续周目或已领奖状态必须提供永久档。保存不执行奖励或 RNG 抽样。

`GameSession.new(path="")` 默认空路径供服务测试，GameShell 正式运行传入 user:// 路径。普通成功命令在提交内存后同步永久图鉴/结局并自动保存；保存失败保留内存和 needs_save，提供重试。失败命令与预览不写文件。操作 ID 从已提交记录派生。

传承领取和轮回采用更严格的复合提交：服务只准备独立 run/meta 候选，协调层先保存两者，成功才替换活动状态。写盘失败不发传承、不消耗旧世 RNG、不切换周目、不清历史；原世仍可重试。轮回预览和确认使用源周目编号，旧按钮或重复确认不能开启第三世。新世和旧世记录的 next_run 标记在同一封套生效。

新游戏/重新入宗保留永久记录；未结束的修行重开使用同一周目编号及世界/携带传承，重置临时资源并可换种子。已结束的修行拒绝通过新游戏绕过领奖及轮回。会话未加载时也会先读取有效磁盘永久档。

开炉在动画前结算，保存已扣材料/已发结果和待揭晓回执。重启恢复为已结算炉次，不再次发奖或抽样；当次进程仍能揭晓一次。普通结算与写盘之间硬崩溃可能回到上一有效提交，未声称能跨进程阻止主动回档。待选秘境按原实例恢复，待选天赋及结局保留；手动读档需确认，炼制/待处理事件中不覆盖。

退出前保存失败阻止直接关闭，可返回重试或明确放弃未存进度。

## 隔离验证

```sh
godot --headless --path . --script res://tests/test_runner.gd -- --rebirth-only
godot --headless --path . --script res://tests/test_runner.gd -- --ui-only
godot --headless --path . --script res://tools/rebirth_demo.gd -- --write-checkpoints
# 图形复核使用独立测试文件，save-path 为两个 token
godot --path . -- --save-path res://test-output/p7-demo/first-ending.json
```

覆盖 schema 1 迁移/不写原档/v1 备份、完整 int64 种子、非法元进度、临时写入/替换/替换后损坏、领取和轮回失败重试、第二世开炉及重启复现；保留 P6 全部存档回归。测试和实机均使用隔离路径，未修改默认用户进度。实际结果见 P7_REPORT.md。

## P8 新消耗品与委托

0.1.11沿用schema2；研究香库存沿用普通堆叠，实际已结算基础研究与快照保存，不在读档时重算或补发奖励。新委托使用原实例结构，重复/一次性限制读回仍成立；轮回清除本世实例与消耗品，永久图鉴/传承/结局继续保留。

## P8 可选特殊结局归档

0.1.12引入schema2可选结局归档。标准run.ending六字段不变；meta.records每世原9字段记录可选增加optional_endings数组，九转条目包含id=ending_jiuzhuan、action_count/alchemy_attempts/research_crafts/quests_completed/exp五统计及consumed极品扣丹映射。新条目不改变该世原ending、reward、next_run。旧记录省略该字段照常读取，不自动认证；新记录校验引用、品质、数量、重复和统计边界。永久unlocked_endings及jiuzhuan_saint从归档派生。

## 材料日志、异变与第三结局（0.1.13）

继续使用schema2，无新增run必需字段。meta可选增加`material_journal: {run_1: [material_id, ...], ...}`及`mutation_discoveries: [recipe_niepan|quality|mutation_qingling, ...]`。日志按世保存去重的材料接触记录（含丹渣）；历世发现为各世并集，只有本世列表计入百草要求。成功公共操作后同步，出售/消耗不移除。变异发现独立于原100项基础品质图鉴，上限4项。

读取缺少这些字段的旧档时，先验证完整原payload，再仅把当前正数材料库存和已持有的注册异变丹补入内存日志，不猜测已消耗材料或过去周目，不写原文件、不补发研究奖励。下一次成功保存才写入扩展字段。拒绝未来/非规范周目键、未知/重复材料和异变引用；轮回保留旧日志/异变发现，为新世登记初始两种材料。

丹药仍存recipe_id/quality/mutation_id/quantity，注册异变键为`recipe_niepan|quality|mutation_qingling`，与普通键分开；历史炉次允许该配方的注册mutation_id，旧回执无需增加字段。未知变异仍拒绝。

optional_endings现最多2项，允许九转与百草任意认证顺序，各ID每世唯一。百草条目id=ending_baicao，具有上述五统计及consumed一项异变涅槃丹映射，并增加`evidence: {materials: [material_id, ...], research_cost: int}`记录认证时至少25种材料及所付心得。两种档案追加互不覆盖，标准统计与本世唯一传承奖励保持原值；派生解锁加入ending_baicao/baicao_ancestor。

异变复现和百草认证使用与轮回/九转相同的先保存后切换复合提交；写入/替换失败不改变run、meta、RNG、操作号或历史，可重试。普通概率开炉沿用原自动保存边界。完整兼容、反序认证及故障检查见 P8_BAICAO_REPORT.md。

认证/神丹精研由GameSession先保存完整候选再替换run/meta；任何保存失败保留旧资源和档案，可重试。旧action或旧run_number不能重复交丹，轮回保留档案但新世需重新达到资格；认证不增加传承次数。永久discovered_pills容量改为有效丹方数×4，当前100项，旧48项以内档案不受影响。已完成特殊认证的新档不兼容旧版本应用的严格元记录校验，旧版会拒读而非默默丢弃该字段。

## 双消耗品历史（0.1.14）

沿用schema2，不增加run/meta必需字段，不持久化UI临时槽位，不自动授予消耗品。旧快照setup.consumable_id继续读取，已结算概率/成本/结果不重算。新快照可用setup.consumable_ids保存0～2项规范ID升序列表，consumed保存实际每件×1；读取/保存时校验新列表的引用、类别唯一、上限、顺序及消耗对应，拒绝混合单件字段或缺失一件消耗的伪造回执。旧单件记录不要求新增字段。

双件开炉仍复用已有状态事务/三流RNG与自动保存边界；本次不改变普通行动的保存失败策略。实际存档重启后继续双件开炉结果及RNG一致，非法新回执不能替换有效主档。轮回依原规则清空消耗品库存和本世炉次，永久材料/品质/异变与结局保留，详见 P8_DUAL_REPORT.md。
