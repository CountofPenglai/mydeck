extends StatusEffect
class_name RangerEnchantWatcherStatus

enum TriggerKind {
	WAIT_FOR_MOVEMENT,
	LOCKDOWN_ON_CARD,
}

var trigger_kind: int = TriggerKind.WAIT_FOR_MOVEMENT
var equipment_slot: String = ""
var _controller: BattleController
var _owner: BattleUnitState
var _zone_card: CardData
var _enemy_cells: Dictionary = {}
var _enemy_hand_ids: Dictionary = {}
var _tracked_in_flight: Dictionary = {}
var _scheduled: bool = false
var _triggered: bool = false


func configure(
		controller: BattleController,
		owner: BattleUnitState,
		zone_card: CardData,
		kind: int,
		selected_equipment_slot: String
	) -> void:
	_controller = controller
	_owner = owner
	_zone_card = zone_card
	trigger_kind = kind
	equipment_slot = selected_equipment_slot
	status_id = "ranger_enchant_watcher_%d" % zone_card.get_instance_id()
	display_name = zone_card.card_name
	_snapshot_enemies()


func on_turn_start(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit == _owner and not _triggered:
		_queue_cleanup("期限届满")


func on_enemy_movement_completed(owner: BattleUnitState, enemy: BattleUnitState, _context: Dictionary = {}) -> void:
	if owner == _owner and trigger_kind == TriggerKind.WAIT_FOR_MOVEMENT and _is_target_in_selected_range(enemy):
		_queue_trigger(enemy)


func on_enemy_card_completed(owner: BattleUnitState, enemy: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	if owner == _owner and trigger_kind == TriggerKind.LOCKDOWN_ON_CARD and _is_target_in_selected_range(enemy):
		_queue_trigger(enemy)


func on_ranger_stealth_ended(owner: BattleUnitState, _context: Dictionary = {}) -> void:
	if owner == _owner and not _triggered and not _scheduled:
		_queue_cleanup("潜行提前结束")


func _on_controller_state_changed() -> void:
	if _scheduled or _triggered:
		return
	if _controller == null or _owner == null or _zone_card == null:
		_disconnect()
		stacks = 0
		return
	if not _owner.has_card_in_enchant(_zone_card):
		_disconnect()
		stacks = 0
		return
	if not _owner.is_alive() or not _owner.is_stealthed():
		_queue_cleanup("潜行提前结束")
		return

	match trigger_kind:
		TriggerKind.WAIT_FOR_MOVEMENT:
			_detect_enemy_movement()
		TriggerKind.LOCKDOWN_ON_CARD:
			_detect_enemy_card_completion()
		_:
			pass


func _detect_enemy_movement() -> void:
	for enemy: BattleUnitState in _controller.get_opposing_units(_owner):
		var previous: Vector2i = _enemy_cells.get(enemy.unit_id, enemy.cell) as Vector2i
		_enemy_cells[enemy.unit_id] = enemy.cell
		if previous == enemy.cell:
			continue
		if _is_target_in_selected_range(enemy):
			_queue_trigger(enemy)
			return


func _detect_enemy_card_completion() -> void:
	for enemy: BattleUnitState in _controller.get_opposing_units(_owner):
		var previous: Array = _enemy_hand_ids.get(enemy.unit_id, []) as Array
		var current := _card_ids(enemy.hand)
		for card: CardData in enemy.hand:
			if card != null and _controller.cards_in_flight.has(card.get_instance_id()):
				_tracked_in_flight[card.get_instance_id()] = enemy

		var completed := false
		for card_id: int in previous:
			if current.has(card_id):
				continue
			if _tracked_in_flight.has(card_id) or (
					_controller.current_unit == enemy and _controller.get_current_action_id() > 0
			):
				completed = true
				break
		for card_id: int in _tracked_in_flight.keys().duplicate():
			if _tracked_in_flight[card_id] == enemy and not _controller.cards_in_flight.has(card_id):
				completed = true
				_tracked_in_flight.erase(card_id)
		_enemy_hand_ids[enemy.unit_id] = current
		if completed and _is_target_in_selected_range(enemy):
			_queue_trigger(enemy)
			return


func _queue_trigger(triggering_enemy: BattleUnitState) -> void:
	if _scheduled or triggering_enemy == null:
		return
	_scheduled = true
	_controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_trigger"),
		[triggering_enemy],
		0,
		"%s 自动伏击" % _zone_card.card_name,
		{
			"owner": _owner,
			"source_card": _zone_card,
			"trigger": triggering_enemy,
			"equipment_slot": equipment_slot,
		}
	))


