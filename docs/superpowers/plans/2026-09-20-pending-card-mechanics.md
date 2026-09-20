# 更新文档待实现机制与卡牌实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. 本任务由用户指定多智能体执行，所有子智能体使用 Terra，主智能体统筹与验证。

**Goal:** 实施已确认的游侠潜行/特调、德鲁伊机制及十张重做牌、五张战士普通牌；保留现有眩晕层数。

**Architecture:** 职业状态与卡牌效果负责规则，`BattleController` 仅连接主流程和行动栈。法力采用独立储量，根系为独立无效果状态；卡牌分层文本与运行时同步，界面共用运行时合法性判断。

**Tech Stack:** Godot 4、GDScript、CardData `.tres`、现有诊断场景。

**Spec:** [游侠机制](../../card_lists/ranger_rework_mechanics.md)、[德鲁伊机制与十张牌](../../card_lists/druid_rework_mechanics.md)、[战士五张普通牌](../../card_lists/warrior.md)。2026-09-20 对德鲁伊范围、目标与时点的补充确认已写入规格。

## Global Constraints

- 直接在当前工作区实施；保留原有未提交文档，不自动提交或推送。
- 子智能体统一 `gpt-5.6-terra`；不并发编辑同一文件。涉及共享战斗主流程的任务依次进行。
- `card_text` 面向玩家，`resolution_rules` 储存详细裁定，保持现有关键词格式。
- 德鲁伊：人形回合开始产法，回合结束清空；变形不产法，回合结束支付 1 法力，付不起才解除变形。
- 先产法再结算法力区其他收益；回合结束其他效果完全结算后再维护形态。卡牌追击等待上一次打击及其附带效果完全结束。
- 根系不叠层、不自然衰减、不区分来源，无固有效果。血潮连击两面及根系搜索使用武器范围，正位可选敌我及自身。
- 正逆位默认弃置，只有明确效果入区；入法力区不立即产法。武器与准备动作的独立既有效果需保留并适配，不擅自重做。
- 眩晕施加层数不调整。无定稿的法师、术士新牌不在此次任务中。
- 每组功能先添加真实行为诊断并观察预期失败，再实现与复验。最终运行所有非视觉诊断，单独说明原有退出清理警告。

## Review Focus

- 失败出牌或取消选择必须回滚法力与手牌，不得因为储量模型迁移漏掉快照。
- 打击附带效果杀死或移动目标后，不得继续扣费追击；第三击吸血不能覆盖前两击。
- 变形维护用尽最后 1 点法力仍保持变形；法力降为 0 不立即解除。
- 重复潜行不能刷新机会、持续时间或任何监听；显形仍可正常调配。
- 普通牌进入奖励牌池，不修改初始牌组；卡牌数、名称及两面文本均与资源一致。

## Task 1：游侠状态与特调界面

**Files:** `scripts/ranger/ranger_combat_state.gd`、`scripts/battle/battle_unit_state.gd`、`scripts/battle/battle_controller.gd`；界面独立负责 `scripts/battle/ui/battle_bottom_hud.gd` 与 `scripts/battle/battle_scene.gd`。

**Tests:** 新建 `tools/diagnostics/ranger_stealth_blend_check.gd/.tscn`、`ranger_blend_ui_check.gd/.tscn`。

**Interface:** `BattleController.can_prepare_ranger_blend(unit: BattleUnitState) -> bool`；验证战斗/自身回合/自由时间/存活/游侠/可用机会/空载荷/至少两种元素。实际调配额外校验所选配方。

- [x] 写入显形调配、重复潜行零副作用、仇恨选择、回合刷新、资源不足/已装填/行动栈忙时无消费，以及按钮与弹窗一致性的诊断，运行确认失败。
- [x] 职业状态保存单次机会；每回合与真实潜行进入恢复，成功调配消耗。重复进入最先返回失败；仇恨按潜行动态 -1。
- [x] HUD 和弹窗调用共享资格判断，提示每回合一次及潜行刷新，不再要求潜行显示入口。
- [x] 运行新增场景与原游侠诊断，独立审查后交接共享文件。

## Task 2：德鲁伊法力、根系与回合时点

