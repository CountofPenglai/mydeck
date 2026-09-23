# 德鲁伊七张新牌与配套机制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. 本计划待用户审阅并选择执行方式；此时不得将任务标记为已实现。

**Goal:** 实施七张德鲁伊新牌、四元素增益、双生法术双向检索和法脉寄生排除自身的逐牌调整，并接入奖励、图鉴与可操作界面。

**Architecture:** `BattleController` 只负责流程入口、合法性检查和现有行动栈衔接；多区域选牌、双生法术、元素增益、战斗内诅咒压制分别使用独立模块。七张牌各自拥有 CardEffect 和资源，临时收益使用独立状态或按区域读取，依附当前结算栈处理后续步骤。保留现有回合、武器、法力、根系与存档语义，不对战斗主控做无关重构。

**Tech Stack:** Godot 4.7.2、GDScript、CardData `.tres`、现有 `.tscn` 非视觉诊断、Godot 场景 UI。

**Spec:** [德鲁伊更新文档](../../card_lists/druid_rework_mechanics.md)，重点为第二节逐牌目标调整、第七节 11～17、第八节元素、第九节双生法术。2026-09-22 用户补充确认元素牌正位共鸣 1，并要求稀有牌优先采用 2～3 字短名。

## Global Constraints

- 工作区：`/Users/zhengce/projects/my_deck/mydeck`，当前分支 `master`；保留已有三个未提交文档，不自动提交、推送或切换工作区。
- 两张稀有牌本计划建议命名为「灵契／协猎」「引灵／赋灵」，随计划审阅确认；已定名的五张史诗牌不改名。内部资源 ID 不依赖显示名称。
- 七张新牌各算一张双面资源：稀有 2、史诗 5；完成后顶层玩家牌 78 张、德鲁伊 17 张。图鉴目录还包含既有子目录条目，不能把目录数组长度直接当成顶层牌总数。
- `card_text`／`inverted_card_text` 使用玩家正文；`resolution_rules`／`inverted_resolution_rules` 记录裁定；兼容 `description` 回退。无新美术要求，复用现有卡面背景，不生成额外资产。
- 原有初始牌组不改；新牌进入相应职业奖励池与显式图鉴目录。
- 普通法力区牌人形回合开始产 1 法力，变形不常规产法；入区不立即产法；变形结束支付规则不变。
- 自身根系稀缺性只属于卡牌设计，不添加全局禁令。仅法脉寄生目标收紧，根系承载、计数与消耗不排除自身。
- 正逆位不默认入法力区；群根盟誓正位弃置、荒野化身逆位附魔入区；万物为途由明确入区效果生效。
- 所有后续效果、协助、眩晕移除依附原行动与攻击结算栈。不能以 `perform_strike` 返回作为其全部附属效果已完成的保证。
- 不修改眩晕层数，不恢复旧版支付法力移除法力区牌，不修改游侠元素配方／地表反应数值，不实施外部原稿未纳入本批的机制。
- 每个任务按真实诊断 RED → GREEN → 回归完成；解析错误或资源缺失不是有效的行为红灯。任务检查点使用差异检查与日志，不自动建立 Git 提交。

## Review Focus

1. 选牌取消、候选离区、同资源多份实体：费用不得提前扣除，区域不得复制卡牌；结算后的跳过不能回滚收益。Task 2、3、8 覆盖。
2. 施放者死亡或回合到期、重复同名增益、双持：不遗留永久增益，不把每次打击效果按伤害段倍增。Task 4、5、7、10 覆盖。
3. 派生抽牌、空牌库、洗牌、额外 AP：终结技次数与翻牌收益不能被嵌套触发放大，行动收尾不能提前。Task 8、9 覆盖。
4. 本场诅咒压制与永久封印不同，法力区回收与牌面朝向不同：不污染冒险存档或改变诅咒负荷；同一牌在各区只有一个实体。Task 3、6、8 覆盖。
5. 地表保护只防负面来源，失去自身根系即失去条件收益：不能扩大为全伤免疫、飞行、固定伤害减免或全局自施根系禁令。Task 4、7、10 覆盖。

## 本计划补齐的技术裁定（随计划审阅）

