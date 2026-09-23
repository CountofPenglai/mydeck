extends RefCounted
class_name BattleResolutionRunner

const CARD_CHOICE_STATE := preload("res://scripts/battle/battle_card_choice_state.gd")
const SELECTION_SERVICE := preload("res://scripts/battle/battle_selection_service.gd")
const UNIT_TARGET_CHOICE_STATE := preload("res://scripts/battle/battle_unit_target_choice_state.gd")

signal hand_card_choice_requested(choice)
signal hand_card_choice_cleared
signal unit_target_choice_requested(choice)
signal unit_target_choice_cleared

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
var current_action_frame: BattleActionFrame
var after_current_effect_queue: Array = []
var attack_after_scopes: Array = []
var descendant_after_scopes: Array = []
var pending_hand_card_choice
var pending_unit_target_choice
var selection_service = SELECTION_SERVICE.new()
var resolved_actions_in_pump: int = 0
var current_frame_after_callback_started: bool = false
var current_frame_ap_finalization_started: bool = false
var current_frame_completion_notified: bool = false


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
	current_action_frame = null
	after_current_effect_queue.clear()
	attack_after_scopes.clear()
	descendant_after_scopes.clear()
	pending_hand_card_choice = null
	pending_unit_target_choice = null
	resolved_actions_in_pump = 0
	current_frame_after_callback_started = false
	current_frame_ap_finalization_started = false
	current_frame_completion_notified = false
	hand_card_choice_cleared.emit()
	unit_target_choice_cleared.emit()


func get_current_action_id() -> int:
	return current_action_id


func record_current_action_ap_spent(unit: BattleUnitState, amount: int) -> void:
	if current_action_frame == null or amount <= 0:
		return
	current_action_frame.record_ap_spent(unit, amount)


func request_hand_card_choice(
	owner: BattleUnitState,
	source_card: CardData,
	min_count: int,
	max_count: int,
	prompt: String,
	continuation: Callable,
	card_filter: Callable = Callable()
) -> bool:
	return request_zone_card_choice(
		owner,
		source_card,
		PackedStringArray(["hand"]),
		min_count,
		max_count,
		prompt,
		continuation,
		card_filter
	)


func request_zone_card_choice(
	owner: BattleUnitState,
	source_card: CardData,
	zones: PackedStringArray,
	min_count: int,
	max_count: int,
	prompt: String,
	continuation: Callable,
	card_filter: Callable = Callable(),
	cancel_submits_empty: bool = false
) -> bool:
	if owner == null or source_card == null or not continuation.is_valid() \
			or min_count < 0 or max_count < min_count or not selection_service.are_zones_valid(zones):
		return false
	# A suspended selection can only safely resume a normal action's open effect
	# scope. Attack scopes have their own deferred callback contract.
	if not action_active or current_action_frame == null or _has_pending_choice() \
			or is_attack_scope_active() or queue_scopes.size() != 2:
		if controller != null:
			controller._emit_log("当前结算阶段不支持手牌选择。")
		return false
	var choice: Variant = CARD_CHOICE_STATE.create(owner, source_card, min_count, max_count, prompt, continuation)
	choice.zones = zones
	choice.card_filter = card_filter
	choice.cancel_submits_empty = cancel_submits_empty
	if choice.get_live_cards().is_empty():
		# There is no player decision to make. Continue with an empty result rather
		# than silently selecting a card or leaving the action permanently locked.
		var empty_selection: Array[CardData] = []
		enqueue_effect(continuation, [empty_selection], 0, "手牌选择：无可选牌")
		return true
	pending_hand_card_choice = choice
	hand_card_choice_requested.emit(choice)
	return true


func submit_hand_card_choice(selected: Array[CardData]) -> bool:
	var choice: Variant = pending_hand_card_choice
	if choice == null:
		return false
	if not selection_service.validate(choice.owner, selected, choice.zones, choice.min_count, choice.max_count, choice.source_card):
		return false
	for card in selected:
		if choice.card_filter.is_valid() and not choice.card_filter.call(card):
			return false
	var continuation: Callable = choice.continuation
	pending_hand_card_choice = null
	hand_card_choice_cleared.emit()
	enqueue_effect(continuation, [selected.duplicate()], 0, "手牌选择：已确认")
	_resume_suspended_action()
	return true


func has_pending_hand_card_choice() -> bool:
	return pending_hand_card_choice != null


func get_pending_hand_card_choice():
	return pending_hand_card_choice


func cancel_pending_hand_card_choice() -> void:
	var choice = pending_hand_card_choice
	if choice == null:
		return
	# Opt-in choices have an already-paid guaranteed continuation. Cancellation is
	# an empty selection, not abandonment of that continuation; legacy choices
	# retain their existing cancellation behavior.
	if bool(choice.cancel_submits_empty):
		submit_hand_card_choice([])
		return
	pending_hand_card_choice = null
	hand_card_choice_cleared.emit()
	_resume_suspended_action()