**Files:** 新增 `scripts/druid/druid_combat_state.gd` 与 `scripts/status/druid_root_status.gd`；修改 `scripts/battle/battle_unit_state.gd`、`scripts/battle/battle_controller.gd`、`scripts/cards/card_effect.gd`；必要时新增 `scripts/druid/druid_turn_rules.gd`。

**Tests:** 新增 `tools/diagnostics/druid_rework_mechanics_check.gd/.tscn`，维护旧德鲁伊机制/武器/钩子诊断。

**Interfaces:** 保持 `get_available_mana()/can_pay_mana()/pay_mana()` 调用契约，内部转为独立余额；提供 `gain_mana(amount, context)`。卡牌通用产法接口 `get_mana_production(owner, zone_card, context) -> int` 默认 1，法力区回合开始回调用于其他收益。根系使用独立状态 ID `druid_root`，不复用定身。

- [x] 先测试入区不产法、人形开始产法、变形保留与维护费边界、移出卡牌不回减余额、取消费用回滚，以及根系不叠层/无固有效果。
- [x] 将储量与产出计算职责移入职业模块，保留必要兼容入口，迁移所有临时法力调用与显示。
- [x] 回合开始先产法再触发其他法力区收益；回合结束完整行动栈收尾维护形态，保留装备形态事件。
- [x] 删除逆位身份导致的默认入区，保留明确 `mark_played_card_to_mana` 和独立装备去向修正。
- [x] 回归准备动作、特殊武器、卡牌快照和行动栈诊断。审查通过后开放卡牌任务。

## Task 3：德鲁伊十张卡牌

**Files:** 现有十个 `scripts/cards/druid_*_card_effect.gd` 及对应 `resources/cards/druid_*.tres`（只处理规格列出的十张）；必要的独立状态与选择辅助模块。共享选择入口只由本任务负责人串行修改。

**Tests:** 新建 `tools/diagnostics/druid_rework_cards_check.gd/.tscn`，维护 `druid_remaining_cards_check`、`druid_hooks_check`、`druid_mechanics_check` 等旧预期。

**Interfaces:** 使用 Task 2 的法力、产出与根系 API；入区调用明确标记；延迟选择与打击后继续步骤依附当前行动栈，不能在 `perform_strike` 返回时假定所有附带效果已完成。

- [x] 为每张牌两面编写行为断言；资源中的旧共鸣成本设为 0，暗月的自动支付在逆位效果独立处理。
- [x] 基础与变形组：根系洞察正逆抽 2/1 且各得 1 法力，逆位入区；月光基础 4，暗月基础 6 并自动支付 1 法力升至 8，两面弃置；野性觉醒得 1 法力并变形，兽形猛击打击+2 护甲入区；野性变形得 2 法力、变形、抽 1，返生解除变形、恢复 4、抽 1，两面弃置。
- [x] 法力区组：树灵正逆抽 2/1、各 4 护甲，逆位入区且每次自己回合开始抽 1；强制汲取正逆智力伤害 6/3 并根系，逆位入区后从全场根系敌人各汲取 1 生命，按实际失去总量治疗。
- [x] 投资组：灵脉爪击先抽 2 再选其他手牌 1 入区，逆位吸血打击得 1 法力并自身入区；蓄翠先将至多 2 其他手牌入区、抽实际数量、变形，逆位 4+法力区牌数护甲、抽 1、入区。
- [x] 根系攻击组：根脉结契按当前法力增益另一友军或智力伤害敌人并根系；群根怒袭每个武器范围内根系角色 +4 打击。法脉寄生根系目标并入区，产法等于全场根系角色数；血潮最多三击，第二击自动花 2 法力，第三击消耗最近根系并仅该击吸血，逆位弃置。
- [x] 覆盖选 0/无其他手牌、无根系、同距根系稳定选择、目标死亡/出射程、最后 1 法力、伤害被护甲抵挡，以及同名多张法力区牌的行为。
- [x] 同步两层正文与旧描述回退，回归 UI 选择流程和全部德鲁伊诊断，独立审查。

## Task 4：五张战士普通牌

**Files:** 新建五组卡牌及效果资源、对应 `scripts/cards/` 效果与条件；普通奖励池由现有资源发现机制接入。必要的二选一入口先复用现有 CardEffect 选择协议。

