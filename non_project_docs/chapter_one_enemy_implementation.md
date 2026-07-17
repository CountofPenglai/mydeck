# 第一章敌人与怪物卡池实现

更新时间：2026-07-17

本文记录 `敌人.md` 第一章定稿在项目中的当前实现、工程边界和测试入口。设计目标仍以外部文档为准；代码事实以本页列出的入口与诊断为准。

## 已实现内容

- 16 张怪物公共牌均有 `CardData` 资源，统一由 `MonsterCardEffect` 提供结算。
- 基础牌与畸变牌使用分类配方槽生成；每个敌人按遭遇种子和出生顺序获得独立牌组。
- 第一章 10 种敌人由 `ChapterOneEnemyCatalog` 数据驱动创建，不为每个类型复制行为类。
- 敌人使用真实 `EquipmentData` 武器；冠军和渊鳞具有备用武器。
- 弱、混合、强、精英和 Boss 遭遇均已接入 `AdventureSession`。同池会避开立即重复；大地图构造的敌人不会再被示例场景原型覆盖。
- 行动序改为每轮开始按当前敏捷重建并锁定，轮内属性变化留到下一轮。
- `TacticalEnemyBehavior` 使用最多 4 步、束宽 6 的计划搜索；意图只引用锁定时已存在的牌，失效步骤跳过。
- 战场棋子头顶显示首个意图和累计攻防；单击敌人打开右侧情报栏，可查看完整步骤、特性、配方摘要、牌区数量和已见牌。
- 简版美术包含基础怪物牌面、畸变牌面、临时咒害牌面和 10 格敌人徽章图集。

## 怪物特性

当前由 `ChapterOneEnemyRules` 统一分发：

- 饥饿鱼人首次致命伤害后逆位，第二次死亡眩晕范围内最近冒险者。
- 鱼叉鱼人在水中获得敏捷，主动跨越水域边界每回合获得一次 AP。
- 鱼人祭司与大湖主祭提供水域治疗和伤害光环，并在行动开始引潮。
- 不洁者打出诅咒牌后累积污化，提高伤害和最大生命并治疗。
- 鱼人冠军在大剑状态积势，公开计划切换长枪、突进并强化下一张攻击牌。
- 克拉肯按当前生命分档放大本回合 AP，作为多子回合的简版承载。
- 大湖主祭在护卫最终死亡时承受反噬并清空战斗资源。
- 渊鳞以 20 点共有护甲的单体简化模型开场；护甲归零后切换武器、把战场覆盖为水并启用深渊牌费与回合衰竭。

## 关键入口

| 领域 | 文件 |
| --- | --- |
| 敌人与遭遇目录 | `scripts/enemies/chapter_one_enemy_catalog.gd` |
| 特性分发 | `scripts/enemies/chapter_one_enemy_rules.gd` |
| 分类卡组 | `scripts/enemies/enemy_deck_rule.gd`、`enemy_deck_slot.gd`、`enemy_card_pool_entry.gd` |
| 公开意图 | `scripts/enemies/enemy_intent_planner.gd`、`tactical_enemy_behavior.gd` |
| 怪物牌结算 | `scripts/cards/monster_card_effect.gd` |
| 显化持续状态 | `scripts/status/monster_manifest_status.gd` |
| 战斗情报 UI | `scenes/ui/enemy_inspect_panel.tscn`、`scripts/enemies/enemy_inspect_panel.gd` |
| 卡牌资源 | `resources/cards/monster_cards/` |

## 当前简化与后续边界

- 克拉肯目前用分档 AP 表达 3/2/1 条行动轨道，尚未为每条轨道独立执行完整抽牌、状态计时和 AP 换抽。
- 渊鳞共有护甲目前由 Boss 自身护甲承载；若未来遭遇加入共享护甲单位，需要独立资源池。
- 流寇破口/压制标记、完整职业档案能力列表、敌人业牌深度和随机结果提前公开仍可继续细化。
- 意图步骤当前是结构化 Dictionary。若 UI 需要路径、逐段目标和失效原因，应升级为强类型 `EnemyIntentStep`，不要继续添加不稳定键。
- 显化已支持同名替换、持续状态和批量解放；牌区事务仍是现有分区 API，未来可收敛为统一原子迁移接口。

## 验证

- `chapter_one_enemy_check.tscn`：16 张牌、10 种敌人、五档遭遇和饥饿鱼人逆位。
- `diagnose_battle_load.tscn`：全资源扫描、战斗 UI 实例化、部署和开战。
- `battle_flow_check.tscn`：行动队列、回合边界与每轮行动序改造的邻接回归。

命令和沙箱处理方法见 [环境记录](environment_memory.md)。