- 协猎同一施放者的同名效果刷新持续时间、不额外叠加协助次数，也不重置已经用掉的当前回合机会；不同施放者各自维护，协助打击一律不再触发协助。
- 赋灵同一角色只能保有一份本类下一击元素指定；最新施放覆盖旧的元素、来源与到期点，不叠加第二次元素增益。
- 多张万物为途的免疫与额外土元素均不叠加；荒野化身明确同名不叠加。普通产法仍逐张计算，不因效果去重而少产法。
- 自动武器打击沿用现有合法模式的固定次序选择第一个可用模式，再按距离和单位 ID 选择最近合法敌人；自动协助不弹出操作框。主动多次打击可以逐次选敌或提前停止。
- 施放者下次回合开始到期的状态必须存施放者身份和回合序号，不用受益者的 `on_turn_start` 误删；施放者死亡时清除这类限时状态，避免永不到期。
- 收费前的选择取消不改变 AP、法力、手牌或 RNG；费用提交后不提供“撤销整次行动”。此时可选的选牌、后续打击使用“跳过／结束”完成当前步骤，不回滚已经发生的抽牌或伤害。
- 新牌正文中的变形牌分类使用显式牌面元数据，不用名称／说明文字搜索；双生法术牌分类检查是否有任一牌面关键词，双生检索则精确检查相反牌面。
- 武器打击伤害加值继续遵守现有武器伤害模型，不借此次任务重写双持加值规则；只有元素增益、协助次数与下一击状态消费按整次打击计数。

## 文件与职责

| 模块 | 负责内容 |
| --- | --- |
| `scripts/cards/card_data.gd` | 双生关键词牌面、主动打出例外、正位忽略形态例外、变形牌分类 |
| `scripts/battle/battle_card_choice_state.gd` + 新 `battle_selection_service.gd` | 带区域的实时实体候选、合法提交；不包含具体牌规则 |
| `scripts/battle/ui/battle_zone_card_picker.gd` | 多区域卡牌选择与取消／跳过交互 |
| 新 `scripts/druid/druid_twin_spell_service.gd` | 双生资格、相反牌面筛选、入区检索事务与条件洗牌 |
| 新 `scripts/druid/druid_element_rules.gd` | 地表读取、指定元素、整次打击一次增益、负面地表保护 |
| 新 `scripts/druid/druid_battle_rules.gd` | 存活根系角色查询、自动合法打击、来源回合到期与前置目标事件接线 |
| 新 `scripts/curses/battle_curse_suppression.gd` | 战斗内按实体压制报／果，不修改永久 CurseInstance |
| 七个 `scripts/cards/druid_*_card_effect.gd` | 单牌效果及对应法力区／附魔区收益 |
| `scripts/battle/battle_controller.gd`、`battle_unit_state.gd`、`battle_strike_resolver.gd` | 只加明确接口接线，不把服务逻辑再复制到主控 |

### 资源清单

每个 ID 新增 `resources/cards/<id>.tres`、`resources/cards/<id>_effect.tres`、`scripts/cards/<id>_card_effect.gd`。

| ID | 显示名 | 品质 | 正／逆 AP |
| --- | --- | --- | --- |
| `druid_spirit_pact` | 灵契／协猎（命名建议） | 稀有 | 2／2 |
| `druid_element_invocation` | 引灵／赋灵（命名建议） | 稀有 | 2／2 |
| `druid_curse_prayer` | 驱咒祷词／荒魂怒啸 | 史诗 | 2／2 |
| `druid_wild_wander` | 随风入野／万物为途 | 史诗 | 1／不可主动打出 |
| `druid_wellspring_return` | 灵泉归流／怒潮奔涌 | 史诗 | 3／3 |
| `druid_spirit_whisper` | 万灵低语／盘根守望 | 史诗 | 2／仅法力区效果 |
| `druid_root_oath` | 群根盟誓／荒野化身 | 史诗 | 2／2 |

## 验证命令与诊断骨架

所有 shell 命令工作目录固定为项目实际路径。Godot 需使用本机可执行文件，沙箱阻止运行时走权限申请，不能把沙箱错误归因于规则测试失败。

```sh
"/Users/zhengce/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" --headless --path . --editor --quit
"/Users/zhengce/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" --headless --path . tools/diagnostics/druid_twin_spell_check.tscn -- --main-menu-diagnostics
sh tools/diagnostics/run_headless_checks.sh "/Users/zhengce/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
git diff --check
```

每次单场景调用使用执行工具会话取得输出并设置外部超时保护；全量运行时持续汇报进展。通过必须有场景完成标记、退出码 0 且无 SCRIPT ERROR／断言失败，不能只检查退出码。现有退出清理告警单独列出。

## Task 1：公共诊断夹具、元数据与逐牌目标边界

