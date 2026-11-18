# 技术设计基线

> 摘自根目录完整设计文档 v1.0（2026-11-18）。原章节编号保留。设计规格不代表已实现功能。
> 工程基准：本机 Godot **4.5.stable.official.876b29033**，以 `.godot-version` 为准。

# 12. Godot 4 技术架构和项目目录

## 12.1 技术原则

- **规则层与 UI 分离**：炼丹、商店、委托和轮回不依赖具体 `Control` 场景。
- **数据驱动**：所有静态内容以 JSON 文件或 Godot Resource 定义，初期统一 JSON 最简便。
- **模块化服务**：服务处理校验和事务；UI 负责呈现、输入和事件响应。
- **最小 Autoload**：只将真正的全局协调组件设为 Autoload，避免所有 Service 都成为巨型单例。
- **明确依赖**：服务函数接收必要状态或通过协调器获取，便于无头测试。
- **无网络依赖**：单机离线完整可玩。

## 12.2 建议目录

```text
AlchemyRebirth/
├── project.godot
├── AGENTS.md
├── README.md
├── docs/
│   ├── GAME_DESIGN.md
│   ├── TECHNICAL_DESIGN.md
│   ├── BALANCE.md
│   ├── DEVELOPMENT_PLAN.md
│   └── CHANGELOG.md
├── scenes/
│   ├── main/main.tscn
│   ├── screens/
│   │   ├── main_menu.tscn
│   │   ├── alchemy_screen.tscn
│   │   ├── shop_screen.tscn
│   │   ├── inventory_screen.tscn
│   │   ├── quest_screen.tscn
│   │   ├── exploration_screen.tscn
│   │   ├── progression_screen.tscn
│   │   ├── collection_screen.tscn
│   │   └── rebirth_screen.tscn
│   └── components/
│       ├── item_slot.tscn
│       ├── item_tooltip.tscn
│       ├── quality_badge.tscn
│       └── result_popup.tscn
├── scripts/
│   ├── autoload/
│   │   ├── game_controller.gd
│   │   ├── content_db.gd
│   │   ├── event_bus.gd
│   │   └── save_manager.gd
│   ├── core/
│   │   ├── rng_context.gd
│   │   ├── content_validator.gd
│   │   ├── rules.gd
│   │   └── transaction_result.gd
│   ├── services/
│   │   ├── alchemy_service.gd
│   │   ├── inventory_service.gd
│   │   ├── economy_service.gd
│   │   ├── shop_service.gd
│   │   ├── quest_service.gd
│   │   ├── exploration_service.gd
│   │   ├── progression_service.gd
│   │   └── rebirth_service.gd
│   └── ui/
├── data/
│   ├── recipes.json
│   ├── materials.json
│   ├── furnaces.json
│   ├── flames.json
│   ├── consumables.json
│   ├── quests.json
│   ├── ranks.json
│   ├── talents.json
│   ├── inheritances.json
│   ├── world_modifiers.json
│   └── exploration_events.json
├── assets/
│   ├── icons/
│   ├── items/
│   ├── backgrounds/
│   ├── fonts/
│   └── audio/
├── tools/
│   └── balance_simulator.gd
└── tests/
    ├── test_runner.gd
    ├── test_content.gd
    ├── test_alchemy.gd
    ├── test_economy.gd
    ├── test_quests.gd
    ├── test_progression.gd
    ├── test_rebirth.gd
    └── test_save_load.gd
```

## 12.3 组件职责

| 组件 | 职责 | 禁止事项 |
|---|---|---|
| `ContentDB` | 加载配置、建立 ID 索引、缓存、校验 | 不管理玩家动态库存 |
| `GameController` | 维护当前 RunState 和 MetaState，协调调用 | 不承担复杂概率公式 |
| `EventBus` | 事件广播（结果、库存变化等） | 不隐藏业务事务 |
| `SaveManager` | 存档、读档、备份、迁移 | 不直接执行炼丹 |
| `RNGContext` | 分离并保存炼丹、探索和世界 RNG | 不与 UI 特效共用抽取序列 |
| `AlchemyService` | 预览、资格校验、炼丹结算 | 不操作场景节点 |
| `EconomyService` | 灵石变动、购买出售、余额校验 | 不允许负余额 |
| `InventoryService` | 物品增减、堆叠、持有检查 | 不自行发放不明奖励 |
| `QuestService` | 委托领取、进度、交付、奖励 | 不重复结算 |
| `ExplorationService` | 事件抽取、选项结算 | 不把随机奖池藏在 UI 中 |
| `ProgressionService` | 品阶、经验、考试、天赋 | 不跳过前置条件 |
| `RebirthService` | 周目结算、传承、天地变数、初始化 | 不覆盖永久记录 |

