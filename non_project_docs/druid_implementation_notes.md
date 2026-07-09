# 德鲁伊职业实现记录

更新时间：2026-07-09

## 实现范围

- 为战斗单位新增德鲁伊运行时牌区：法力区、附魔区、诅咒区。
- 为德鲁伊新增变身状态与准备动作：
  - 未变身时，每回合可准备一次：将最左侧手牌逆置置入法力区，并进入变身。
  - 已变身时，每回合可准备一次：支付 1 点法力并解除变身。
- 德鲁伊正逆位卡牌通过 `CardData` 的 Druid 字段驱动：
  - `is_druid_dual_card`
  - `inverted_name`
  - `inverted_description`
  - `inverted_ap_cost`
  - `inverted_target_type`
  - `resonance_cost`
  - `is_twin_spell`
- 逆位打出的德鲁伊双面牌在结算后进入法力区，不进入弃牌堆。
- 共鸣采用当前低交互实现：若卡牌配置 `resonance_cost > 0` 且 `auto_pay_resonance = true`，并且德鲁伊有足够法力，则自动支付并在上下文写入 `druid_resonance_paid`。
- 德鲁伊变身时，战斗单位层面的力量与智力互换。伤害加值读取已改为优先读取 `BattleUnitState` 的实时属性，因此变身会影响力量/智力类型伤害。
- 战斗 UI 的职业资源栏会显示德鲁伊法力、附魔、诅咒与当前形态，并提供准备动作按钮。
- 手牌 UI 和 tooltip 已改为使用正逆位感知的名称、AP、描述与目标类型。

## 已加入资源

- 角色：
  - `resources/characters/sample_druid_data.tres`
  - `resources/characters/battle_druid_state.tres`
- 装备：
  - `resources/items/training_staff.tres`
- 卡牌：
  - `druid_verdant_strike`：正位武器打击并按手牌获得护甲；逆位武器打击并按法力获得护甲。
  - `druid_moonlit_mend`：选择单位，友方治疗，敌方智力魔法伤害；可自动共鸣提高数值。
  - `druid_wild_shape`：正位变身、抽牌并进入法力区；逆位自疗并获得临时法力。
  - `druid_rooted_insight`：正位抽牌并可共鸣获得临时法力；逆位抽牌并获得临时法力。
- 示例战斗：
  - `resources/battle/sample_battle_scenario.tres` 已加入德鲁伊米拉作为第三名玩家角色。
- 诊断：
  - `tools/diagnostics/druid_mechanics_check.tscn` 验证德鲁伊准备动作会消耗 1 张手牌、增加 1 张法力区牌，并进入变身。

## 发现的问题与解决方案

- 问题：德鲁伊准备动作入栈后不会生效。
  - 原因：`can_use_druid_prepare_transform()` 同时用于发起动作与动作解析；动作解析期间 `is_resolving_actions()` 为 true，导致解析阶段自我拦截。
  - 解决：将“正在结算时不能发起新准备动作”的限制移动到 `use_druid_prepare_transform()` / `use_druid_prepare_untransform()`，解析阶段只校验形态、资源和当前单位。
- 问题：正逆位字段存在但战斗流程没有实际使用。
  - 原因：AP、目标类型、tooltip、结算上下文仍直接读取 `card.ap_cost`、`card.target_type`、`card.card_name`。
  - 解决：在 `BattleController.play_card()`、`get_card_ap_cost()`、目标验证和 `BattleScene` UI 中传递 `druid_orientation`，统一使用 `CardData` 的 context-aware getter。
- 问题：共鸣支付失败或特殊条件失败时可能留下牌区副作用。
  - 原因：原支付快照只回滚 AP、生命、手牌、弃牌堆和放逐区。
  - 解决：支付快照加入法力区、附魔区、诅咒区、变身状态、准备动作标记和临时法力。
- 问题：变身后的力量/智力互换不会影响伤害加值。
  - 原因：`CharacterState` 的属性伤害加值直接读取角色基础状态，而不是战斗单位实时状态。
  - 解决：`CharacterState._get_attribute_damage_bonus()` 在上下文包含 `unit` 时，优先使用 `unit.get_strength()`、`unit.get_agility()`、`unit.get_intelligence()`。

## 暂缓实现项

- 文档中需要选择具体手牌逆置的准备动作，目前低交互实现为“最左侧手牌”。后续需要 UI 选择手牌。
- 附魔区、诅咒区已建立运行时牌区和 UI 计数，但尚未实现完整触发事件体系。
- 双生法术目前只做了规则拦截：逆位不可打出。尚未实现一次选择两面或复制结算。
- 抽牌后、治疗后、造成伤害后、弃牌后、牌进入特殊区后等通用事件钩子尚未建立，因此依赖这些触发的复杂德鲁伊牌暂缓。

## 验证

- Godot 无头脚本检查：
  - `Godot_v4.6.3-stable_win64_console.exe --headless --path D:\py_work\my-deck --disable-crash-handler --check-only --quit`
- 战斗加载诊断：
  - `res://tools/diagnostics/diagnose_battle_load.tscn`
- 德鲁伊机制诊断：
  - `res://tools/diagnostics/druid_mechanics_check.tscn`

以上三项均通过。Godot 退出时仍会输出 DummyTexture/RID 释放提示，这是当前无头诊断环境中的既有退出噪音，本次没有发现由德鲁伊资源导致的加载失败。