**Files:** 创建 `tools/diagnostics/druid_expansion_fixture.gd`、`druid_expansion_metadata_check.gd/.tscn`；修改 `scripts/cards/card_data.gd`、`scripts/battle/battle_controller.gd`、`scripts/presentation/rules_text_formatter.gd`、`scripts/cards/druid_overgrowth_graft_card_effect.gd`、`resources/cards/druid_overgrowth_graft.tres` 与现有德鲁伊诊断。

**Interfaces:** 新 CardData 字段 `twin_spell_face: int = -1`、`allow_twin_face_play: bool = false`、`upright_play_ignores_form: bool = false`、`upright_is_transformation: bool = false`、`inverted_is_transformation: bool = false`；新增 `get_twin_spell_face() -> int`，旧 `is_twin_spell=true` 且没有新字段时兼容为逆位关键词。不删除现有字段使旧资源失效。

- [ ] 编写夹具，复用 `druid_rework_cards_check.gd` 中 `_fixture` 的真实样本场景、战斗阶段与部署方式，暴露 `static func make(card_id: String, inverted: bool) -> Dictionary`，键为 `c/u/card/enemy`；各诊断自己积累错误并退出，不让断言只打印后继续误报 PASS。
- [ ] 先写现有行为测试并运行：

```gdscript
var f := Fixture.make("druid_overgrowth_graft", false)
var ap_before: int = f.u.current_ap
_expect(not f.c.play_card(f.u, f.card, [f.u]), "graft rejects caster")
_expect(f.u.current_ap == ap_before and f.u.hand.has(f.card), "invalid self target costs nothing")
```

- [ ] 观察它因当前允许自身而失败，再修改本牌 `is_unit_target_allowed` 的正位分支为 `target != user`，同步两层文本；保留计数自身、消耗自身根系的旧诊断。为另一名德鲁伊可选、敌人可选补绿色断言。
- [ ] 添加上述元数据及兼容入口，保持根系底层无修改。判断牌面时只对 `upright_play_ignores_form` 走正位，禁止由双生字段把所有牌都改成正位。

```gdscript
func get_twin_spell_face() -> int:
    if twin_spell_face >= 0:
        return twin_spell_face
    return CardEnums.DruidOrientation.INVERTED if is_twin_spell else -1
```

- [ ] 测试新字段序列化、旧资源兼容、双生面禁止主动与例外放行、变形分类不靠文案；运行 metadata、druid_rework_cards、druid_mechanics、card_detail_text 诊断并检查差异。

## Task 2：跨区域选择与串行后续步骤

**Files:** 创建 `scripts/battle/battle_selection_service.gd`、`scripts/battle/ui/battle_zone_card_picker.gd`、`tools/diagnostics/druid_selection_check.gd/.tscn`；修改 `battle_card_choice_state.gd`、`battle_resolution_runner.gd`、`battle_scene.gd`。

**Interfaces:** `BattleSelectionService.get_cards(owner: BattleUnitState, zones: PackedStringArray) -> Array[CardData]`、`validate(owner: BattleUnitState, selected: Array[CardData], zones: PackedStringArray, minimum: int, maximum: int, excluded: CardData = null) -> bool`；允许区域只有 `hand/draw/discard/mana`。现有 `request_hand_card_choice` 保持原签名与行为；新增区域参数入口复用候选验证和 UI，不重写旧手牌协议。

- [ ] 编写并运行失败断言，覆盖同一资源的两份不同实体可同时选择、同一实体重复选择失败、卡牌离区后旧选择失败、非法区域失败、最少 0／最多 5：

```gdscript
var first := CardData.new()
var second := first.duplicate(true) as CardData
f.u.mana_zone.assign([first, second])
_expect(service.validate(f.u, [first, second], PackedStringArray(["mana"]), 0, 5), "distinct copies are legal")
_expect(not service.validate(f.u, [first, first], PackedStringArray(["mana"]), 0, 5), "duplicate entity is illegal")
```

- [ ] 实现验证核心：

```gdscript
var live := get_cards(owner, zones)
var seen := {}
for card in selected:
    if card == null or card == excluded or not live.has(card) or seen.has(card):
        return false
    seen[card] = true
return selected.size() >= minimum and selected.size() <= maximum
```

