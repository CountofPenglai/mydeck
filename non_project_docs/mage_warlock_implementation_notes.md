# 法师与术士底层机制实现

更新时间：2026-07-26

本文记录法师、术士职业模板与共用底层机制的当前实现。设计依据为外部 `职业设计/法师.md` 与 `职业设计/术士.md`。两职业尚未加入冒险初始队伍、奖励池或可选职业 UI。

## 模板状态

- 法师：`sample_mage_data.tres`、`battle_mage_state.tres`。
- 术士：`sample_warlock_data.tres`、`battle_warlock_state.tres`。
- 模板属性是机制诊断占位值，不是最终平衡数值。
- 两个战斗模板均为空牌组、无装备；`AdventureSession.HERO_PATHS` 仍只包含战士、游侠、德鲁伊。
- 旧“火焰/冰霜/奥术法力”和“灵魂碎片”有限资源池已停用。

## 法师

- `CardData.element_tags` 以位标记保存火、水、土、气；有效标签会合并冒险期卡牌实例元素灌注。
- `MageCombatState` 保存个人四系无上限法术力，以及当前行动阶段的弃牌转化、主动灌注次数。
- 完成起手抽牌后，法师按完整起手的有效元素标签获得初始法术力，不发送额外抽牌或出牌 hook。
- 弃牌转化通过 `BattleController.submit_mage_discard_conversion()` 提交主要行动。标签与脚下地表在提交时锁定，卡牌逐张走通用弃牌入口，最后一次性增加汇总法术力。
- 主动灌注通过所选武器模式的实时范围校验；重复灌注仍支付法术力并施加地表。
- `MageInfusionState` 按阵营、格子和元素保存共享魔石，与 `BattleSurfaceState` 分离。逆灌注、初态形成回合锁定和四石消费已有控制器接口。
- 初态通过 `play_mage_primordial_card()` 从牌库发起正常卡牌流程：校验后以 0 AP 结算、洗混剩余牌库并原子消费四枚魔石，非 AP 费用与通常目的地区保持不变。牌库选择 UI 留给法师开放阶段。

## 术士

- `WarlockCombatState` 保存无上限术士法力、诅咒正背面和每张背面诅咒的牌上指示物。
- 所有战斗内诅咒触发、修正、限制与主动行动统一经过 `BattleUnitState.is_curse_effect_active()`；背面诅咒不再从旁路生效。
- 回合开始顺序为：既有回合开始效果、统一抽牌、腐化、畸变衰退、术士批量翻面、畸变显化、行动阶段。
- 正面翻背面获得 1 法力；背面翻正面清空牌上指示物。临时诅咒离区时同步清除这些运行时数据。
- 腐化只增加已存在且显式标记为指示物的状态；首版标记了眩晕、灼烧、异常，并单独处理咒波和背面诅咒牌上指示物。
- 术士法力和咒波支持原子混合支付。实际移除咒波后进行额外抽牌，每次事件最多 2 张；支付快照已覆盖牌库、咒波、法师/术士状态、魔石与 RNG。
- 受咒者治疗替换和独立“获得生命”入口已实现；获得生命溢出会写入冒险期最大生命修正。
- 往生通过共享 `CurseCatalog` 使用确定性战斗随机流，排除首领诅咒及深度已满的诅咒。
- `CurseDefinition.hex_keywords` 与 `WarlockHexCondition` 已提供邪术入场条件，但具体邪术牌尚未设计。

## 诊断

专项入口：`tools/diagnostics/mage_warlock_mechanics_check.tscn`。

覆盖模板未注册、元素标签、法术力无上限、弃牌转化、阵营魔石、初态锁定、诅咒翻面、腐化、混合支付、咒波抽牌、治疗替换与生命溢出。邻接回归还需执行 `curse_system_check`、`battle_flow_check`、`adventure_system_check` 和 `diagnose_battle_load`。
