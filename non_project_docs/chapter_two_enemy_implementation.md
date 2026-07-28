# 第二章敌人与怪物池实现记录

更新时间：2026-07-26

## 已实现范围

- `EnemyCatalogRouter` 将内部楼层 `0/1` 明确映射为第一/第二章，并把 `enemy_chapter` 固化进战斗事务。
- 遭遇袋键包含章节编号；旧事务若已经保存敌人 ID，则默认按第一章恢复。
- 第二章具有独立弱、混合、强、伏击、精英和 Boss 池。
- 六种军事单位、圣垒军团长、造物裂片、魔血构造体、腐心帷幕、灰垒圣骑和凯旋圣像均使用真实属性、武器、牌组与公开意图。
- 军事单位会优先邻接部署；`军阵`只查询相邻存活军事友军，不叠加、不传导。
- 永久畸变字段写在 `EnemyData.permanent_distortion_fields`，战斗初始化时投影到 `DistortionBattleState`。
- 八张军事公共牌及六张怪物化职业牌由 `ChapterTwoEnemyCardEffect` 统一实现，全部排除在玩家奖励池外。
- `EnemyRuleDispatcher` 统一分发第一、二章规则，控制器和单位状态不再直接依赖第一章规则类。
- 凯旋圣像属于可攻击、不可行动的支援单位；圣徽按生命阈值熄灭，圣骑致命时延迟合体为军神圣骸。
- 腐心帷幕实现福音转阶段、强制位移、咒波增伤和诅咒区伤害。
- 击败腐心帷幕后，战斗奖励 UI 可选择一名冒险者接受深度 1「福音」之业，或主动放弃。
- 福音的业、报、果、负荷上限、咒波获取、消耗里程碑和回合末代价均进入统一诅咒框架。

## 运行时所有权

- 敌人阶段、圣徽、军令、过载、倒转、往生和召唤状态保存在 `EnemyState.runtime_state`。
- 共享 `EnemyData`、`CardData` 与 `EquipmentData` 不保存战斗状态。
- 血肉衍生物与构造体共享抽牌堆和弃牌堆；洗牌使用原数组原地更新，避免共享引用失效。
- 血肉衍生物的最大生命固定为 1，不再被力量生命公式二次抬高。
- 第二章固定加入敌人牌组的职业牌和诅咒牌会先复制并强制设置 `reward_eligible = false`。
- 「公开戒备」会从手牌直接迁入附魔区，确保同一张牌不会同时存在于附魔区与弃牌堆。

## 当前基础版本边界

- 军事公共牌的逐张正式效果在外部设计文档中仍标为暂缓；项目采用可完整结算的基础版，后续定稿时只需替换数据与效果种类。
- 造物裂片的职业池选择由确定性敌方 AI 自动完成，并在战斗日志公开，不增加玩家确认窗口。
- 腐心帷幕的一阶段范围扩展已覆盖第二章通用直接伤害效果；未来新增带移动、召唤或复杂自效果的专属牌时，应显式声明是否允许范围扩展。
- 福音 Boss 行动当前作为公开特殊意图执行；反制窗口需要未来统一的“公开首领行动反制”接口。

## 关键文件

- `scripts/enemies/enemy_catalog_router.gd`
- `scripts/enemies/chapter_two_enemy_catalog.gd`
- `scripts/enemies/chapter_two_enemy_rules.gd`
- `scripts/enemies/enemy_rule_dispatcher.gd`
- `scripts/cards/chapter_two_enemy_card_effect.gd`
- `resources/curses/gospel.tres`
- `tools/diagnostics/chapter_two_enemy_check.tscn`

## 验证

- 严格 Godot 编辑器加载：通过。
- `chapter_two_enemy_check.tscn`：通过。
- `chapter_one_enemy_check.tscn`：通过。
- `adventure_system_check.tscn`：通过。
- `battle_flow_check.tscn`：通过。
- `curse_system_check.tscn`：通过。
- `diagnose_battle_load.tscn`：通过。

专项诊断覆盖：12 个正式第二章敌人模板、各档遭遇袋、楼层章节路由、军阵、永久畸变、战术回合、公开戒备区域迁移、血肉衍生物固定生命与共享牌堆、圣像阈值、圣骑合体、腐心帷幕转阶段，以及福音奖励的存档往返与报状态结算。