- [ ] 将区域选择请求存于 runner 当前行动中；空可选集使用空结果继续，不能留下永不结束的窗口。窗口本身只发选择信号，提交后由服务再次验证实时区域。
- [ ] 收费前多步骤选项保存在 `strike_context`，全部验证通过后才调用 `play_card`；后置选择只允许跳过可选效果，不回滚已经结算的抽牌。原行动等待选择期间不得开放普通出牌或回合结束按钮。
- [ ] 运行 `druid_selection_check`、`card_choice_flow_check`、`druid_rework_cards_check`；验证眩晕在恢复选择且全部后续完成后才按原 AP 消耗移除。

## Task 3：双生法术双向免费入区与检索

**Files:** 创建 `scripts/druid/druid_twin_spell_service.gd`、`tools/diagnostics/druid_twin_spell_check.gd/.tscn`；修改 `battle_scene.gd`、`ui/battle_bottom_hud.gd`、`battle_controller.gd`、`card_data.gd` 和规则详情展示。

**Interfaces:** `DruidTwinSpellService.setup(controller: BattleController) -> void`、`can_begin(owner: BattleUnitState, card: CardData) -> bool`、`get_candidates(owner: BattleUnitState, card: CardData) -> Array[CardData]`、`execute(owner: BattleUnitState, card: CardData, selected: CardData = null, searched_deck: bool = false) -> bool`。调用方先展示只读候选，确认后一次提交；入区触发完全结算后复核检索实体，不复制卡牌。

- [ ] 编写双向行为诊断，源码中不存在服务时先给明确失败提示；解析成功后观察没有入区／检索的行为红灯。构造正位 A、逆位 B、无标记 C、同面 D，两个区域候选和无候选分别测。

```gdscript
var ap_before: int = f.u.current_ap
var mana_before: int = f.u.get_available_mana()
_expect(service.execute(f.u, a, b, false), "twin action succeeds")
_expect(f.u.mana_zone.has(a) and not f.u.hand.has(a), "source moves once")
_expect(f.u.hand.has(b) and not f.u.discard_pile.has(b), "retrieved entity moves once")
_expect(f.u.current_ap == ap_before and f.u.get_available_mana() == mana_before, "no AP fee or immediate mana")
```

- [ ] 按关键词所在面筛选，与持有者形态无关：

```gdscript
var face := card.get_twin_spell_face()
var opposite := CardEnums.DruidOrientation.INVERTED if face == CardEnums.DruidOrientation.UPRIGHT else CardEnums.DruidOrientation.UPRIGHT
for candidate in selection_service.get_cards(owner, PackedStringArray(["draw", "discard"])):
    if candidate.get_twin_spell_face() == opposite:
        result.append(candidate)
```

- [ ] 仅在存活角色自己的自由时间允许执行；不占用普通准备动作次数、不触发主动牌效果，不作为支付 AP 的新主要行动。所有入区／检索派生效果进入 runner，完成前暂时锁住自由操作。
- [ ] UI 区分“打出正位”和“双生入区”；检索可选 0 张；实际查看过牌库页令 `searched_deck=true` 并洗牌，选中牌库实体时服务端也必须强制按搜寻过牌库处理，不能因调用方漏传标志跳过洗牌。仅浏览弃牌堆不洗牌，弃牌堆不回洗。取消提交前不改 RNG 或区域。
- [ ] 验证忙时拒绝、源牌已离手、候选被其他触发移走、只搜弃牌不洗牌、无候选成功入区、两方向自由选择非固定配对；运行新场景和准备动作／装备回归。

## Task 4：四元素增益与地表负面来源识别

**Files:** 创建 `scripts/druid/druid_element_rules.gd`、`tools/diagnostics/druid_element_rules_check.gd/.tscn`；修改 `battle_strike_resolver.gd`、`battle_controller.gd` 的地表入口、`battle_unit_state.gd` 的地表修正调用、`scripts/items/effects/druid_weapon_effect.gd` 的元素元数据桥接。复用 `ranger_burn_status.gd`、`ranger_move_surcharge_status.gd`，不复制第二套同名状态。

**Interfaces:** `DruidElementRules.setup(controller: BattleController) -> void`、`resolve_after_strike(attacker: BattleUnitState, target: BattleUnitState, context: Dictionary) -> void`、`is_surface_protected(unit: BattleUnitState) -> bool`。在本次打击上下文快照 `druid_element` 与 `druid_extra_earth`，保留来源；指定元素优先于武器／地表读取，额外土元素独立一次。

- [ ] 新诊断分别验证火 2×2 次回合、水下一主动移动 +1 AP、土 3 护甲、风远离攻击者 1 格；双持整次只有一次元素效果。用下面的土元素断言作为首个行为红灯：

