extends RefCounted
class_name BattleResolutionRunner

const MAX_EFFECTS_PER_ACTION := 32
const MAX_EFFECTS_PER_CARD := MAX_EFFECTS_PER_ACTION

var controller: BattleController
var queue_scopes: Array = []
var queue_sequence: int = 0
var queue_depth: int = 0
var action_stack: Array[BattleActionFrame] = []
var action_resolution_depth: int = 0
var current_action_effect_count: int = 0
var effect_limit_reached: bool = false
var next_action_id: int = 1
var action_id_stack: Array[int] = []


func setup(new_controller: BattleController) -> void:
	controller = new_controller
	reset()


func reset() -> void:
	queue_scopes = [[]]
	queue_sequence = 0
	queue_depth = 0
	action_stack.clear()
	action_resolution_depth = 0
	current_action_effect_count = 0
	effect_limit_reached = false
	next_action_id = 1
	action_id_stack.clear()


func get_current_action_id() -> int:
	if action_id_stack.is_empty():
		return 0
	return action_id_stack.back()


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context, false)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context, true)


func push_action_frame(frame: BattleActionFrame) -> void:
	if frame == null or not frame.callback.is_valid():
		return
	if not _can_enqueue_resolution_item():
		return

	action_stack.append(frame)
	if action_resolution_depth <= 0 and queue_depth <= 0:
		resolve_action_stack()


func push_card_frame(frame: BattleCardFrame) -> void:
	if frame == null:
		return

	var context_dict := {}
	if frame.context != null:
		context_dict = frame.context.to_dict()
	push_action_frame(BattleActionFrame.create(
		Callable(frame.card, "play"),
		[context_dict, frame.targets],
		_get_card_effect_priority(frame.card),
		"%s 卡牌效果" % frame.card.card_name,
		frame.context,
		Callable(self, "_finish_card_frame"),
		[frame]
	))


func resolve_effect_queue() -> void:
	if queue_scopes.is_empty():
		queue_scopes.append([])
	_drain_current_effect_queue()


func resolve_action_stack() -> void:
	if action_stack.is_empty():
		return

	if controller != null:
		controller._begin_action_resolution()
	while not action_stack.is_empty():
		var frame: BattleActionFrame = action_stack.pop_back() as BattleActionFrame
		var action_id := next_action_id
		next_action_id += 1
		var parent_effect_count := current_action_effect_count
		var parent_limit_reached := effect_limit_reached
		action_id_stack.append(action_id)
		action_resolution_depth += 1
		current_action_effect_count = 0
		effect_limit_reached = false
		_resolve_action_frame(frame)
		action_resolution_depth -= 1
		current_action_effect_count = parent_effect_count
		effect_limit_reached = parent_limit_reached
		if frame != null and frame.after_callback.is_valid():
			frame.after_callback.callv(frame.after_args)
		action_id_stack.pop_back()
	if controller != null:
		controller._end_action_resolution()


func resolve_card_stack() -> void:
	resolve_action_stack()


func _enqueue(callback: Callable, args: Array, priority: int, label: String, context, is_trigger: bool) -> void:
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
		context,
		is_trigger
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
	_pop_effect_queue_scope()

func _finish_card_frame(frame: BattleCardFrame) -> void:
	if frame == null or frame.user == null or frame.card == null:
		return

	if frame.discard_after_play:
		if controller != null and controller.should_card_exile_after_play(frame):
			controller.finish_card_to_exile(frame)
		elif controller != null and controller.has_method("should_card_enter_mana_after_play") and controller.should_card_enter_mana_after_play(frame):
			controller.finish_druid_card_to_mana(frame)
		else:
			frame.user.discard_card(frame.card, {
				"controller": controller,
				"reason": "card_after_play",
				"source": frame.user,
				"source_card": frame.card,
				"card_context": frame.context,
			})
	if controller != null:
		var actual_ap_cost := frame.card.ap_cost
		if frame.context != null:
			actual_ap_cost = int(frame.context.extra.get("actual_ap_cost", frame.card.ap_cost))
		controller._emit_log("%s 打出 %s，消耗 %d AP。" % [frame.user.get_display_name(), frame.card.card_name, actual_ap_cost])
		controller.state_changed.emit()
		controller._check_battle_end()


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
		if not action_stack.is_empty():
			resolve_action_stack()
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


func _get_card_effect_priority(card: CardData) -> int:
	if card != null and card.effect != null:
		return _get_effect_priority(card.effect)
	return 0


func _get_effect_priority(effect) -> int:
	if effect == null:
		return 0
	var value = effect.get("effect_priority")
	if value == null:
		return 0
	return int(value)


func _can_enqueue_resolution_item() -> bool:
	if action_resolution_depth <= 0:
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
	if action_resolution_depth <= 0:
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
