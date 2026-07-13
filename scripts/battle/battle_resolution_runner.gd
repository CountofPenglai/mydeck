extends RefCounted
class_name BattleResolutionRunner

const MAX_EFFECTS_PER_ACTION := 32
const MAX_EFFECTS_PER_CARD := MAX_EFFECTS_PER_ACTION
const MAX_PENDING_ACTIONS := 64
const MAX_ACTIONS_PER_PUMP := 512

var controller: BattleController
var queue_scopes: Array = []
var queue_sequence: int = 0
var queue_depth: int = 0
var action_queue: Array[BattleActionFrame] = []
var is_draining_actions: bool = false
var action_active: bool = false
var current_action_effect_count: int = 0
var effect_limit_reached: bool = false
var next_action_id: int = 1
var current_action_id: int = 0


func setup(new_controller: BattleController) -> void:
	controller = new_controller
	reset()


func reset() -> void:
	queue_scopes = [[]]
	queue_sequence = 0
	queue_depth = 0
	action_queue.clear()
	is_draining_actions = false
	action_active = false
	current_action_effect_count = 0
	effect_limit_reached = false
	next_action_id = 1
	current_action_id = 0


func get_current_action_id() -> int:
	return current_action_id


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context)


func push_action_frame(frame: BattleActionFrame) -> bool:
	if frame == null or not frame.callback.is_valid():
		return false
	if action_queue.size() >= MAX_PENDING_ACTIONS:
		if controller != null:
			controller._emit_log("待结算行动达到 %d 个，新行动未加入队列。" % MAX_PENDING_ACTIONS)
		return false

	action_queue.append(frame)
	if not is_draining_actions and queue_depth <= 0:
		_drain_action_queue()
	return true


func resolve_effect_queue() -> void:
	if queue_depth > 0:
		return
	if queue_scopes.is_empty():
		queue_scopes.append([])
	_drain_current_effect_queue()
	if not is_draining_actions and not action_queue.is_empty():
		_drain_action_queue()


func clear_pending_actions() -> void:
	action_queue.clear()


func get_current_effect_queue_size() -> int:
	return _get_current_effect_queue().size()


func truncate_current_effect_queue(size: int) -> void:
	var queue := _get_current_effect_queue()
	var target_size := clampi(size, 0, queue.size())
	while queue.size() > target_size:
		queue.pop_back()


func _drain_action_queue() -> void:
	if is_draining_actions or action_queue.is_empty():
		return

	is_draining_actions = true
	if controller != null:
		controller._begin_action_resolution()
	var resolved_action_count := 0
	while not action_queue.is_empty():
		if resolved_action_count >= MAX_ACTIONS_PER_PUMP:
			var cancelled_actions := action_queue.duplicate()
			action_queue.clear()
			if controller != null:
				controller._emit_log("单次结算达到 %d 个行动，剩余行动已取消。" % MAX_ACTIONS_PER_PUMP)
				controller._on_action_frames_cancelled(cancelled_actions)
			break
		resolved_action_count += 1
		var frame: BattleActionFrame = action_queue.pop_front() as BattleActionFrame
		current_action_id = next_action_id
		next_action_id += 1
		action_active = true
		current_action_effect_count = 0
		effect_limit_reached = false
		_resolve_action_frame(frame)
		action_active = false
		current_action_effect_count = 0
		effect_limit_reached = false
		current_action_id = 0
	if controller != null:
		controller._end_action_resolution()
	is_draining_actions = false
	if controller != null:
		controller._notify_action_resolution_finished()


func _enqueue(callback: Callable, args: Array, priority: int, label: String, context) -> void:
	if not callback.is_valid():
		return
	if not _can_enqueue_resolution_item():
		return

	var queue := _get_current_effect_queue()
	queue.append(BattleResolutionEntry.create(
		callback,
		args,
		priority,
		queue_sequence,
		label,
		context
	))
	queue_sequence += 1


func _resolve_action_frame(frame: BattleActionFrame) -> void:
	if frame == null or not frame.callback.is_valid():
		return

	_push_effect_queue_scope()
	enqueue_effect(
		frame.callback,
		frame.args,
		frame.priority,
		frame.label,
		frame.context
	)
	_drain_current_effect_queue()
	if frame.after_callback.is_valid():
		frame.after_callback.callv(frame.after_args)
		_drain_current_effect_queue()
	if controller != null:
		controller._on_action_resolution_completed(current_action_id)
	_pop_effect_queue_scope()


func _drain_current_effect_queue() -> void:
	var queue := _get_current_effect_queue()
	queue_depth += 1
	while not queue.is_empty():
		if effect_limit_reached:
			queue.clear()
			break
		queue.sort_custom(Callable(self, "_compare_effect_queue_entries"))
		var entry: BattleResolutionEntry = queue.pop_front() as BattleResolutionEntry
		_execute_effect_queue_entry(entry)
	queue_depth -= 1


func _execute_effect_queue_entry(entry: BattleResolutionEntry) -> void:
	if entry == null or not _record_effect_resolution():
		return
	if not entry.callback.is_valid():
		return
	entry.callback.callv(entry.args)


func _compare_effect_queue_entries(a: BattleResolutionEntry, b: BattleResolutionEntry) -> bool:
	if a.priority == b.priority:
		return a.order < b.order
	return a.priority > b.priority


func _get_current_effect_queue() -> Array:
	if queue_scopes.is_empty():
		queue_scopes.append([])
	return queue_scopes[queue_scopes.size() - 1] as Array


func _push_effect_queue_scope() -> void:
	queue_scopes.append([])


func _pop_effect_queue_scope() -> void:
	if queue_scopes.size() <= 1:
		_get_current_effect_queue().clear()
		return
	queue_scopes.remove_at(queue_scopes.size() - 1)


func _can_enqueue_resolution_item() -> bool:
	if not action_active:
		return true
	if effect_limit_reached:
		return false
	if current_action_effect_count >= MAX_EFFECTS_PER_ACTION:
		effect_limit_reached = true
		if controller != null:
			controller._emit_log("单个主要行动效果结算达到 %d 个，后续效果不再加入结算。" % MAX_EFFECTS_PER_ACTION)
		return false
	return true


func _record_effect_resolution() -> bool:
	if not action_active:
		return true
	if effect_limit_reached:
		return false

	current_action_effect_count += 1
	if current_action_effect_count > MAX_EFFECTS_PER_ACTION:
		effect_limit_reached = true
		if controller != null:
			controller._emit_log("单个主要行动效果结算达到 %d 个，停止结算后续效果。" % MAX_EFFECTS_PER_ACTION)
		return false
	return true