```gdscript
var before: int = f.u.get_armor_stacks()
rules.resolve_after_strike(f.u, f.enemy, {"druid_element": BattleSurfaceState.Element.EARTH})
_expect(f.u.get_armor_stacks() == before + 3, "earth grants three armor")
```

- [ ] 以单个武器打击 scope 为单位接入，不能在 `apply_damage` 每段后调用。武器范围／敌人死亡后不可附加非法击退，土元素仍给执行者护甲。

```gdscript
match int(context.get("druid_element", BattleSurfaceState.Element.NONE)):
    BattleSurfaceState.Element.EARTH:
        attacker.gain_armor(3, context)
if bool(context.get("druid_extra_earth", false)):
    attacker.gain_armor(3, context)
```

- [ ] 其他分支调用已有共享灼烧、冻结和强制位移路径；不自动铺地表。风无合法落点不移动，不弹窗。
- [ ] 对地表伤害、地表生成状态、移动惩罚、冰停步、沙尘射程限制及毒沼减值使用来源一致的免疫判断；保留地表有益加值和读取／采集。直接卡牌造成的灼烧、固定伤害不能被误当成地表来源。
- [ ] 运行元素新诊断、`battlefield_features_check`、`ranger_terrain_cards_check`、`ranger_traps_check` 与 `druid_weapons_check`；检查元素附属效果仍位于当前攻击 scope 内。

## Task 5：两张稀有牌与来源回合状态

**Files:** 创建资源清单中的 `druid_spirit_pact`、`druid_element_invocation` 三件套；创建 `scripts/druid/druid_battle_rules.gd`、`scripts/status/druid_assist_status.gd`、`druid_element_charge_status.gd`、`tools/diagnostics/druid_rare_cards_check.gd/.tscn`；为现有选择 UI 增加共鸣多选与基础元素选择组合，不向主控添加专牌分支。

**Interfaces:** `DruidBattleRules.setup(controller: BattleController) -> void`、`get_rooted_units(origin: BattleUnitState, radius: int = -1) -> Array[BattleUnitState]`、`get_automatic_strike(owner: BattleUnitState, target: BattleUnitState = null) -> Dictionary`；返回打击信息 `{target, equipment_slot}`，无合法模式返回空字典。限时状态存 `source_unit_id`、`expires_on_source_turn`，协助另存最近使用的全局角色回合序号。

- [ ] 写每牌两面红灯：灵契未共鸣单选／共鸣 2 多选、抽 2／最近敌人吸血打击／6 护甲；引灵共鸣 1 两项先铺后打；赋灵全场根系友军受益、自身无需根系。

```gdscript
var f := Fixture.make("druid_spirit_pact", false)
_expect(f.c.play_card(f.u, f.card, [f.u], {"choice_indices": [2]}), "pact armor option")
_expect(f.u.get_armor_stacks() == 6, "pact armor equals six")
```

- [ ] `choice_indices` 和 `selected_element` 在收费前选定；共鸣选择校验为非空、去重、按正文序号执行。支付失败不得消费 AP；自动吸血由实际打击者恢复实际生命伤害。
- [ ] 协猎：首击全部结束后赋状态；友军首击及其附属效果结束后再检查射程／存活并排队协助。通过上下文 `druid_assist=true` 阻止协助互相触发。

```gdscript
if bool(context.get("druid_assist", false)):
    return
controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_resolve_assist"), [owner, target], "协猎")
```

- [ ] 赋灵快照受益者，下一击覆盖通常元素读取；最新同类效果覆盖旧效果，移动或失根不撤销，按施放者回合到期；新获得根系不补发。
- [ ] 增加协助目标被附属效果杀死／移动、自动模式无合法项、施放者死亡、不同角色回合刷新、重复打出不重置当回合机会、双持一次消费的断言；验证世界状态变化后共鸣第二项不能攻击死目标。
- [ ] 运行新场景与原共鸣／选择／武器诊断；同步正文和裁定，首次采用短名需以用户批准本计划为准。

## Task 6：驱咒祷词／荒魂怒啸与战斗内压制

**Files:** 创建 `druid_curse_prayer` 三件套、`scripts/curses/battle_curse_suppression.gd`、`tools/diagnostics/druid_curse_prayer_check.gd/.tscn`；修改 `battle_unit_state.gd` 的诅咒生效查询和战斗重置、诅咒选择 UI。

