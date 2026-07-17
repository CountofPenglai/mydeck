# 游侠职业实现说明

## 实现范围

- 实现新版潜行：抵消一次敌方行动、主动破隐整次打击 `x1.5`、蒸汽与沙暴中的单体不可选取。
- 实现连击窗口与 `2/4/6/8/10` 里程碑，10 点扣除后保留溢出点；“猎杀时刻”为临时衍生牌。
- 实现火、水、土、风基础地表及六种高级地表，并接入移动代价、伤害、减免、射程与隐蔽规则。
- 实现匕首/弩选择型成对武器，以及潜行期间的特调配方与载荷选择 UI。
- 元素库存上限为 5，写回 `CharacterState.ranger_element_inventory`，可在同一次冒险的多场战斗间保留。
- 实现 3 张普通、11 张稀有、6 张史诗设计牌，并将 19 张新增牌与双职业“藏锋再起”加入默认游侠牌组。

## 通用交互

- 模式型攻击牌复用武器选择弹窗。
- “交错猎步”先选择敌人，再选择并预览合法六边格落点。
- “窃取预案”展示敌方手牌；匕首模式禁用不可复制牌。
- “绝处续弦”在抽牌结算完成后自动打开手牌单选，不在伤害回调内嵌套选择。
- “透支灵感”的弃牌债务在回合结束前合并为一次手牌多选。
- “回锋不止”可从弃牌堆执行 0 AP 独立回收行动，并使用现有手牌选择 UI 支付弃牌。
- “异域爆瓶”在选取位置前选择配方与催化剂，支付在卡牌结算时原子校验。

## 结算约束

- 连击点只在卡牌完整结算后的统一收尾点增加，卡牌脚本不重复发放。
- 敌方移动完成、敌方出牌完成、伤害后、打击后与潜行抵消均使用明确 hook；附魔触发进入行动/效果队列。
- “无处不猎”的自动回手在统一出牌收尾点检查，不轮询牌区。
- “猎手三幕”按后续三张牌依次执行随机弃牌、预选武器打击、进入潜行并离场。
- “终猎宣告”按匕首 `x3` / 弩 `x2` 覆盖基础破隐倍率，并处理匕首锁定与弩载荷复制。
- 爆瓶元素与无缝追击弃牌属于原子支付；支付失败会恢复 AP、手牌、状态与持久元素库存。
- 移动、普通攻击、调配和装备/弃牌区独立行动会关闭连击窗口。
- 潜行取消账本在主要行动结束时清理；附魔状态使用明确事件 hook，不连接全局 `state_changed`。
- 伤害接口返回真实生命损失，过量伤害不会放大采集与伤害后触发。

## 测试环境

Godot 4.6.3 会向 `%APPDATA%\Godot` 写入日志与缓存。受限沙箱可能在报告项目错误前崩溃，因此命令行检查必须按 `environment_memory.md` 的记录在授权环境运行，并使用控制台可执行文件。

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\ranger_compile.log" --path "D:\py_work\my-deck" --editor --quit
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\ranger_diag.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/ranger_mechanics_check.tscn"
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\battle_flow_after_ranger.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/battle_flow_check.tscn"
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\hex_grid_after_ranger.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/hex_grid_check.tscn"
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\battle_load_after_ranger.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/diagnose_battle_load.tscn"
```

上述脚本注册、游侠专项、战斗流程、六边网格和战斗加载诊断均已通过。无头退出时现有 DummyTexture/RID 清理提示仍会出现，但进程退出码为 0，且各诊断均打印完成标记。

## 后续边界

- 大地图“新冒险开始”流程已接入；`AdventureSession.start_new_demo()` 从角色模板深复制新队伍，因此新冒险不会继承上一局的游侠元素库存。同一次冒险内仍通过 `CharacterState.ranger_element_inventory` 和存档跨战斗保留。
- 牌库构筑界面尚未按品质筛选，本次将完整设计牌组接入样例游侠，便于战斗内验证。
