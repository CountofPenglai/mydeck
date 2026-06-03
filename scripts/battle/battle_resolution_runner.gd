extends RefCounted
class_name BattleResolutionRunner

const MAX_EFFECTS_PER_CARD := 32

var controller: BattleController
var queue_scopes: Array = []
var queue_sequence: int = 0
var queue_depth: int = 0
var card_stack: Array[BattleCardFrame] = []
var card_resolution_depth: int = 0
var current_card_effect_count: int = 0
var effect_limit_reached: bool = false


func setup(new_controller: BattleController) -> void:
	controller = new_controller
	reset()


func reset() -> void:
	queue_scopes = [[]]
	queue_sequence = 0
	queue_depth = 0
	card_stack.clear()
	card_resolution_depth = 0
	current_card_effect_count = 0
	effect_limit_reached = false


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context, false)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context, true)


func push_card_frame(frame: BattleCardFrame) -> void:
	if frame == null:
		return
	card_stack.append(frame)
	if card_resolution_depth <= 0 and queue_depth <= 0:
		resolve_card_stack()


func resolve_effect_queue() -> void:
	if queue_scopes.is_empty():
		queue_scopes.append([])
	_drain_current_effect_queue()


func resolve_card_stack() -> void:
	while not card_stack.is_empty():
		var frame := card_stack.pop_back()
		card_resolution_depth += 1
		current_card_effect_count = 0
		effect_limit_reached = false
		_resolve_card_frame(frame)
		card_resolution_depth -= 1
		current_card_effect_count = 0
		effect_limit_reached = false


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


func _resolve_card_frame(frame: BattleCardFrame) -> void:
	if frame.user == null or frame.card == null:
		return

	_push_effect_queue_scope()
	var context_dict := {}
	if frame.context != null:
		context_dict = frame.context.to_dict()
	enqueue_effect(
		Callable(frame.card, "play"),
		[context_dict, frame.targets],
		_get_card_effect_priority(frame.card),
		"%s 卡牌效果" % frame.card.card_name,
		frame.context
	)
	_drain_current_effect_queue()
	_pop_effect_queue_scope()

	frame.user.discard_card(frame.card)
	if controller != null:
		controller._emit_log("%s 打出 %s，消耗 %d AP。" % [frame.user.get_display_name(), frame.card.card_name, frame.card.ap_cost])
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
		var entry: BattleResolutionEntry = queue.pop_front()
		_execute_effect_queue_entry(entry)
		if not card_stack.is_empty():
			resolve_card_stack()
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
	return queue_scopes[queue_scopes.size() - 1]


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
	if card_resolution_depth <= 0:
		return true
	if effect_limit_reached:
		return false
	if current_card_effect_count >= MAX_EFFECTS_PER_CARD:
		effect_limit_reached = true
		if controller != null:
			controller._emit_log("单张卡牌效果结算达到 %d 个，后续效果不再加入结算。" % MAX_EFFECTS_PER_CARD)
		return false
	return true


func _record_effect_resolution() -> bool:
	if card_resolution_depth <= 0:
		return true
	if effect_limit_reached:
		return false

	current_card_effect_count += 1
	if current_card_effect_count > MAX_EFFECTS_PER_CARD:
		effect_limit_reached = true
		if controller != null:
			controller._emit_log("单张卡牌效果结算达到 %d 个，停止结算后续效果。" % MAX_EFFECTS_PER_CARD)
		return false
	return true