**Interfaces:** `BattleCurseSuppression.suppress(curse: CurseInstance) -> bool`、`is_suppressed(curse: CurseInstance) -> bool`、`clear() -> void`；每个 BattleUnitState 一个战斗内集合。`is_curse_effect_active` 在现有封印／术士逻辑之外检查该集合，不能写 `curse.sealed` 或永久角色属性。

- [ ] 首先写实际战斗诊断：目标抽 2、施放者得 2 法力；可选报或果失效，负荷、深度、成熟度不变，重开战斗恢复；不能选择业或已压制实例。

```gdscript
var depth_before: int = curse.depth
var load_before: int = curse.get_load_cost()
_expect(suppression.suppress(curse), "report/fruit can be suppressed")
_expect(curse.depth == depth_before and curse.get_load_cost() == load_before and not curse.sealed, "no permanent mutation")
```

- [ ] 逆位只从相应区诅咒候选中用战斗 RNG 随机选 1 张；手牌与牌库独立，实际成功数量转换为 `4 * exiled_count` 打击加值。牌库无候选不展示付费选项，法力不足拒绝增强但允许基础使用。
- [ ] 额外 2 法力支付选择在出牌前明确；先完成放逐触发，再进行打击；不向玩家展示敌人其他手牌或牌库牌序，不删除永久诅咒实例。
- [ ] 覆盖仅手牌／仅牌库／两个都无、费用取消、盾甲吸收、两个合法候选确定性随机、本场结束后压制恢复；运行新诊断、`mage_warlock_mechanics_check`、诅咒相关既有诊断与存档往返检查。

## Task 7：随风入野／万物为途

**Files:** 创建 `druid_wild_wander` 三件套、`tools/diagnostics/druid_wild_wander_check.gd/.tscn`；修改必要的区域入场通知和地表保护查询，调用 Task 4 服务。

**Interfaces:** 正位 `upright_play_ignores_form=true`；逆位 `twin_spell_face=INVERTED`、不可主动。明确入区方法复用 `mark_played_card_to_mana`；需在传送前实际提交入区与区域通知，不能只打标记后等行动结束才入区。

- [ ] 先写变形时 1 AP 正位成功、起点无元素也可、距离 7 成功／8 拒绝、被占据落点拒绝的行为断言；元素落点伤害必须在入区保护后结算。

```gdscript
var f := Fixture.make("druid_wild_wander", true)
_expect(f.card.upright_play_ignores_form, "wander is the explicit form exception")
_expect(f.card.get_twin_spell_face() == CardEnums.DruidOrientation.INVERTED, "twin tag stays on inverse")
```

- [ ] 入区 → 通知附属效果完成 → 合法传送 → 落点地表的顺序排队；不能把支付 1 AP 的主动入区自动转成免费双生检索。
- [ ] 法力区按资源效果身份读取保护与额外土元素；多份去重，不用额外普通状态留在角色上导致离区后漏清理。
- [ ] 验证离区即停保护、人形／兽形均生效、没有即时产法、普通产法仍逐张、额外土和指定火同时生效、直接敌方技能仍能施加相同负面状态；运行新场景、movement／surface／druid 武器回归。

## Task 8：灵泉归流／怒潮奔涌

**Files:** 创建 `druid_wellspring_return` 三件套、`tools/diagnostics/druid_wellspring_return_check.gd/.tscn`；必要时为 `battle_unit_state.gd` 增加返回直接抽牌实体列表的辅助入口，原 `draw_cards` 调用契约保持兼容；复用 Task 2 区域选择。

**Interfaces:** 本牌效果内部保存 `direct_draw_count` 与 `strikes_remaining`，后者只从前者赋值一次；主动选敌的续接使用 runner 当前行动，不调用新的 `play_card` 扣费。

- [ ] 红灯覆盖法力区回收 0／5、6 张非法、回收立即停止万物为途等区内收益、之后获得 3 法力；逆位 8 法力、3 其他手牌时直抽 5、至多打 5 次。

```gdscript
var needed := maxi(0, owner.get_available_mana() - owner.hand.size())
var direct_cards: Array[CardData] = draw_directly_for_this_effect(owner, needed, context)
strikes_remaining = direct_cards.size()
```

