# 游侠牌表

> 数据来源：`resources/cards/*.tres` 中的 `CardData` 资源。默认值按 `scripts/cards/card_data.gd` 解释。

- 当前收录：21 张
- “武器射程”表示实际射程还会受角色、装备、状态和地表效果影响。
- 完整规则文本保持与资源中的 `description` 一致。
- [重做机制记录](ranger_rework_mechanics.md)：已确认意图 AP、意图干扰和新版眩晕规则，尚未实现。

## 基础

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 猎影穿行 | 技能 | 1 | 指定范围；范围 3 | 连击 | 你选择范围 3 内、与至少 1 名敌人相邻的空格，特殊移动至该格并进入潜行。<br><br>连击：其他手牌不少于 6 张。你以 0 AP 结算上述效果。 | [ranger_shadow_passage.tres](../../resources/cards/ranger_shadow_passage.tres) |
| 透支灵感 | 技能 | 1 | 自身 | 连击 | 你抽 2 张牌。<br><br>连击：无条件。你以 0 AP 抽 2 张牌，并增加 2 点弃牌债务；本回合结束时，你按手牌顺序弃置至多等同于累计债务的牌，然后清空债务。 | [ranger_overdrawn_inspiration.tres](../../resources/cards/ranger_overdrawn_inspiration.tres) |
| 险步突袭 | 攻击 | 2 | 单体；武器射程 | 连击 | 你选择近战或远程组件进行 1 次武器打击。<br><br>连击：支付 1 AP 或弃置 1 张牌。你以 0 AP 进行该武器打击。 | [ranger_perilous_assault.tres](../../resources/cards/ranger_perilous_assault.tres) |

## 稀有

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 交错猎步 | 攻击 | 2 | 单体；武器射程 | — | 你选择近战或远程组件、1 名敌人和合法落点。使用远程组件时，打击后特殊移动至目标相邻空格，并使你本回合下一次由游侠武器牌结算的近战打击伤害 x1.5；使用近战组件时，打击后特殊移动至距目标 2 至 3 格的空格并进入潜行。 | [ranger_cross_hunt_step.tres](../../resources/cards/ranger_cross_hunt_step.tres) |
| 回锋不止 | 攻击 | 1 | 单体；武器射程 | 连击 | 你使用当前近战组件进行 1 次武器打击。本牌在弃牌堆时，你可以弃置 1 张手牌，将本牌移回手牌。<br><br>连击：近战模式本回合伤害加值 -2（可叠加）。你以 0 AP 进行该近战武器打击。 | [ranger_relentless_backslash.tres](../../resources/cards/ranger_relentless_backslash.tres) |
| 守候猎物 | 附魔 | 1 | 自身 | — | 附魔：你进入潜行并选择近战或远程组件。你的下回合开始前，首名移动结束后位于所选武器范围内的敌人自动受到 1 次对应武器打击。触发后、期限届满时或你提前离开潜行时，将本牌移入弃牌堆。 | [ranger_waiting_prey.tres](../../resources/cards/ranger_waiting_prey.tres) |
| 异域取样 | 攻击 | 1 | 单体；武器射程 | — | 武器打击。匕首首次造成正数生命伤害后，按通用规则采集目标格，再额外采集游侠当前格；弩首次造成正数生命伤害后采集目标格一次。 | [ranger_exotic_sampling.tres](../../resources/cards/ranger_exotic_sampling.tres) |
| 弩索牵引 | 攻击 | 2 | 单体；范围 3 | — | 使用弩打击。目标存活时沿朝向游侠的六边直线强制移动至多 2 格；沿途触发地表，冰面立即终止。移动结束后采集目标最终所在格一次。 | [ranger_crossbow_tether.tres](../../resources/cards/ranger_crossbow_tether.tres) |
| 无缝追击 | 攻击 | 1 | 单体；武器射程 | 连击 | 你选择近战或远程组件进行 1 次武器打击。<br><br>连击：选择并弃置 2 张其他手牌。你以 0 AP 进行该武器打击，并使本回合下一张手牌可以忽略自身连击条件，以 0 AP 作为连击牌打出。 | [ranger_seamless_pursuit.tres](../../resources/cards/ranger_seamless_pursuit.tres) |
| 猎场封锁 | 附魔 | 2 | 自身 | — | 附魔：你进入潜行并选择近战或远程组件。你的下回合开始前，首名在所选武器范围内完成出牌的敌人触发伏击：近战模式对你相邻的所有敌人各进行 1 次近战武器打击；远程模式对触发者及其相邻、且在远程组件范围内的所有敌人各进行 1 次远程武器打击。触发后、期限届满时或你提前离开潜行时，将本牌移入弃牌堆。 | [ranger_hunting_ground_lockdown.tres](../../resources/cards/ranger_hunting_ground_lockdown.tres) |
| 百味齐备 | 技能 | 1 | 自身 | — | 抽 2 张；元素库存至少有 2 种时额外抽 1 张，四种齐全时再额外抽 1 张。 | [ranger_full_flavor.tres](../../resources/cards/ranger_full_flavor.tres) |
| 窃取预案 | 攻击 | 2 | 单体；武器射程 | — | 武器打击并检视目标手牌。匕首复制 1 张可复制牌加入手牌，本回合费用 -1 且打出后或回合结束时放逐；弩弃置目标 1 张手牌，然后抽 1 张。 | [ranger_steal_plan.tres](../../resources/cards/ranger_steal_plan.tres) |
| 绝处续弦 | 攻击 | 1 | 单体；武器射程 | 连击 | 你进行 1 次武器打击，然后抽 3 张牌；若抽牌后你有其他手牌，结算完成后选择并弃置 1 张。<br><br>连击：本牌是唯一手牌。你以 0 AP 结算上述效果。 | [ranger_desperate_string.tres](../../resources/cards/ranger_desperate_string.tres) |
| 藏锋再起 | 攻击 | 2 | 单体；武器射程 | 余势、连击、共享：战士/游侠 | 你进行 1 次武器打击。<br><br>连击：弃置 1 张手牌。你以 0 AP 进行 1 次武器打击。<br><br>余势：从弃牌堆放逐 1 张牌。你以 0 AP 进行 1 次获得 +2 伤害加值的武器打击。 | [hidden_blade_again.tres](../../resources/cards/hidden_blade_again.tres) |