func _resolve_trigger(triggering_enemy: BattleUnitState) -> void:
	_scheduled = false
	if _controller == null or _owner == null or _zone_card == null:
		return
	if not _owner.has_card_in_enchant(_zone_card) or not _owner.is_stealthed():
		_resolve_cleanup("触发时已失效")
		return
	if not _is_target_in_selected_range(triggering_enemy):
		_resolve_cleanup("触发目标失效")
		return

	_triggered = true
	_disconnect()
	var targets := _get_ambush_targets(triggering_enemy)
	var ambush_multiplier := _controller.consume_ranger_stealth_for_attack(_owner)
	for target: BattleUnitState in targets:
		_controller.enqueue_effect(
			Callable(_controller, "perform_strike_with_options"),
			[
				_owner,
				target,
				_zone_card,
				0,
				1.0,
				_zone_card.card_name,
				equipment_slot,
				{
					"skip_ranger_ambush": true,
					"ranger_attack_multiplier": ambush_multiplier,
				},
			],
			0,
			"%s：伏击 %s" % [_zone_card.card_name, target.get_display_name()]
		)
	_controller.enqueue_effect(
		Callable(self, "_resolve_cleanup"),
		["已触发"],
		-100,
		"%s：触发后弃置" % _zone_card.card_name
	)


func _get_ambush_targets(triggering_enemy: BattleUnitState) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if trigger_kind == TriggerKind.WAIT_FOR_MOVEMENT:
		result.append(triggering_enemy)
		return result
	var is_dagger := _selected_mode_has_tag("匕首")
	for enemy: BattleUnitState in _controller.get_opposing_units(_owner):
		if is_dagger:
			if _owner.cell_distance_to(enemy) <= 1:
				result.append(enemy)
		elif triggering_enemy.cell_distance_to(enemy) <= 1 and _is_target_in_selected_range(enemy):
			result.append(enemy)
	result.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		return a.unit_id < b.unit_id
	)
	return result


func _is_target_in_selected_range(target: BattleUnitState) -> bool:
	if target == null or not target.is_alive() or target.faction == _owner.faction:
		return false
	return _owner.cell_distance_to(target) <= _owner.get_attack_range(equipment_slot)


func _selected_mode_has_tag(tag: String) -> bool:
	if _owner == null:
		return false
	var profile: StrikeProfile = _owner.build_strike_profile_object(equipment_slot)
	return profile.primary_equipment != null and profile.primary_equipment.has_tag(tag)


func _queue_cleanup(reason: String) -> void:
	if _scheduled:
		return
	_scheduled = true
	_controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_cleanup"),
		[reason],
		-100,
		"%s 失效" % _zone_card.card_name,
		{"owner": _owner, "source_card": _zone_card, "reason": reason}
	))


func _resolve_cleanup(reason: String) -> void:
	_scheduled = false
	_disconnect()
	stacks = 0
	if _owner == null or _zone_card == null:
		return
	if _owner.move_enchant_card_to_discard(_zone_card, {
		"controller": _controller,
		"reason": "ranger_enchant_finished",
		"source_card": _zone_card,
	}):
		if _controller != null:
			_controller._emit_log("%s 因%s进入弃牌堆。" % [_zone_card.card_name, reason])


func _snapshot_enemies() -> void:
	_enemy_cells.clear()
	_enemy_hand_ids.clear()
	if _controller == null or _owner == null:
		return
	for enemy: BattleUnitState in _controller.get_opposing_units(_owner):
		_enemy_cells[enemy.unit_id] = enemy.cell
		_enemy_hand_ids[enemy.unit_id] = _card_ids(enemy.hand)


func _card_ids(cards: Array[CardData]) -> Array[int]:
	var result: Array[int] = []
	for card: CardData in cards:
		if card != null:
			result.append(card.get_instance_id())
	return result


func _disconnect() -> void:
	var callback := Callable(self, "_on_controller_state_changed")
	if _controller != null and _controller.state_changed.is_connected(callback):
		_controller.state_changed.disconnect(callback)