- [ ] `draw_directly_for_this_effect(owner: BattleUnitState, amount: int, context: Dictionary) -> Array[CardData]` 属于本牌辅助，逐张通过通用抽牌入口获取该调用直接抽到的实体，不能以最终手牌差计算。派生抽牌可正常结算，但不能追加直接计数。
- [ ] 固定初始 `needed`，使用直接抽牌结果；等全部抽牌附属效果结束再开始攻击。每次打击及其附属效果完成后，若还有次数且存在合法敌人，再开放继续选敌或停止。
- [ ] 无额外法力费、无额外 AP 费、无打击硬上限。已有 runner 死循环保护作为运行安全边界，不转写成新的牌面次数限制。
- [ ] 加入抽牌触发再抽牌、抽牌触发弃牌／加法力、空牌库、所有目标死亡、首次打击击杀后转目标、提前停止和眩晕恰好在整次 3 AP 行动后移除的诊断；运行新场景和 AP 栈相关全部诊断。

## Task 9：万灵低语／盘根守望

**Files:** 创建 `druid_spirit_whisper` 三件套、`tools/diagnostics/druid_spirit_whisper_check.gd/.tscn`；修改 `druid_battle_rules.gd`、`battle_controller.gd` 卡牌目标确认点和 `battle_unit_state.gd` 区内事件分发。

**Interfaces:** CardEffect 新钩子 `on_zone_owner_targeted(owner: BattleUnitState, zone_card: CardData, context: Dictionary) -> void` 默认空实现；仅在敌人卡牌最终确认目标、费用成功后调用，必须在该牌效果前让响应队列完成。`context` 带施放者、源牌、目标、行动 ID，不能从范围预览或每段伤害触发。

- [ ] 正位红灯：2 AP 主动双生例外，弃置其他全部手牌，按固定数量展示，分类收益 +4／治 4／AP +1，多类别分别计入；所有展示牌最后入手，不触发抽牌监听。

```gdscript
for revealed_card in revealed_cards:
    if revealed_card.card_type == CardEnums.CardType.ATTACK:
        attack_bonus += 4
    if revealed_card.upright_is_transformation or revealed_card.inverted_is_transformation:
        heal_events += 1
    if revealed_card.get_twin_spell_face() >= 0:
        ap_gain += 1
```

- [ ] 实施顺序为弃牌及附属效果 → 展示固定数量 → 加攻击状态 → 每次治疗重新找最低当前生命受伤友方 → 加 AP → 展示牌入手。牌库为空按既有牌库重洗边界处理，不能在展示暂存区复制同一实体。
- [ ] 下一击加值到自己回合结束过期；不能在主手后清除导致副手语义与旧模型冲突。新增 AP 不在当前队列中途开放操作。
- [ ] 逆位先锁定本张实体为正在响应，先对半径 3 敌人施根系，再统计半径 3 根系角色×3 加甲，再移入弃牌；多段攻击只触发一次。多张不同实体可各自执行一次，但同一实体不可重入。
- [ ] 验证目标预览不触发、费用失败不触发、真实敌人卡牌生效前有护甲、友方指定不触发、环外根系不计数、自身计数、叠加标签、同生命按单位 ID、无受伤友军、牌面“变形”字样但无元数据不计入；运行新场景及敌人意图／卡牌目标／眩晕回归。

## Task 10：群根盟誓／荒野化身

**Files:** 创建 `druid_root_oath` 三件套、`scripts/status/druid_root_oath_status.gd`、`tools/diagnostics/druid_root_oath_check.gd/.tscn`；复用 `druid_battle_rules.gd` 根系集合与来源回合到期，不改根系状态类。

**Interfaces:** 正位状态存固定受益者、+2 伤害、来源和到期点；逆位由附魔区 CardEffect 的现有伤害／减伤查询读取，辅助 `get_incarnation_bonus(owner: BattleUnitState, context: Dictionary) -> int` 只服务武器打击，同名效果只汇总一次。

- [ ] 红灯覆盖自身根系 → 变形 → 自身及全场其他根系友军 4 护甲、+2 打击；初始没根系友军不受益，后来新增根系不补发，失根不撤销已发正位强化。
- [ ] 逆位数学核心与诊断：

```gdscript
func get_incarnation_bonus(owner: BattleUnitState, context: Dictionary) -> int:
    if not bool(context.get("strike", false)):
        return 0
    var result := 4
    if owner.has_status("druid_root"):
        result += 2 * rules.get_rooted_units(owner).size()
    return result
```

- [ ] 验证无自身根系 +4／0 减伤；自身有根系且 N=1/3/5 时 +6/+10/+14，减伤始终 3。固定伤害不减免，非武器伤害不获得该增伤；增加、死亡、移除根系后即时变化。
- [ ] 正位同名状态刷新不叠伤害、护甲仍获得；逆位多份附魔不重复计入；本牌离开附魔区后立即无效。
- [ ] 验证血潮连击消费自身根系后，后续计算失去条件增益；法脉寄生仍不能自选但另一德鲁伊可选；源角色死亡时清理团队限时状态。运行新场景与所有德鲁伊诊断。

