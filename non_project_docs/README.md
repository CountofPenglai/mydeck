# 项目文档索引

本目录带有 `.gdignore`，用于保存开发文档，不参与 Godot 资源导入。文档中的“当前状态”以最近更新的总览为准；专题实现记录保留时间线，较早章节可能被同文件的后续章节覆盖。

## 当前总览

- [项目结构与 Skill 工作流](project_structure_and_skill_workflow.md)：当前架构、数据所有权、运行流程、测试矩阵和 Skill 选择方法。
- [环境记录](environment_memory.md)：Godot 路径、版本、沙箱问题和命令行测试方法。
- [战斗结算约定](battle_resolution_notes.md)：主要行动、附属效果、trigger、优先级和 GDScript 类型规则。

## 系统实现记录

- [德鲁伊职业实现](druid_implementation_notes.md)：法力区、形态、双面牌、剩余卡牌和德鲁伊武器。
- [游侠职业实现](ranger_implementation_notes.md)：潜行、连击、元素、卡牌与成对武器。
- [第一章敌人与怪物卡池实现](chapter_one_enemy_implementation.md)：怪物牌、分类卡组、敌人特性、遭遇池、公开意图与简版战斗情报 UI。
- [战斗场景加载排查](battle_scene_load_investigation.md)：历史加载故障、定位过程和验证命令。
- [UI 加载问题记录](ui_load_issue_notes.md)：历史 UI 资源与配置故障。

## 内容与美术

- [战斗示例指南](battle_example_guide.md)：示例角色、敌人和基本操作。
- [战斗场景原型指南](battle_scene_prototype_guide.md)：战场原型资源约定。
- [美术风格指南](art_style_guide.md)：卡牌、角色、战场和 UI 的视觉方向。
- [美术资源清单](../assets/art/asset_manifest.md)：已生成与已接入资源。

## 事实来源优先级

出现冲突时按以下顺序判断：

1. 当前代码、`.tres` 资源和可运行诊断。
2. [项目结构与 Skill 工作流](project_structure_and_skill_workflow.md) 中标记为“当前”的说明。
3. 最近日期的专题实现记录。
4. 较早的调查记录与外部设计原案。

外部职业和系统设计文档位于 `D:/设计与开发文档/总之是卡组/`。它们描述设计目标；本目录记录项目当前实现和工程约束。

## 维护规则

- 新增系统时更新总览中的模块表、数据流和诊断表。
- 修复跨模块问题时更新对应专题记录，不为一次性日志另建长期文档。
- 专题文档保留历史时，在旧章节标题中注明日期或“历史”，避免把旧限制误读为当前状态。
- 测试命令集中维护在 `environment_memory.md`，其他文档只引用或列出专项场景。
- 美术文件新增后同步更新 `assets/art/asset_manifest.md`。