func request_unit_target_choice(owner: BattleUnitState, source_card: CardData, prompt: String, continuation: Callable, candidates: Array, target_filter: Callable = Callable()) -> bool:
	if owner == null or source_card == null or not continuation.is_valid() or not action_active \
			or current_action_frame == null or _has_pending_choice() or is_attack_scope_active() or queue_scopes.size() != 2:
		return false
	var choice = UNIT_TARGET_CHOICE_STATE.new()
	choice.owner = owner
	choice.source_card = source_card
	choice.prompt = prompt
	choice.continuation = continuation
	choice.candidates.assign(candidates)
	choice.target_filter = target_filter
	if choice.get_live_targets().is_empty():
		enqueue_effect(continuation, [null], 0, "单位选择：无合法目标")
		return true
	pending_unit_target_choice = choice
	unit_target_choice_requested.emit(choice)
	return true


func submit_unit_target_choice(target: BattleUnitState = null) -> bool:
	var choice = pending_unit_target_choice
	if choice == null or (target != null and not choice.get_live_targets().has(target)):
		return false
	var continuation: Callable = choice.continuation
	pending_unit_target_choice = null
	unit_target_choice_cleared.emit()
	enqueue_effect(continuation, [target], 0, "单位选择：已确认" if target != null else "单位选择：跳过")
	_resume_suspended_action()
	return true


func has_pending_unit_target_choice() -> bool:
	return pending_unit_target_choice != null


func get_pending_unit_target_choice():
	return pending_unit_target_choice


func cancel_pending_unit_target_choice() -> void:
	if pending_unit_target_choice != null:
		submit_unit_target_choice(null)


func _has_pending_choice() -> bool:
	return pending_hand_card_choice != null or pending_unit_target_choice != null


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	_enqueue(callback, args, priority, label, context)


func enqueue_after_current_effect_queue(callback: Callable, args: Array = [], label: String = "") -> void:
	if not callback.is_valid():
		return
	if not attack_after_scopes.is_empty():
		(attack_after_scopes.back() as Array).append(BattleResolutionEntry.create(callback, args, 0, queue_sequence, label, null))
		queue_sequence += 1
		return
	if not descendant_after_scopes.is_empty():
		(descendant_after_scopes.back() as Array).append(BattleResolutionEntry.create(callback, args, 0, queue_sequence, label, null))
		queue_sequence += 1
		return
	if not action_active:
		after_current_effect_queue.append(BattleResolutionEntry.create(callback, args, 0, queue_sequence, label, null))
		queue_sequence += 1
		return
	after_current_effect_queue.append(BattleResolutionEntry.create(callback, args, 0, queue_sequence, label, null))
	queue_sequence += 1


func begin_attack_scope() -> void:
	_push_effect_queue_scope()
	attack_after_scopes.append([])


func is_attack_scope_active() -> bool:
	return not attack_after_scopes.is_empty()


func end_attack_scope() -> void:
	if attack_after_scopes.is_empty():
		return
	var callbacks: Array = attack_after_scopes.back() as Array
	_drain_current_effect_queue()
	while not callbacks.is_empty():
		var pending := callbacks.duplicate()
		callbacks.clear()
		for entry in pending:
			_execute_effect_queue_entry(entry as BattleResolutionEntry)
		_drain_current_effect_queue()
	attack_after_scopes.pop_back()
	_pop_effect_queue_scope()
	if attack_after_scopes.is_empty() and not is_draining_actions and not action_queue.is_empty():
		_drain_action_queue()


# A generic resolution fence for effects which must wait for every trigger and
# descendant they emit, without relying on an incidental queue priority.
func begin_descendant_scope() -> void:
	_push_effect_queue_scope()
	descendant_after_scopes.append([])


func end_descendant_scope() -> void:
	if descendant_after_scopes.is_empty():
		return
	var callbacks: Array = descendant_after_scopes.back() as Array
	_drain_current_effect_queue()
	while not callbacks.is_empty():
		var pending := callbacks.duplicate()
		callbacks.clear()
		for entry in pending:
			_execute_effect_queue_entry(entry as BattleResolutionEntry)
		_drain_current_effect_queue()
	descendant_after_scopes.pop_back()
	_pop_effect_queue_scope()


# Bottle damage must settle descendants before payload placement, while trap
# after-attack callbacks remain deferred until the enclosing scope is closed.
func drain_active_attack_effects() -> void:
	if attack_after_scopes.is_empty():
		return
	_drain_current_effect_queue()


