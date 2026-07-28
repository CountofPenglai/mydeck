# Battle Resolution Notes

本文档记录两个容易反复踩坑的约定：

- GDScript 中 `:=` 遇到 `Variant` 时的写法规则。
- 战斗主要行动栈、附属动作队列、trigger 队列的当前语义。

## GDScript `:=` 与 Variant

项目开启了 warning treated as error。以下 Godot warning 会直接导致脚本解析失败：

```text
The variable type is being inferred from a Variant value, so it will be typed as Variant.
```

### 触发原因

`:=` 会让 Godot 从右侧表达式推断变量类型。若右侧返回值是 `Variant`，Godot 无法推断出具体类型，就会把变量推断成 `Variant`，并在当前项目设置下报错。

常见来源：

- `Array.pop_back()`
- `Array.pop_front()`
- 未强类型的 `Array` 下标读取
- `Dictionary.get()`
- `Resource.get(property_name)`
- 一些未声明返回类型的函数

### 推荐规则

如果右侧可能是 `Variant`，不要用裸 `:=`。改用显式类型，必要时加 `as`。

错误示例：

```gdscript
var frame := card_stack.pop_back()
var entry := queue.pop_front()
var value := effect.get("effect_priority")
```

正确示例：

```gdscript
var frame: BattleCardFrame = card_stack.pop_back() as BattleCardFrame
var entry: BattleResolutionEntry = queue.pop_front() as BattleResolutionEntry
var value = effect.get("effect_priority")
```

如果值本来就是动态类型，并且后续会做 null/type 检查，可以使用普通 `=`，避免触发推断 warning：

```gdscript
var value = effect.get("effect_priority")
if value == null:
	return 0
return int(value)
```

### 写新代码时的经验规则

- `:=` 只用于右侧类型明确的表达式，例如 `BattleResolutionEntry.new()`、`Vector2.ZERO`、强类型函数返回值。
- 从 `Array` / `Dictionary` / `Resource.get()` 取值时，优先写显式类型。
- 若数组声明为 `Array[SomeType]`，但使用 `pop_back()` / `pop_front()`，仍建议显式 cast。
- 资源导出数组若 Godot 序列化容易不稳定，可以导出为 `Array[Resource]`，再通过 getter 过滤成强类型数组。

## 行动与效果结算核心

当前结算核心在：

- `res://scripts/battle/battle_resolution_runner.gd`
- `res://scripts/battle/battle_resolution_entry.gd`
- `res://scripts/battle/battle_action_frame.gd`
- `res://scripts/battle/battle_card_frame.gd`

控制器通过以下方法提交结算项：

```gdscript
push_action_frame(frame)
enqueue_effect(callback, args, priority, label, context)
enqueue_trigger(callback, args, priority, label, context)
resolve_effect_queue()
```

### 主要行动

主要行动指由玩家、AI 或回合流程直接发起的一层动作。当前包括：

- 打出牌。
- 直接点击 UI 进行移动。
- 直接点击 UI 进行普通攻击。
- 点击 UI 消耗势。
- 回合开始。
- 回合结束。
- 后续装备启动式异能等直接点击动作也应接入主要行动栈。

主要行动使用 `BattleActionFrame`，进入 FIFO `action_queue`。runner 只有一个非重入 pump；行动或 after 回调追加的新行动只会排到队尾，不会递归调用新的 resolve。

控制器会验证回合所有权和结算锁。玩家命令只能由当前存活单位在 `ACTIVE` 行动阶段提交；AI 使用显式内部提交窗口，一次决策只提交一个行动。

每个主要行动结算时会创建独立的附属动作队列作用域：

1. 将主要行动自身的 `callback` 作为一个普通效果入队。
2. drain 当前队列。
3. 行动内部追加的效果、状态事件、trigger 都进入当前队列。
4. 当前行动追加的新主要行动进入 FIFO 队尾，等待当前行动的效果和 after 阶段全部结束。
5. 当前效果队列清空后执行 `after_callback`，再 drain after 阶段新增的效果，最后退出 action id 和队列作用域。

`after_callback` 属于当前主要行动，沿用同一个 action id 和效果预算。卡牌离场、弃牌 hook、回合推进请求都因此能在解锁前完成，不会落入默认队列或形成递归调用链。

### 结算中的 UI 锁

主要行动栈结算期间，控制器通过 `is_resolving_actions()` 暴露锁定状态。`BattleScene` 必须在该状态下禁用或拒绝所有会发起独立主要行动的 UI：

- 地图点击移动、攻击目标、卡牌目标。
- 移动、攻击、结束回合等按钮。
- 手牌、弃牌堆余势牌。
- 职业资源按钮，例如势。
- 后续装备启动式异能按钮。

这个锁同时由控制器领域入口执行，不只依赖 UI。结算内部若确实需要提交新行动，必须通过明确的内部入口；状态和卡牌 after hook 只能追加附属效果，不能直接打开新的玩家命令。

### 队列条目

每个队列条目是一个 `BattleResolutionEntry`，包含：

- `callback`: 实际要调用的方法。
- `args`: `callback.callv(args)` 的参数。
- `priority`: 优先级。
- `order`: 入队顺序，由 runner 自动分配。
- `label`: 调试/日志用名称。
- `context`: 结算上下文。

### 队列排序

效果队列每次出队前都会排序：

1. `priority` 数值越大，越先结算。
2. `priority` 相同，则 `order` 越小，越先结算。

也就是说，同一时点先把所有效果加入队列，再按优先级和入队顺序依次结算。

### 附属动作与 trigger

`enqueue_effect()` 与 `enqueue_trigger()` 都进入当前效果队列。

