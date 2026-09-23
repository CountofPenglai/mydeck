extends RefCounted
class_name DruidBattleRules

var _controller: BattleController


func setup(controller: BattleController) -> void:
	_controller = controller


func get_rooted_units(origin: BattleUnitState, radius: int = -1) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if _controller == null or origin == null:
		return result
	for candidate_value in _controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate == null or not candidate.is_alive() or not candidate.is_deployed or not candidate.has_status("druid_root"):
			continue
		if radius >= 0 and origin.get_range_distance_to(candidate, {"controller": _controller}) > radius:
			continue
		result.append(candidate)
	return result


func get_automatic_strike(owner: BattleUnitState, target: BattleUnitState = null) -> Dictionary:
	if _controller == null or owner == null or not owner.is_alive() or not owner.is_deployed:
		return {}
	var candidates: Array[BattleUnitState] = []
	if target != null:
		candidates.append(target)
	else:
		for unit_value in _controller.units:
			var candidate := unit_value as BattleUnitState
			if candidate != null and candidate.is_alive() and candidate.is_deployed and candidate.faction != owner.faction:
				candidates.append(candidate)
	candidates.sort_custom(func(left: BattleUnitState, right: BattleUnitState) -> bool:
		var left_distance := owner.get_range_distance_to(left, {"controller": _controller})
		var right_distance := owner.get_range_distance_to(right, {"controller": _controller})
		return left_distance < right_distance or (left_distance == right_distance and left.unit_id < right.unit_id)
	)
	var modes := owner.get_attack_weapon_options()
	for mode_value in modes:
		var equipment_slot := str((mode_value as Dictionary).get("slot", ""))
		for candidate in candidates:
			if _can_strike(owner, candidate, equipment_slot):
				return {"target": candidate, "equipment_slot": equipment_slot}
	return {}


func expire_source_statuses(source: BattleUnitState) -> void:
	if _controller == null or source == null:
		return
	for owner_value in _controller.units:
		var owner := owner_value as BattleUnitState
		if owner == null:
			continue
		for status_value in owner.statuses.duplicate():
			var status := status_value as StatusEffect
			if status == null or not (status is DruidElementChargeStatus or status is DruidAssistStatus or status is DruidRootOathStatus):
				continue
			if int(status.get("source_unit_id")) == source.unit_id and source.turn_serial >= int(status.get("expires_on_source_turn")):
				owner.statuses.erase(status)


func clear_source_statuses(source: BattleUnitState) -> void:
	if _controller == null or source == null:
		return
	for owner_value in _controller.units:
		var owner := owner_value as BattleUnitState
		if owner == null:
			continue
		for status_value in owner.statuses.duplicate():
			var status := status_value as StatusEffect
			if status != null and (status is DruidElementChargeStatus or status is DruidAssistStatus or status is DruidRootOathStatus) and int(status.get("source_unit_id")) == source.unit_id:
				owner.statuses.erase(status)


func notify_strike_finished(attacker: BattleUnitState, target: BattleUnitState, context: Dictionary = {}) -> void:
	if _controller == null or attacker == null or target == null or bool(context.get("druid_assist", false)):
		return
	for owner_value in _controller.units:
		var owner := owner_value as BattleUnitState
		if owner == null or not owner.is_alive():
			continue
		var status := owner.get_status("druid_assist") as DruidAssistStatus
		if status == null or status.last_used_active_turn_serial == _controller.active_turn_serial:
			continue
		if owner == attacker or attacker.faction != owner.faction or not attacker.has_status("druid_root") or owner.get_range_distance_to(attacker, {"controller": _controller}) > 2:
			continue
		_controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_resolve_assist"), [owner, attacker, target, status], "协猎")


func _resolve_assist(owner: BattleUnitState, _attacker: BattleUnitState, target: BattleUnitState, status: DruidAssistStatus) -> void:
	if _controller == null or owner == null or status == null or owner.get_status(status.status_id) != status or status.last_used_active_turn_serial == _controller.active_turn_serial:
		return
	var strike := get_automatic_strike(owner, target)
	if strike.is_empty():
		return
	status.last_used_active_turn_serial = _controller.active_turn_serial
	_controller.perform_unit_strike_with_options_and_after_effects(owner, strike["target"] as BattleUnitState, null, 0, 1.0, "协猎", str(strike["equipment_slot"]), {"druid_assist": true}, Callable())


func _can_strike(owner: BattleUnitState, target: BattleUnitState, equipment_slot: String) -> bool:
	return target != null and target.is_alive() and target.is_deployed and target.faction != owner.faction \
		and owner.can_use_attack_mode(equipment_slot, {"controller": _controller, "target": target}) \
		and owner.get_range_distance_to(target, {"controller": _controller, "equipment_slot": equipment_slot}) <= _controller.get_effective_attack_range_against(owner, target, equipment_slot)
