# 游侠卡牌重做与新增牌实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已确认的九张游侠牌及其依赖机制接入可玩的战斗与冒险流程。

**Architecture:** 保留 BattleController 的行动主流程，独立模块负责陷阱、仇恨候选、地表批次与选择状态；卡牌效果、条件、资源各自承担现有职责。全部延迟效果依附现有结算栈；文本不驱动结算。

**Tech Stack:** Godot 4.7 / typed GDScript / Resource (.tres) / tools/diagnostics 场景。

**Spec:** docs/card_lists/ranger_rework_mechanics.md

## Global Constraints

- 在当前工作区实现；保留原有未提交文档和 .gitignore 改动。此轮不提交或推送。
- 子智能体使用 gpt-5.6-terra，监督由当前会话模型承担；工作者不得启动子智能体。
- 实施已确认设计，不自行重平衡眩晕牌。异域取样保留资源路径与引用，显示名采用文档暂名异域诱饵。
- 2026-09-06 用户修正：尽程一矢、踏境追刃、潜踪整备均为普通品质（高于基础），加入普通奖励池，初始牌组保持原配置。
- 连击统一为“连击：条件。卡牌效果正文”；不满足/不支付条件仍能正常付费，免费连击完成后才增加计数器。
- card_text / resolution_rules 不参与行为计算；保留旧 description 的兼容读取，避免破坏现有资源和双面牌。
- 改动用 apply_patch。独立任务只修改所分配文件；共享接口变更先通知监督。
- 使用实际 BattleController/Resource 的行为诊断，先观察新增行为诊断失败再实现；完整回归由监督统一运行。
- Godot: `/Users/zhengce/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot`。已获准在沙箱外运行。新类首次运行前需 headless editor 导入。

### Task 1: 卡牌文本分层与详情展开

**Files:** scripts/cards/card_data.gd; scripts/presentation/rules_text_formatter.gd; scripts/battle/ui/battle_detail_panel.gd; 必要的详情场景; tools/diagnostics/rules_text_formatter_check.gd，另建最小详情交互诊断。

**Interfaces:** 新增导出 card_text、resolution_rules；现有 get_description_for_context() 优先返回相应 card_text，旧 description 回退。详情接口读取规则文本，不修改卡面格式器的普通输出。

- [x] 阅读现有 CardData 双面/上下文读取、RulesTextFormatter、详情面板锁定/预览状态及现有测试。
- [x] 增加真实输出诊断：设置旧 description 与新 card_text 时，卡面只显示新文本；空新字段仍显示旧资源文本；裁定仅在详情展开后显示；切换卡牌和锁定状态不会残留前一张裁定；双面卡原行为不变。
- [x] 运行诊断观察预期缺失失败。随后新增两个 export 字段，详情中加入明确“详细裁定”展开/收起控件，无规则时隐藏。遵循现有 UI 布局。
- [x] 执行 rules_text_formatter_check 与新增 UI 诊断，并检查 git diff --check；报告变更及 RED/GREEN 证据。

### Task 2: 地表即时结算、陷阱与仇恨基础

**Files:** scripts/battle/battle_object_state.gd; battle_object_definition.gd; battle_unit_state.gd; battle_controller.gd 的薄集成入口; battle_strike_resolver.gd; 独立 battle_trap_controller.gd / battle_threat_targeting.gd（按现有结构决定具体名字）；现有敌人 AI 模块、地图对象显示；tools/diagnostics/ranger_traps_check.gd/.tscn。

**Interfaces:** 在报告中列出陷阱放置/合法性、上限读取、对象受攻击通知、地表扩散入口的准确签名供 Task 3/4 使用。兼容现有战场对象，不使普通桶/墙柱变为全局仇恨目标。

- [x] 阅读规范中的“元素地表变更”“仇恨等级”“通用陷阱规则”“元素陷阱牌”。以现有对象和地表结算入口扩展，不复制伤害主流程。
- [x] 新增行为诊断，覆盖实际变更立即结算、同地表不重结算、反应仅最终地表；攻击零伤害和致死攻击均在完整攻击后引爆；环境伤害不引爆；爆炸只扩散当前地表且不形成攻击连锁。
- [x] 新增角色通用可修正仇恨/陷阱上限（普通玩家仇恨 1，游侠基础上限 1）；对象拥有者保持引用，独立仇恨 1，动态统计全部活陷阱。超限最新陷阱在当前栈立即引爆，旧陷阱和上限下降不追溯处理。所有者死亡不清除陷阱。
- [x] 集成敌人选择合法攻击/追踪目标：合法候选内先保留最高仇恨，再用原评分；陷阱与玩家同级，不盲目让不可攻击对象屏蔽合法敌人。
- [x] 运行陷阱/地表及 enemy_intent_ai_check、battlefield_features_check 相关诊断；报告新增 API、时点保证与结果。

### Task 3: 意图牌、牵引、元素陷阱牌与品质调整

**Files:** scripts/cards/ranger_waiting_prey_card_effect.gd; ranger_hunting_ground_lockdown_card_effect.gd; ranger_crossbow_tether_card_effect.gd; ranger_exotic_sampling_card_effect.gd; 对应 .tres；ranger_full_flavor.tres；scripts/battle/battle_scene.gd / CardData / CardEffect 所需通用选择入口；新增聚焦选择模块；tools/diagnostics/ranger_rework_cards_check.gd/.tscn。

