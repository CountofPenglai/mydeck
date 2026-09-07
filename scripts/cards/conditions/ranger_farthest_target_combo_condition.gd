extends CardPlayCondition
class_name RangerFarthestTargetComboCondition


func _init() -> void:
	condition_name = "目标位于远程配件的实际最远射程"


func can_pay(context: Dictionary = {}) -> bool:
	var controller := _get_controller(context)
	var user := _get_user(context)
	var targets := context.get("targets", []) as Array
	if controller == null or user == null:
		return false
	if targets.size() != 1:
		return _has_targetless_legal_candidate(controller, user, context) if bool(context.get("targetless_condition_search", false)) else false
	var target: Variant = targets[0]
	var equipment_slot := str(context.get("equipment_slot", "paired"))
	if target is BattleUnitState:
		return user.get_range_distance_to(target, {"controller": controller, "equipment_slot": equipment_slot, "card": context.get("card")}) == controller.get_effective_attack_range_against(user, target, equipment_slot)
	if target is BattleObjectState:
		return controller.map_data.get_distance(user.cell, target.cell) == controller.get_effective_attack_range_at_cell(user, target.cell, equipment_slot)
	return false


func _has_targetless_legal_candidate(controller: BattleController, user: BattleUnitState, context: Dictionary) -> bool:
	var card := context.get("card") as CardData
	var equipment_slot := str(context.get("equipment_slot", "paired"))
	if card == null:
		return false
	var candidates: Array = controller.get_hostile_target_candidates(user)
	# Card targeting permits ordinary damageable battlefield objects, whereas the
	# hostile-target helper intentionally only exposes opponent units and traps.
	for battle_object in controller.battle_objects:
		if battle_object != null and battle_object.is_targetable() and not candidates.has(battle_object):
			candidates.append(battle_object)
	for candidate in candidates:
		if not controller._targets_are_valid(user, card, [candidate], false, equipment_slot, CardEnums.CardPlayMode.COMBO):
			continue
		var candidate_context := context.duplicate()
		candidate_context["targets"] = [candidate]
		if can_pay(candidate_context):
			return true
	return false


func get_description() -> String:
	return "目标与你的距离等于远程配件对该目标的实际射程"