## 史诗

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 三相解剖 | 攻击 | 2 | 单体；武器射程 | 连击 | 你对同一目标依次进行至多 3 次近战武器打击；每次打击将武器基础伤害改为 1，目标死亡后停止后续打击。每次造成正数生命伤害时，分别按通用规则采集目标格。<br><br>连击：本回合实际加入库存的元素至少 2 枚。你以 0 AP 结算上述效果。 | [ranger_tri_phase_dissection.tres](../../resources/cards/ranger_tri_phase_dissection.tres) |
| 双相猎影 | 附魔 | 2 | 自身 | — | 进入潜行，分别获得一次进攻续接和一次防御续接：主动攻击破隐或敌方行动被潜行抵消后，可各重新进入潜行一次。两次耗尽或下回合结束时弃置。 | [ranger_dual_phase_hunt.tres](../../resources/cards/ranger_dual_phase_hunt.tres) |
| 异域爆瓶 | 攻击 | 2 | 指定范围；范围 4 | — | 你选择 1 种高级元素配方，并消耗其两种反应元素各 1 枚和任意基础元素催化剂 1 枚。对中心格的敌人与战场对象造成基础伤害 8 加你的敏捷伤害加值，对每个相邻格的敌人与战场对象造成基础伤害 4 加你的敏捷伤害加值；潜行倍率同时作用于所有这些伤害。然后将中心格和所有合法相邻格变为所选高级地表。 | [ranger_exotic_bottle.tres](../../resources/cards/ranger_exotic_bottle.tres) |
| 无处不猎 | 攻击 | 1 | 单体；武器射程 | — | 武器打击。每场3次：本牌在弃牌堆且手牌变空，或在牌库且本回合打出第3张牌时，自动移回手牌。 | [ranger_no_place_to_hunt.tres](../../resources/cards/ranger_no_place_to_hunt.tres) |
| 猎手三幕 | 附魔 | 2 | 单体；武器射程 | — | 附魔：你预选 1 名敌人与 1 种武器模式，并将本牌移入你的附魔区。你此后打出的第 1 张其他牌令目标随机弃置 1 张手牌；第 2 张使你在目标仍存活且位于所选武器范围内时自动打击目标；第 3 张使你进入潜行，然后将本牌移入弃牌堆。本牌最晚在本回合结束时移入弃牌堆。 | [ranger_hunter_three_acts.tres](../../resources/cards/ranger_hunter_three_acts.tres) |
| 终猎宣告 | 攻击 | 3 | 单体；武器射程 | — | 仅潜行可用。匕首破隐伤害x3，未击杀则锁定匕首至下回合；弩破隐伤害x2，并复制本次消耗的弩特调载荷。 | [ranger_final_hunt_declaration.tres](../../resources/cards/ranger_final_hunt_declaration.tres) |

## 传说

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 猎杀时刻 | 攻击 | 0 | 单体；武器射程 +2 | — | 你选择近战或远程组件进行 1 次武器打击。若目标在打击前的生命不高于生命上限的 50%，本次打击伤害 x2。近战组件击杀目标后，你进入潜行。使用远程组件时，本牌攻击范围 +2，并忽略远程攻击的地表伤害减免。 | [ranger_hunt_moment.tres](../../resources/cards/ranger_hunt_moment.tres) |