func push_action_frame(frame: BattleActionFrame) -> bool:
	if frame == null or not frame.callback.is_valid():
		return false
	# A hand-card choice suspends one specific action frame. Effects already
	# queued by that frame remain resumable, but accepting a fresh action here
	# would let it run after the player's selection and interleave two turns.
	if _has_pending_choice():
		if controller != null:
			controller._emit_log("请先完成当前选择。")
		return false
	if action_queue.size() >= MAX_PENDING_ACTIONS:
		if controller != null:
			controller._emit_log("待结算行动达到 %d 个，新行动未加入队列。" % MAX_PENDING_ACTIONS)
		return false

	action_queue.append(frame)
	if not is_draining_actions and queue_depth <= 0 and not is_attack_scope_active():
		_drain_action_queue()
	return true


func resolve_effect_queue() -> void:
	if queue_depth > 0 or is_attack_scope_active():
		return
	if queue_scopes.is_empty():
		queue_scopes.append([])
	_drain_current_effect_queue()
	_drain_after_current_effect_queue()
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
	resolved_actions_in_pump = 0
	if controller != null:
		controller._begin_action_resolution()
	_continue_action_drain()


func _continue_action_drain() -> void:
	if not is_draining_actions or _has_pending_choice():
		return
	while not action_queue.is_empty():
		if resolved_actions_in_pump >= MAX_ACTIONS_PER_PUMP:
			var cancelled_actions := action_queue.duplicate()
			action_queue.clear()
			if controller != null:
				controller._emit_log("单次结算达到 %d 个行动，剩余行动已取消。" % MAX_ACTIONS_PER_PUMP)
				controller._on_action_frames_cancelled(cancelled_actions)
			break
		resolved_actions_in_pump += 1
		var frame: BattleActionFrame = action_queue.pop_front() as BattleActionFrame
		current_action_id = next_action_id
		next_action_id += 1
		action_active = true
		current_action_effect_count = 0
		effect_limit_reached = false
		if not _resolve_action_frame(frame):
			return
		action_active = false
		current_action_effect_count = 0
		effect_limit_reached = false
		current_action_id = 0
	if _has_pending_choice():
		return
	if controller != null:
		controller._end_action_resolution()
	is_draining_actions = false
	resolved_actions_in_pump = 0
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


func _resolve_action_frame(frame: BattleActionFrame) -> bool:
	current_action_frame = null
	if frame == null or not frame.callback.is_valid():
		return true

	current_action_frame = frame
	current_frame_after_callback_started = false
	current_frame_ap_finalization_started = false
	current_frame_completion_notified = false
	after_current_effect_queue.clear()
	_push_effect_queue_scope()
	enqueue_effect(
		frame.callback,
		frame.args,
		frame.priority,
		frame.label,
		frame.context
	)
	_drain_current_effect_queue()
	if _has_pending_choice():
		return false
	return _finish_current_action_frame(frame)


func _resume_suspended_action() -> void:
	if not is_draining_actions or not action_active or current_action_frame == null:
		return
	_drain_current_effect_queue()
	if _has_pending_choice():
		return
	if not _finish_current_action_frame(current_action_frame):
		return
	action_active = false
	current_action_effect_count = 0
	effect_limit_reached = false
	current_action_id = 0
	_continue_action_drain()


func _finish_current_action_frame(frame: BattleActionFrame) -> bool:
	_drain_after_current_effect_queue()
	if _has_pending_choice():
		return false
	if not current_frame_after_callback_started and frame.after_callback.is_valid():
		current_frame_after_callback_started = true
		frame.after_callback.callv(frame.after_args)
		_drain_current_effect_queue()
		if _has_pending_choice():
			return false
		_drain_after_current_effect_queue()
		if _has_pending_choice():
			return false
	if controller != null and not current_frame_ap_finalization_started:
		current_frame_ap_finalization_started = true
		controller._finalize_ap_action(frame, current_action_id)
		_drain_current_effect_queue()
		if _has_pending_choice():
			return false
		_drain_after_current_effect_queue()
		if _has_pending_choice():
			return false
	if controller != null and not current_frame_completion_notified:
		current_frame_completion_notified = true
		controller._on_action_resolution_completed(current_action_id)
	_pop_effect_queue_scope()
	current_action_frame = null
	current_frame_after_callback_started = false
	current_frame_ap_finalization_started = false
	current_frame_completion_notified = false
	return true


func _drain_after_current_effect_queue() -> void:
	while not after_current_effect_queue.is_empty():
		var entry: BattleResolutionEntry = after_current_effect_queue.pop_front() as BattleResolutionEntry
		_execute_effect_queue_entry(entry)
		if _has_pending_choice():
			return
	_drain_current_effect_queue()
	if _has_pending_choice():
		return


func _drain_current_effect_queue() -> void:
	var queue := _get_current_effect_queue()
	queue_depth += 1
	while not queue.is_empty():
		if _has_pending_choice():
			break
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