**Tests:** 新建 `tools/diagnostics/warrior_common_cards_check.gd/.tscn`，回归 `warrior_mechanics_check`、`warrior_hooks_check`、`warrior_reserve_weapon_check`。

- [x] 测试护势追击：2 AP 通常得 2 护甲；余势需至少 1 护甲，移除至多 5，每点 +2 打击伤害。
- [x] 测试守势未尽：1 AP 通常得 4 护甲；余势需至少 4 护甲，改为 1 抵挡。
- [x] 测试转锋斩：2 AP 打击后切换；成功后新武器范围敌人各受 1 固定伤害；切换失败仍保留首击。
- [x] 测试临阵换装：1 AP 切换再抽 1，不能切换时不能打出且不消费 AP。
- [x] 测试进退有势：2 AP 稳进得 1 势、打击、2 护甲；强攻付 2 势、+5 打击，不足不能选。取消选择不消费资源。
- [x] 实现与资源严格使用余势、切换武器、二选一现有规范；五张均普通，不进入初始牌组。独立审查。

## Task 5：集成、文档与最终验证

- [x] 同步德鲁伊法力余额/法力区信息显示，不用旧“已消耗/容量”语义；检查详情可查看两面详细裁定。
- [x] 更新职业牌表、索引与日志；新增 5 张战士后顶层玩家卡 71 张，战士 23 张，德鲁伊 10 张、游侠 24 张；实际从资源复核后填写。
- [x] 运行所有 `tools/diagnostics/*.tscn` 中非视觉诊断，使用本机 Godot，必要时沙箱外执行；每项有完成标记、退出码和限时保护。
- [x] 审查全部代码变更，修正重要问题并复验。保留眩晕层数再平衡待办，不宣称完成未运行的人工视觉测试。
- [x] 汇报实施范围、验证结果与剩余风险；不自动提交或推送。

## 执行记录

- 2026-09-20：用户已确认本计划；游侠核心与界面两个有明确接口、互不编辑同一文件的任务已启动，其余任务按共享文件依赖分批执行。
- 用户已确认德鲁伊范围、正位目标与时点；已明确本轮保留眩晕层数。


## 最终验证与交接（2026-09-20）

- 当前工作区实施完成，未提交、未推送，HEAD 保持 `d9b3da6`。
- 使用本机 Godot `4.7.2.stable.steam` 在沙箱外运行全部 **41 项非视觉诊断，41/41 通过**。每项退出码为 0，并核对完成标记；无脚本、解析或编译错误。
- 每项命令采用 `--headless --disable-crash-handler --path /Users/zhengce/projects/mydeck res://tools/diagnostics/<场景>.tscn --quit-after 600`，外层附加 35 秒超时保护。移动预览诊断以其性能统计行作为完成标记。
- 已排除人工视觉场景：`battle_hud_visual_check.tscn`、`chapter_two_enemy_art_visual_check.tscn`；未宣称完成人工视觉检查或 PvE 数值平衡验证。
- 退出时仍存在 ObjectDB、资源与 RID 清理警告；它们单独记录，不作为脚本错误忽略策略的通配例外。
- 补测覆盖了空手牌／选 0 张、抽牌触发后暂停与同一 AP 行动的眩晕结算、暂停时禁止其他行动、回调不重复、后续效果不丢失、血潮三击精确伤害与仅第三击吸血、死亡／移出范围先停止再决定费用、护甲全挡、根系同距稳定选择，以及真实冒险奖励候选池。
- 独立 Terra 审查发现的奖励池遗漏、纯防御段武器选择、追击目标判断、选择期间行动重入、空数组回调类型及关键词文本问题均已修复并复验。职业状态与回合规则放入专属模块，主控制器只接入流程。
- `git diff --check`、7 份文档的相对链接检查、德鲁伊 20 个牌面的正文一致性检查均通过。资源统计为顶层玩家牌 71、战士 23、游侠 24、德鲁伊 10、中立／诅咒 15；跨职业牌仅在总数中计一次。
- 保留眩晕牌现有层数；眩晕数值再平衡与长期法力区收益的 PvE 平衡仍为后续事项。