**Interfaces:** 复用现有意图干扰 API 与 Task 2 陷阱入口；公开可序列化的 context 选择键，供 UI 和诊断一致传递。禁止把意图选择塞进文本解析。

- [x] 从规范逐项实现守候猎物（普通技能 1 AP，任一可削减公开意图）、猎场封锁（稀有攻击 2 AP，武器配件+该射程敌人的攻击意图，先偷 1 AP 再打击）。需有真实 UI 选择和取消路径，选中后结算前重新校验。
- [x] 弩索牵引保持 2 AP，普通品质，远程实际射程，打击后仅存活目标向自己强移至多 1 格，再采集最终格。
- [x] 异域诱饵保持原资源路径，稀有技能 2 AP、范围 3、元素空格放置；超限提示“超限：放置后爆炸”且可放置。使用 Task 2 通用机制。
- [x] 百味齐备只下调为普通，保持 1 AP 和 2/3/4 抽牌。
- [x] 写入这些牌 card_text 和 resolution_rules，保留使用中的资源引用。对非法/锁定/零预算/非攻击意图与取消选择无消耗、回合实际预算、牵引障碍/击杀、陷阱超限进行行为诊断，执行后报告。

### Task 4: 异域爆瓶临时采集与载荷选择

**Files:** scripts/cards/ranger_exotic_bottle_card_effect.gd; 对应 .tres；scripts/ranger/ranger_combat_state.gd；独立采集批次 helper；battle_scene 选择流程与薄 controller 入口；tools/diagnostics/ranger_bottle_check.gd/.tscn。

**Interfaces:** 复用现有采集规则/事件，临时批次独立于库存容量。与 Task 3 通用选择入口保持一致。

- [x] 卡牌仍为史诗攻击 2 AP。至少一枚周围当前可采集元素才可用；无库存前置条件。目标使用远程配件对该格实际射程，包含修正和现有合法格规则，不进行武器打击。
- [x] 按规范采集当前和邻格；采集来源限制、高级拆分、数量修正和事件保持原语义。临时批次不受库存上限阻挡，选择本次采集 1 至 2 种不同元素，每种消耗 1 枚；选择后的剩余按库存容量收入。
- [x] 对中心敌人/对象造成 8+敏捷伤害加值，邻格 4+敏捷伤害加值，潜行倍率对全部伤害一致。伤害全部完成，再按所选顺序施加中心载荷，最后只扩散最终地表。
- [x] 诊断覆盖库存已满、空库存、有库存但无可采集来源、不可重复采集、高级拆分、顺序反应、零/重复/旧库存载荷无效、范围修正、潜行伤害和攻击后陷阱爆炸时序；验证并报告。

### Task 5: 三张普通牌与连击文本统一

**Files:** scripts/cards/conditions/ 新连击条件；scripts/cards/ 三张新效果；resources/cards/ 三套卡/effect/stack/条件；scripts/status/ 延迟 AP 状态；现有游侠连击卡资源；实际卡池/奖励/测试入口注册处；tools/diagnostics/ranger_common_cards_check.gd/.tscn。

**Interfaces:** 必须复用既有 normal/combo 入口和统一连击完成回调。登记新卡牌进入实际可发现牌池；不擅改已确认的初始牌组数量。

- [x] 尽程一矢：普通攻击 2 AP、远程配件；连击条件目标距离等于对其实际射程；额外伤害 min(距离-1,3)。精确卡面见 Spec 原文。
- [x] 踏境追刃：普通攻击 2 AP、近战配件；自身基础或高级地表可连击；完整打击后额外采集自身当前格，无正数生命伤害要求、击杀仍采集。
- [x] 潜踪整备：普通技能 1 AP；选择弃 0 至 2 张其他手牌，按实际弃数立即抽等量；进入潜行，自己下回合开始得 1 AP，多次叠加且不要求潜行保留。
- [x] 统一已有游侠连击卡文本为“连击：条件。卡牌效果正文”，去除重复正文与“以0 AP”表达，行为不变。
- [x] 行为诊断覆盖付费/免费两路径、距离修正、连击计数结束时点、零伤害与击杀采集、0/1/2 张弃牌、取消选择、下回合 AP 叠加且潜行破除不丢失。确认新资源进入实际卡池，运行并报告。

### Task 6: 集成回归与文档同步

**Files:** tools/diagnostics 受新语义影响的旧断言；docs/card_lists/ranger.md、ranger_rework_mechanics.md、README.md、CHANGELOG.md；必要集成修复。

- [x] 对所有实现做整体审查，逐项对照 Spec；处理跨任务接口与结算时序遗漏，补充真实回归。
- [x] 使用 headless editor 导入，并执行全部非视觉诊断（逐场景检查退出码及脚本错误）；相关 UI 场景做布局/交互核验。
- [x] 将九张卡的资源当前值同步到牌表，移除本批已实现项的“待实现”标记；保留尚未定数值的眩晕牌再平衡作为后续工作。
- [x] 新增脚本 UID、引用、git diff --check、完整 Git 状态核验；给出结果与可审查文件，不提交推送。