---

# 13. 数据模型、接口和关键时序

## 13.1 运行态 `RunState`

建议用受控 Dictionary 开始实现，复杂后可引入明确的数据类。字段：

```json
{
  "run_id": "example-run-001",
  "run_number": 1,
  "world_seed": 123456,
  "rng_states": {"alchemy": 0, "exploration": 0, "world": 0},
  "rank": 0,
  "exp": 0,
  "research_points": 0,
  "spirit_stones": 200,
  "inventory": {"herb_lingcao": 5, "herb_qinghua": 3},
  "pills": {},
  "unlocked_recipes": ["recipe_juling"],
  "owned_furnaces": ["furnace_basic"],
  "owned_flames": ["flame_normal"],
  "equipped_furnace": "furnace_basic",
  "equipped_flame": "flame_normal",
  "active_quests": [],
  "quest_progress": {},
  "talent_choices": [],
  "world_modifiers": [],
  "completed_actions": [],
  "statistics": {"alchemy_attempts": 0, "alchemy_successes": 0}
}
```

示例 `rng_states=0` 仅为结构占位，**不能作为真实初始化状态**；实际新周目必须先创建 RNG、设置有效 seed，再读取初始 `state` 保存。

## 13.2 永久态 `MetaState`

```json
{
  "highest_completed_run": 0,
  "unlocked_inheritances": [],
  "discovered_pill_variants": [],
  "unlocked_endings": [],
  "achievements": [],
  "best_records": {},
  "quality_of_life_unlocks": [],
  "tutorial_completed": false
}
```

## 13.3 服务返回结构

所有业务服务建议统一返回：

```json
{
  "ok": true,
  "error_code": "",
  "message": "",
  "state_changes": {},
  "result": {}
}
```

错误码示例：`RECIPE_LOCKED`、`INSUFFICIENT_MATERIAL`、`NOT_ENOUGH_STONES`、`EQUIPMENT_NOT_OWNED`、`ACTION_DUPLICATE`、`INVALID_CONFIG`。

## 13.4 接口建议

```gdscript
# 下列为接口示意，类型可在实现时用具体自定义类替换。
func preview_alchemy(
    run_state: Dictionary,
    recipe_id: String,
    setup: Dictionary
) -> Dictionary:
    pass

func execute_alchemy(
    run_state: Dictionary,
    recipe_id: String,
    setup: Dictionary,
    rng: RandomNumberGenerator,
    action_id: String
) -> Dictionary:
    pass

func buy_item(
    run_state: Dictionary,
    item_id: String,
    quantity: int
) -> Dictionary:
    pass

func submit_quest(
    run_state: Dictionary,
    quest_id: String
) -> Dictionary:
    pass

func complete_rebirth(
    run_state: Dictionary,
    meta_state: Dictionary,
    selected_heritage_id: String
) -> Dictionary:
    pass
```

`pass` 是接口草图占位，不能视为可直接运行的完整实现。Codex 应在对应阶段创建可运行实现及测试。

## 13.5 状态变更事务

所有消费／奖励操作采取 **先校验后提交**：

1. 获取输入及当前状态快照。
2. 验证引用与资格。
3. 计算全部变化，确保不存在负库存与非法货币。
4. 对同一个逻辑操作准备完整结果。
5. 一次性提交状态变更，并记录该 `action_id`。
6. 发布变更事件，提示 UI 与存档系统。

**尤其注意 RNG：** 校验失败不抽随机数；只有确认可以执行后才改变炼丹随机流。失败回滚时必须连同 RNG 状态一起恢复，以保证可复现。

## 13.6 事件名建议

- `inventory_changed`
- `spirit_stones_changed`
- `alchemy_completed`
- `quest_completed`
- `rank_changed`
- `content_unlocked`
- `collection_updated`
- `rebirth_completed`
- `save_failed`

所有事件必须有明确的参数结构，避免发送任意 Dictionary 后难以维护。

---

# 14. 存档、确定性、异常处理与安全

## 14.1 存档划分

- **MetaSave**：图鉴、结局、传承、长期纪录。
- **RunSave**：当前周目资源、等级、装备、任务、随机流状态。
- **Settings**：音量、字体、动画速度、界面缩放等，可独立存储。

写入到 Godot `user://`。每份数据含 `schema_version`、保存时间（仅用于展示／诊断）和必要验证信息。

## 14.2 可靠存档流程

