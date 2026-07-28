# 地表与地图要素实现记录

更新时间：2026-07-27

本文记录《地表与地图要素》设计在 Godot 项目中的当前实现。正式数值与规则仍以外部设计文档为目标；本文件用于说明代码所有权、运行时入口和回归方法。

## 已实现范围

- 战场格拆分为永久地形、临时地面效果、临时空气效果、永久元素源、四系临时残留和战场对象。
- 基础火、水、土、气只参与反应、采集和条件读取，不再直接提供伤害、治疗、减免或射程修正。
- 蒸汽、熔岩、烈焰、毒沼、冰面和沙暴按固定顺序结算；地面与空气通道分别覆盖，同名刷新。
- 高级效果和临时残留持续两个后续战斗轮；永久源不被反应消耗。
- 浅水、岩浆裂隙和深渊已接入移动、环境伤害与首张非诅咒牌 AP 加费。
- 炸药桶、储水罐、风蚀图腾、不稳墙柱和建筑残骸拥有独立生命、占格、视线与销毁效果。
- 普通攻击可选择可破坏对象；单体卡牌可用 `CardData.can_target_battle_objects` 显式开放对象目标。
- 回旋斩、伤铸壁垒和异域爆瓶等现有范围伤害已同步影响范围内对象。
- 地图按地形、地面效果、空气效果、元素角标、对象和单位分层绘制；悬停格子可查看完整摘要。
- 第一章与第二章使用独立权重生成 5 至 8 个特殊地形格和 3 至 5 个对象。
- 第一章强敌/精英深渊使用 50%/75% 概率，并通过 `PartyRunState.adventure_flags` 保存连续未生成次数；两次未生成后下一次保底。
- Boss 或特殊遭遇可通过 `BattleMapData.terrain_cells` 和 `object_placements` 使用手工配置。

## 数据所有权

| 数据 | 所有者 | 说明 |
| --- | --- | --- |
| 地图尺寸、部署区、手工地形与对象摆位 | `BattleMapData` | 共享只读配置，战斗开始后深复制 |
| 地形、效果、元素源、残留、采集记录 | `BattleSurfaceState` | 单场战斗运行时 |
| 对象生命、销毁状态、倒塌方向 | `BattleObjectState` | 单场战斗运行时，不进入单位列表 |
| 章节、档位、生成种子、深渊结果 | `BattleScenario` | 待处理战斗事务固化后传入 |
| 深渊连续未生成次数 | `PartyRunState.adventure_flags` | 冒险期持久状态 |

`BattleObjectDefinition` 是对象静态配置。对象运行时生命和触发标记不得写回定义资源。

## 关键入口

- `battle_surface_state.gd`
  - `apply_base_element()`：一次施加匹配全部反应。
  - `get_readable_elements()`：职业和 AI 读取当前格的元素集合。
  - `get_collectible_entries()` / `commit_collection()`：游侠按来源限次采集。
  - `get_cell_snapshot()`：UI 和诊断使用的只读快照。
- `battlefield_feature_generator.gd`
  - 使用独立种子生成章节战场要素，不消费 `BattleController.rng`。
- `battle_controller.gd`
  - 负责环境伤害、对象伤害、销毁状态、销毁副作用队列、元素即时反应和深渊 AP 加费。
  - `battle_objects` 与 `units` 完全分离，避免污染行动序、AI 和胜负判断。
- `battle_targeting.gd`
  - 单位落点同时检查活跃对象；远程攻击使用对象视线阻挡。
- `battle_map_view.gd`
  - 只负责绘制、预览和悬停文本，不拥有规则。

## 结算约定

1. 元素施加先读取施加前的永久源和残留快照。
2. 所有匹配反应按蒸汽、熔岩、烈焰、毒沼、冰面、沙暴排序。
3. 匹配残留被消耗，永久源保留；反应产物不在本次施加中继续反应。
4. 即时反应随后结算，地面/空气最终保留同通道顺序靠后的效果。
5. 对象生命归零时同步标记销毁并移除其永久元素源；爆炸、倒塌等副作用进入当前效果队列，后续销毁继续追加到队列，禁止递归出牌。即使效果预算耗尽，关键销毁状态也不会回滚或遗留。
6. 环境伤害经过伤害减免与护甲，但没有攻击者伤害后、吸血或打击 hook。

## 扩展方法

- 新增永久地形时，同时定义移动/伤害规则和永久元素源，不要把规则写入基础元素。
- 新增高级效果时，先指定地面或空气通道，再补持续时间、进入/回合触发和 UI 颜色。
- 新增对象时，在 `BattleObjectDefinition.Kind` 注册静态数据，在控制器的销毁分派中实现效果。
- 单体卡牌若能攻击对象，应开启 `can_target_battle_objects`，并让对应 `CardEffect` 接受 `BattleObjectState`。
- 范围伤害效果应通过 `get_battle_objects_in_range()` 或目标格的 `get_battle_object_at_cell()` 同步对象伤害。
- 手工 Boss 战在地图资源中配置；普通、精英战使用章节生成器。

## 回归

专项入口：

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --disable-crash-handler --log-file "tmp\battlefield_features_check.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/battlefield_features_check.tscn"
```

`battlefield_features_check` 覆盖六层共存、基础元素无数值加成、多反应顺序、通道覆盖、持续期、来源采集、生成确定性、部署区保护、深渊保底、对象占格、不可摧毁语义、效果预算下的关键销毁状态、爆炸连锁和视线阻挡。

相邻回归至少运行：

- `battle_flow_check.tscn`
- `diagnose_battle_load.tscn`
- `hex_grid_check.tscn`
- `movement_preview_check.tscn`
- `card_movement_check.tscn`
- `adventure_system_check.tscn`

Godot 沙箱和退出清理警告的判定方法见 `environment_memory.md`。