## Task 11：资源注册、文档、集成审查与全量验证

**Files:** 修改 `resources/card_catalog.tres`、必要时 `scripts/adventure/adventure_reward_catalog.gd`、`scripts/presentation/rules_text_formatter.gd`；更新 `docs/card_lists/druid.md`、`README.md`、`CHANGELOG.md`、`druid_rework_mechanics.md`；创建 `tools/diagnostics/druid_expansion_catalog_check.gd/.tscn`、`druid_expansion_ui_check.gd/.tscn`。

**Interfaces:** 沿用现有奖励资源发现与图鉴显式目录，不新建第二份卡牌注册系统。新资源使用稳定路径，确保保存的卡牌路径重新载入有效。

- [ ] 先以资源集合写失败验收：

```gdscript
var expected := ["druid_spirit_pact", "druid_element_invocation", "druid_curse_prayer", "druid_wild_wander", "druid_wellspring_return", "druid_spirit_whisper", "druid_root_oath"]
for card_id in expected:
    var card := load("res://resources/cards/%s.tres" % card_id) as CardData
    _expect(card != null and card.is_druid_dual_card, "registered druid card: " + card_id)
    _expect(not card.card_text.is_empty() and not card.inverted_resolution_rules.is_empty(), "both-face copy is present")
```

- [ ] 注册资源与奖励，校验新牌稀有度 2 稀有／5 史诗、所有 AP、关键词面与形态例外；总量按顶层 CardData 统计 78、德鲁伊 17，初始卡组保持原列表。
- [ ] UI 行为验证：共鸣多选、元素＋格子／单位双目标、跨区域双生检索、法力区回收、连续打击选敌与提前结束、详细裁定显示；1280×720 和 1920×1080 进行人工或截图检查，记录实际完成项，不能把 headless 当视觉验收。
- [ ] 运行导入解析检查、新增全部场景，再运行 `run_headless_checks.sh` 全套旧场景；检查每项完成标记、退出码、错误日志与超时。回归失败先定位，不直接改期望值掩盖错误。
- [ ] 按共享底层、卡牌行为、UI/元数据三条线审查；涉及执行方式需要独立审查者时遵循相应技能与用户模型选择，禁止在计划阶段擅自启动实现子智能体。
- [ ] 对照规格逐项检查，不遗漏双生动作、元素装备接线、根系计数自身、诅咒战斗边界；修正后重跑相关场景，再跑全量。
- [ ] 只有诊断和实际实现完成后，才把更新文档状态改为已实施、同步当前牌表与数量；保留尚未进行的平衡实测说明。最后 `git diff --check`，汇报变化、测试、风险，不自动提交推送。

## 依赖与执行选择

- Task 1 → 2 → 3 串行建立元数据、选择与双生流程；Task 4 接入现有打击链；Task 5～10 按上述次序实现，共享文件同一时间只有一个实现者。
- 可选多智能体：逐任务实现和独立审查，不并发编辑 battle 主流程；模型按用户确认配置。可选本会话执行：主智能体逐任务实现，最后集中审查。
- 执行状态（2026-09-22 当前阶段审查，历史记录）：用户已选择对当前更新进行审查与提交准备；灵契／协猎、引灵／赋灵、驱咒祷词／荒魂怒啸三张已实现并经本阶段定向验证，另四张史诗（随风入野／万物为途、灵泉归流／怒潮奔涌、万灵低语／盘根守望、群根盟誓／荒野化身）尚未开始。上方 Task 7–11 的原始计划复选框保留未勾选，不表示完整计划已完成。

## 执行更新（2026-09-22，保留原计划历史）

七张双面德鲁伊牌现均已接入，其中本轮完成后续四张史诗的资源、效果、显式图鉴/奖励登记和专项 UI/资源诊断；顶层玩家牌为 78、德鲁伊为 17，初始卡组未改。Task 7–11 已完成逐任务审查与集成收尾：编辑器导入退出0，最终完整套件76通过、0失败，两个分辨率的实际渲染验收通过；退出资源警告与视觉打磨事项如实保留。详见[本轮审查记录](../reports/2026-09-22-druid-expansion-review.md)。本轮未提交或推送；上方旧阶段段落与原计划保留历史语义。
