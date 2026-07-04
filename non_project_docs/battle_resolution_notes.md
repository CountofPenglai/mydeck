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
push_card_frame(frame)
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

主要行动使用 `BattleActionFrame`，进入 `action_stack`。栈行为是后进先出。

`action_stack` 只用于管理当前主要行动，以及这个行动结算过程中附带产生的其它主要行动。玩家在 UI 上快速点击产生的另一个独立主要行动，不应该在当前主要行动栈结算中插入。

每个主要行动结算时会创建独立的附属动作队列作用域：

1. 将主要行动自身的 `callback` 作为一个普通效果入队。
2. drain 当前队列。
3. 行动内部追加的效果、状态事件、trigger 都进入当前队列。
4. 若结算中压入新的主要行动，新的主要行动先结算。
5. 当前主要行动的队列清空后，才执行 `after_callback`。

`after_callback` 在当前主要行动完全退出后执行。这样 AI 或 UI 在 after 阶段发起的新主要行动，会按自然发起顺序立即结算，不会因为仍处在旧行动深度里被后续行动反向压栈。

### 结算中的 UI 锁

主要行动栈结算期间，控制器通过 `is_resolving_actions()` 暴露锁定状态。`BattleScene` 必须在该状态下禁用或拒绝所有会发起独立主要行动的 UI：

- 地图点击移动、攻击目标、卡牌目标。
- 移动、攻击、结束回合等按钮。
- 手牌、弃牌堆余势牌。
- 职业资源按钮，例如势。
- 后续装备启动式异能按钮。

这个锁只阻止玩家 UI 发起新的独立主要行动；结算内部由效果、trigger 或 after 回调压入的附带主要行动仍然允许进入 `action_stack`。

### 队列条目

每个队列条目是一个 `BattleResolutionEntry`，包含：

- `callback`: 实际要调用的方法。
- `args`: `callback.callv(args)` 的参数。
- `priority`: 优先级。
- `order`: 入队顺序，由 runner 自动分配。
- `label`: 调试/日志用名称。
- `context`: 结算上下文。
- `is_trigger`: 是否为 trigger。当前主要是元数据，排序规则不因它变化。

### 队列排序

效果队列每次出队前都会排序：

1. `priority` 数值越大，越先结算。
2. `priority` 相同，则 `order` 越小，越先结算。

也就是说，同一时点先把所有效果加入队列，再按优先级和入队顺序依次结算。

### 附属动作与 trigger

`enqueue_effect()` 与 `enqueue_trigger()` 都进入当前效果队列。

当前差异：

- `enqueue_effect()` 创建普通效果条目。
- `enqueue_trigger()` 创建 `is_trigger = true` 的条目。
- 排序仍统一看 `priority` 和 `order`。

写状态、装备、卡牌 trigger 时，应把后续效果加入当前结算队列，而不是立即执行。这些由主要行动触发出来的效果统称为附属动作。

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

卡牌打出现在也是主要行动的一种。`push_card_frame()` 仍然保留为兼容入口，但内部会转换为 `BattleActionFrame` 并进入 `action_stack`。

流程：

1. `push_card_frame(frame)` 将卡牌帧转换为主要行动。
2. 该主要行动把 `card.play(context, targets)` 加入附属动作队列。
3. drain 当前队列。牌效果中追加的非卡牌效果、trigger 都进入同一个队列作用域。
4. 队列清空后，通过 `after_callback` 执行弃牌、日志、战斗结束检查等收尾流程。

这实现了以下语义：

- 一张牌及其触发的非卡牌效果使用队列。
- 如果一张牌打出后又触发另一张牌打出，后打出的牌会先结算。
- 后打出的牌及其 trigger 队列结算完成后，再回到先打出牌的剩余队列。

### 队列作用域

`queue_scopes` 用于隔离当前主要行动的附属动作队列。

- 战斗 setup 等非主要行动流程仍可使用默认队列作用域。
- 每个主要行动结算时 `_push_effect_queue_scope()` 新建作用域。
- 主要行动结算完成后 `_pop_effect_queue_scope()` 移除作用域。

因此，主要行动 A 的附属动作队列不会和主要行动 B 的附属动作队列混成一个队列；但若行动 A 的队列中途压入行动 B，runner 会先处理行动 B。

### 32 个效果上限

为了防止死循环，单个主要行动最多结算 `MAX_EFFECTS_PER_ACTION = 32` 个附属动作。`MAX_EFFECTS_PER_CARD` 仍作为兼容常量指向同一数值。

当前规则：

- 只有 `action_resolution_depth > 0` 时启用该限制。
- 每执行一个队列条目，计数加 1。
- 达到上限后，后续效果不再加入栈和队列。
- 若队列 drain 过程中发现已达到限制，会清空当前队列并停止后续结算。
- 主要行动结算结束后，计数和限制状态会重置。

写会反复触发自身或互相触发的效果时，仍应主动设计终止条件；32 上限只是兜底。

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

若卡牌效果会打出另一张牌，应压入新的主要行动，通常通过 `BattleCardFrame` / `push_card_frame()`，不要直接调用那张牌的 `play()`。

### 装备与 trigger

装备 trigger 也应通过队列提交。切换装备相关已预留三个时点：

- 切换装备时。
- 切换掉当前装备。
- 切换出新的装备。

这些时点后续接入具体装备 trigger 时，应继续沿用 `enqueue_trigger()`。

## 快速检查清单

新增或修改结算代码时，先检查：

- 是否从 `Array` / `Dictionary` / `Resource.get()` 用 `:=` 接了 `Variant`。
- 是否把 trigger 直接执行了，而不是入队。
- 玩家或 AI 直接发起的动作是否进入了 `push_action_frame()`。
- 是否需要设置 `effect_priority`。
- 是否在卡牌效果中直接打出另一张牌，而不是压入主要行动栈。
- 是否可能产生循环触发，并需要显式终止条件。
