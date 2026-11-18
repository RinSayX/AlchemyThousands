# P6 单周目存档与恢复

Godot `4.5.stable.official.876b29033`，存档 schema 1。默认 `user://run_save.json`，上一有效修订为 `.bak`，设置仍独立放在 settings.cfg。macOS 用户目录为 `~/Library/Application Support/AlchemyThousands/`。

## 封套与内容

主文件是 JSON 对象：

```json
{"schema_version":1,"engine_version":"4.5.stable.official.876b29033","saved_at":"UTC date-time","payload":"JSON string","checksum":"SHA-256 of exact payload string"}
```

payload 中包含完整 `run` 与最多二十条 `history`。run 保存经济、逐级成长、天赋、图鉴、委托实例、防重复操作记录、采药机会、待处理秘境、三个 RNG 的十进制 seed/state 字符串及结局快照。校验和检测意外损坏，不作为防玩家修改的安全措施。

解码先验证封套、支持的版本/引擎、校验和，再将有效整数语义的 JSON float 规范化为 int，执行 ProgressionState 的完整验证和历史显示字段验证。种子/随机状态始终是字符串，避免 int64 精度丢失。非法 JSON、未知版本、引擎不匹配、未知物品/天赋、重复天赋、非法数值和不一致结局都拒绝，文件限制 16 MiB。

P5 尚无正式磁盘存档，因此本版没有旧版存档迁移；未知版本保留原文件并报告不支持，不尝试猜测修复。P7 的永久 meta/轮回数据不混入本世 run，本阶段不实现跨世保存。

## 写入顺序

1. 验证候选状态和历史，复制 run 并把序列化副本 needs_save 置 false。
2. 写 `.tmp`、flush、关闭并读回验证。
3. 若正式文件当前有效，复制到 `.bak.tmp`，读回后替换 `.bak`。正式文件已坏时不覆盖有效备份。
4. 重命名 `.tmp` 替换正式文件，再读回验证。
5. 若替换后校验失败，尝试通过 `.restore.tmp` 恢复有效备份；只在整条流程成功时向协调层报告保存成功。

写入、备份或替换失败保留先前有效档；游戏事务已经提交的进度仍在内存并保留 needs_save，界面显示失败与重试入口。退出前保存失败会阻止直接关闭，允许返回重试或由玩家明确选择放弃未存进度。Windows 文件替换行为仅有命令层故障测试，未经过 Windows 实机验证；不宣称所有平台和断电窗口完全原子。

读取先尝试主档，失败尝试 `.bak`；备份成功会附 recovered/warning 并在界面提示。两者均失败不自动创建周目、不发起始资源、不修改文件，提供中文错误及新游戏确认入口。遗留临时文件不会被自动当作已提交进度读取。

## 会话与事务边界

`SaveManager.new(content_db, path)`，提供 `save_run(state, history=[])` 和 `load_run()`，结果沿用 TransactionResult。只接受有效完整状态；不执行游戏奖励、晋升或 RNG 抽样。

`GameSession.new(path="")`：默认空路径供服务测试，不写用户磁盘；GameShell 正式运行传入默认 user:// 路径。每次成功的状态命令自动保存；失败命令和所有预览不写文件。操作 ID 从已提交记录派生，失败命令不会留下读档后丢失的计数器空洞。

开炉在动画前已结算，自动存档保存已扣材料/已发结果的状态，并把待揭晓回执加入序列化历史。重启恢复为该炉已经结算的状态，不重播发奖、不重掷；当次进程仍可正常揭晓一次。结算/写盘之间硬崩溃的极短窗口可能回到上一有效提交，未声称能跨进程永久阻止主动回档。

待选秘境按原 instance_id 恢复，继续时自动打开该事件卡，不再计入境行动；待选天赋和结局也完整恢复。手动读档先确认覆盖当前内存状态，炼制/待处理事件中不接受读档覆盖。

## 隔离验证

```sh
godot --headless --path . --script res://tests/test_runner.gd -- --progression-only
godot --headless --path . --script res://tests/test_runner.gd -- --ui-only
# 图形复核使用独立测试文件，参数为两个 token
godot --path . -- --save-path res://test-output/p6-demo/final-ready.json
```

测试实际注入临时写入中断、备份/正式替换失败、替换后损坏，验证原档/备份和脏内存仍可恢复；包含坏档/未来版本/引擎/校验和/非法状态拒绝、动画中重启、秘境/天赋/结局持久化及下一次真实结果一致性。全部场景测试使用空路径或隔离文件，不操作默认游戏进度。实际结果见 P6_REPORT.md。