建议：序列化 → 写临时文件 → 关闭文件确认 → 读回验证 → 备份已有正式存档 → 使用文件系统重命名／替换 → 再次检查。需要考虑目标平台对替换、备份和原子重命名的具体行为，不应假设所有平台都完全原子。

如果写入失败，保留原有效档，并向用户展示错误；不要错误提示“保存成功”。读取失败时尝试备份；仍失败则提供新游戏入口和可读错误说明。

## 14.3 轮回的存档顺序

- 完成结局 → 更新 `MetaState`。
- 将旧 `RunState` 标记为已结算并保存。
- 选择下一世传承 → 创建新 `RunState`。
- 保存新的 `MetaState` 与 `RunState`。

为避免两份文件更新中断导致互相不一致，建议将二者封装在**同一版本化主存档封套**中一次提交，或者实现明确的轮回事务恢复标记。首版推荐单文件主存档，逻辑上仍分 `meta` 与 `run` 两部分。

## 14.4 随机性复现

在 `RNGContext` 中至少保存：

- `alchemy_rng.seed` 与 `alchemy_rng.state`。
- `exploration_rng.seed` 与 `exploration_rng.state`。
- `world_rng.seed` 与 `world_rng.state`。

Godot `RandomNumberGenerator` 支持 `seed`／`state`；恢复时应按当前锁定 Godot 版本的 API 正确重建。由于 RNG 算法未来可能变化，跨引擎大版本不保证位级完全一致，因此必须固定运行时版本并加回归测试。

## 14.5 作弊与安全取舍

这是离线单机，不需要为“彻底阻止玩家修改本地存档”投入大量成本。应优先关注损坏防护、崩溃恢复和游戏逻辑一致性。可选地在存档中加入校验和来检测意外损坏，但不能把校验和等同于真正的防篡改安全措施。

---

# 15. 自动化测试与数值模拟

## 15.1 必须覆盖的测试

| 分类 | 案例 |
|---|---|
| 内容校验 | 重复 ID、缺失材料、负价格、非法品阶、权重为零 |
| 交易 | 买入成功、资金不足、卖出失败、零数量、极大数量 |
| 炼丹 | 材料不足、不合格品阶、成功、失败、回收、极品、多丹 |
| 概率 | 归一化正确、上下限、模拟统计置信范围 |
| RNG | 同种子同序列、预览不消耗 RNG、读档延续序列 |
| 委托 | 品质是否达标、库存交付、奖励只领一次 |
| 晋升 | 前置条件不足、成功晋升、不可越级 |
| 轮回 | 元进度保留、当世资源重置、冲突变数过滤 |
| 存档 | 读写一致、坏档恢复、版本迁移、轮回中断恢复 |
| UI 集成 | 重复点击不会双重奖励、按钮状态刷新正确 |

## 15.2 概率统计测试

对每个代表性构筑模拟至少 100,000 炉，统计：

- 成功率的真实样本频率。
- **仅在成功样本中**统计四档品质。
- 变异与多丹的独立触发频率。
- 与理论预期的差异。

第一阶段允许成功率与理论值偏差不大于 **±1 个百分点**作为宽松回归门槛；极低概率项目要使用适合样本量的统计容差，不能一律要求 ±1%。同时有精确、非统计的逻辑单测（边界值、归一化、概率公式）。

## 15.3 经济模拟

模拟多种玩家策略：

- 保守型：优先稳丹、完成常规委托。
- 冒险型：优先冲品、寻找高价订单。
- 回收型：优先降低高阶材料损失。
- 随机型：有限合理随机决策。

输出：平均净收益、分位数、累计失败、资源耗尽次数、升级节点、通关行动数、各流派最大瓶颈。以统计作为调参依据，**不能仅凭计算声称玩家实际体验符合 4～8 小时**，仍需真人测试。

## 15.4 Godot 命令行检查（示例）

在 Godot 可执行文件能通过 `godot` 命令调用的前提下：

```bash
# 导入和解析项目（具体选项需按锁定版本确认）
godot --headless --path . --editor --quit

# 运行自定义测试入口
godot --headless --path . --script res://tests/test_runner.gd
```

如尚未创建可运行的测试入口，命令会失败；Codex 必须先实现并实际执行，不得把未执行的检查写为通过。

## 15.5 发布前人工检查

- 全新账号路径从开局到首个结局可打通。
- 至少完成一次轮回并继续到下一品阶。
- 多次存读档不会额外发物品。
- 高 DPI 与常见窗口大小下文本不截断。
- Windows/macOS 均可启动及离线运行。
- 即使玩家灵石为 0，也有恢复路线。
- 首周目和后续周目的实际游玩时长记录在测试报告中。

---