两者使用相同的队列条目和排序规则；`enqueue_trigger()` 是用于表达事件来源的语义入口，不再保存无效的 `is_trigger` 元数据。

写状态、装备、卡牌 trigger 时，应把后续效果加入当前结算队列，而不是立即执行。这些由主要行动触发出来的效果统称为附属动作。

当前约定：伤害前倍率、伤害减免、AP 费用查询等“必须立即返回数值”的 before/query hook 保持同步；抽牌后、弃牌后、伤害后、治疗后、护甲变化、区域牌触发等 after hook 统一进入当前效果队列，并受 32 效果预算保护。

示例：

```gdscript
controller.enqueue_trigger(
	Callable(controller, "_emit_basic_attack_trigger"),
	[trigger_context],
	0,
	"普通攻击触发",
	trigger_context
)
```

### 卡牌打出

卡牌打出是主要行动的一种，由控制器创建 `BattleCardFrame` 并包装成 `BattleActionFrame`。

流程：

1. 提交阶段只验证请求并保留卡牌行动，不扣 AP、不支付特殊费用。
2. 卡牌行动开始后重新验证来源、目标和费用，并在同一个 action id 内完成支付。
3. 支付产生的 trigger 先进入队列；支付后续效果会在这些 trigger 结算后检查角色存活和卡牌来源，再执行 `card.play()`。
4. 卡牌效果及其 trigger 全部 drain 后，通过 `after_callback` 执行弃牌、放逐、法力区归属、日志和战斗结束检查。

这实现了以下语义：

- 一张牌及其触发的非卡牌效果使用队列。
- 同一卡牌实体在行动完成前带有 in-flight 标记，不能重复提交。
- 新卡牌行动进入 FIFO 队尾，不会嵌入当前卡牌效果队列。

### 队列作用域

`queue_scopes` 用于隔离当前主要行动的附属动作队列。

- 战斗 setup 等非主要行动流程仍可使用默认队列作用域。
- 每个主要行动结算时 `_push_effect_queue_scope()` 新建作用域。
- 主要行动结算完成后 `_pop_effect_queue_scope()` 移除作用域。

因此，主要行动 A 的附属动作队列不会和主要行动 B 混合；行动 A 中提交的行动 B 会在 A 的效果和 after 阶段完成后开始。

### 32 个效果上限

为了防止死循环，单个主要行动最多结算 `MAX_EFFECTS_PER_ACTION = 32` 个附属动作。`MAX_EFFECTS_PER_CARD` 仍作为兼容常量指向同一数值。

当前规则：

- 只有 `action_active` 时启用该限制。
- 每执行一个队列条目，计数加 1。
- 达到上限后，后续附属效果不再加入当前效果队列；回合推进等主要行动不使用这个局部效果预算。
- 若队列 drain 过程中发现已达到限制，会清空当前队列并停止后续结算。
- 主要行动结算结束后，计数和限制状态会重置。

写会反复触发自身或互相触发的效果时，仍应主动设计终止条件；32 上限只是兜底。

runner 另有两层总量保护：待结算行动最多 64 个，单次 pump 最多处理 512 个行动。达到总行动上限时会取消剩余行动并清理其中卡牌的 in-flight 标记。

## 新机制接入建议

### 状态效果

状态不要在事件发生时直接修改复杂后续流程，而是把“后续要发生的事”入队。

例如抵挡成功后触发切换装备：

```gdscript
controller.queue_unit_status_event("on_block_spent", unit, damage_context)
```

状态本身通过 `effect_priority` 决定同一时点内的先后顺序。

### 卡牌效果

卡牌效果内可以直接完成本牌的主效果，也可以继续 `enqueue_effect()` / `enqueue_trigger()`。

若卡牌效果会打出另一张牌，应通过控制器的内部行动提交入口排入 FIFO 队列，不要直接调用那张牌的 `play()`。

### 装备与 trigger

装备 trigger 也应通过队列提交。切换装备相关已预留三个时点：

- 切换装备时。
- 切换掉当前装备。
- 切换出新的装备。

“切换装备时”是读取旧装备状态的 before 信号，必须在实际替换前同步发出；“切换掉当前装备”和“切换出新的装备”属于 after trigger，继续使用 `enqueue_trigger()`。

### 环境与战场对象

- 环境伤害通过 `BattleController.apply_environment_damage()` 进入单位伤害管线，正常经过伤害减免与护甲，但不创建攻击者伤害后、吸血或打击 trigger。
- 战场对象使用独立的 `apply_object_damage()`，不得伪装为 `BattleUnitState`，也不得进入行动序、AI 或胜负判断。
- 对象生命归零时同步标记 `destroyed` 并移除其永久元素源，确保占格、视线和元素状态立即失效；`destruction_queued` 只保护爆炸、倒塌等销毁副作用一次性进入当前效果队列。即使 32 项效果预算耗尽，关键销毁状态也不能依赖可丢弃的队列条目。
- 武器打击以战场对象为目标时仍经过攻击模式校验、打击前后 hook、潜行消耗和基础攻击 trigger；仅单位专属的减免、护甲、状态与职业目标效果明确跳过。
- 同一次行动中的对象连锁使用 action id 和对象级触发记录阻止重复触发。元素施加导致的爆炸仍属于原行动的附属效果。

## 快速检查清单

新增或修改结算代码时，先检查：

- 是否从 `Array` / `Dictionary` / `Resource.get()` 用 `:=` 接了 `Variant`。
- 是否把 trigger 直接执行了，而不是入队。
- 玩家或 AI 直接发起的动作是否进入了 `push_action_frame()`。
- 是否需要设置 `effect_priority`。
- 是否在卡牌效果中直接打出另一张牌，而不是压入主要行动栈。
- 是否可能产生循环触发，并需要显式终止条件。
