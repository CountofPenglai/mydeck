# my_deck

`my_deck` 是一个使用 Godot 4.6 开发的六边形战棋卡组构筑游戏原型。当前可运行内容以两层冒险 Demo 为主，队伍由战士、游侠和德鲁伊组成，包含大地图探索、战斗、卡牌、装备、诅咒、奖励、商店、营地和存档框架。

## 快速入口

- 主场景：`res://scenes/adventure_map_scene.tscn`
- 战斗场景：`res://scenes/battle_scene.tscn`
- 全局冒险服务：`res://scripts/adventure/adventure_session.gd`
- 项目架构与 Skill 工作流：[project_structure_and_skill_workflow.md](non_project_docs/project_structure_and_skill_workflow.md)
- 项目文档索引：[non_project_docs/README.md](non_project_docs/README.md)
- 本机 Godot 与测试环境：[environment_memory.md](non_project_docs/environment_memory.md)

## 运行项目

使用 Godot 4.6.3 打开 `project.godot`，运行项目即可进入大地图。项目使用：

- 基准分辨率 `1280x720`
- `canvas_items` 拉伸模式
- `expand` 宽高比策略
- `AdventureSession` Autoload

命令行严格加载检查：

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\project_compile.log" --path "D:\py_work\my-deck" --editor --quit
```

Godot 会写入 `%APPDATA%\Godot`。在 Codex 受限沙箱中运行时，应按 [environment_memory.md](non_project_docs/environment_memory.md) 的说明申请沙箱外执行。

## 目录

| 路径 | 作用 |
| --- | --- |
| `assets/` | 卡牌、角色、战场和 UI 美术资源 |
| `scenes/` | 大地图与战斗两个主要场景 |
| `scripts/adventure/` | 地图生成、冒险会话、奖励、商店、事件、存档 |
| `scripts/battle/` | 回合、行动队列、六边网格、寻路、伤害、打击和战斗 UI |
| `scripts/cards/` | 卡牌数据、效果、条件和职业卡牌实现 |
| `scripts/characters/` | 角色静态数据、持久状态、装备栏和职业资源 |
| `scripts/items/` | 装备数据、运行时状态和武器效果 |
| `scripts/curses/` | 诅咒定义、实例、生命周期和冒险队伍状态 |
| `scripts/status/` | 战斗状态及事件 hook 实现 |
| `resources/` | Godot `.tres` 配置资源，禁止写入战斗期临时状态 |
| `tools/diagnostics/` | 可独立运行的无头回归诊断场景 |
| `non_project_docs/` | 架构、实现记录、测试环境和美术规范 |

## 开发约束

- `CardData`、`EquipmentData` 等共享 Resource 只保存配置；战斗层数、冷却、弹仓和临时加值放入运行时状态。
- 玩家、AI、回合开始和回合结束等主要行动进入 `BattleResolutionRunner`，嵌套效果通过效果队列结算。
- 地图坐标、距离和范围统一使用六边格 `Vector2i` 与整数距离。
- 修改系统时同步更新相关资源、UI、存档字段和专项诊断。
- 新机制开始前选择匹配的 GodotPrompter Skill，完成后运行代码审查与诊断。

详细约定见 [project_structure_and_skill_workflow.md](non_project_docs/project_structure_and_skill_workflow.md) 与 [battle_resolution_notes.md](non_project_docs/battle_resolution_notes.md)。
