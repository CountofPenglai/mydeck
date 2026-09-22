extends CardEffect
class_name DruidElementInvocationCardEffect


const CHARGE_STATUS := preload("res://scripts/status/druid_element_charge_status.gd")


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return true


func requires_preplay_configuration(_context: Dictionary = {}) -> bool:
	return true


func get_preplay_configuration(context: Dictionary = {}) -> Dictionary:
	if _is_inverted(context):
		return {"title": "赋灵：选择基础元素", "options": [], "minimum": 0, "maximum": 0, "resonance_cost": 0, "requires_element": true}
	return {
		"title": "引灵：选择元素、效果与共鸣",
		"options": ["铺设地表", "武器打击"],
		"minimum": 1,
		"maximum": 2,
		"resonance_cost": 1,
		"requires_element": true,
	}


func requires_preplay_cell(context: Dictionary = {}) -> bool:
	return not _is_inverted(context) and _choice_indices(context).has(0)


func get_target_type_for_mode(context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	if not _is_inverted(context) and _choice_indices(context) == [0]:
		return CardEnums.TargetType.AREA
	return default_target_type


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	return user != null and target != null and target.faction != user.faction


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var element := int(context.get("selected_element", BattleSurfaceState.Element.NONE))
	if not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return false
	if _is_inverted(context):
		return true
	var choices := _choice_indices(context)
	if choices.is_empty() or choices.size() > 2:
		return false
	for choice in choices:
		if choice < 0 or choice > 1:
			return false
	if choices.size() > 1 and not bool(context.get("pay_resonance", false)):
		return false
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	return user != null and card != null and (not bool(context.get("pay_resonance", false)) or user.can_pay_mana(user.get_card_resonance_cost(card, context)))


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	if _is_inverted(context):
		return targets.size() == 1 and targets[0] is BattleUnitState
	var choices := _choice_indices(context)
	var needs_strike := choices.has(1)
	var needs_surface := choices.has(0)
	if needs_strike != (targets.size() == 1 and targets[0] is BattleUnitState):
		return false
	if needs_surface:
		var cell := context.get("selected_cell", BattleHexGrid.INVALID_CELL) as Vector2i
		var controller := context.get("controller") as BattleController
		var user := context.get("user") as BattleUnitState
		return controller != null and user != null and controller.map_data.is_valid_cell(cell) and controller.map_data.get_distance(user.cell, cell) <= 3
	return true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	var element := int(context.get("selected_element", BattleSurfaceState.Element.NONE))
	if _is_inverted(context):
		for beneficiary in controller.druid_battle_rules.get_rooted_units(user):
			if beneficiary.faction == user.faction:
				_grant_charge(beneficiary, user, element)
		_grant_charge(user, user, element)
		if targets.size() == 1 and targets[0] is BattleUnitState:
			controller.perform_unit_strike_with_after_effects(user, targets[0] as BattleUnitState, card, "赋灵", str(context.get("equipment_slot", "")), Callable())
		return
	var choices := _choice_indices(context)
	if choices.has(0):
		controller.apply_base_surface_element(context.get("selected_cell") as Vector2i, element, {"source": user, "source_cell": user.cell})
	if choices.has(1) and targets.size() == 1 and targets[0] is BattleUnitState:
		controller.perform_unit_strike_with_options_and_after_effects(
			user, targets[0] as BattleUnitState, card, 0, 1.0, "引灵", str(context.get("equipment_slot", "")), {"druid_element": element}, Callable()
		)


func _grant_charge(beneficiary: BattleUnitState, source: BattleUnitState, element: int) -> void:
	if beneficiary == null or source == null:
		return
	var charge := CHARGE_STATUS.new()
	charge.source_unit_id = source.unit_id
	charge.expires_on_source_turn = source.turn_serial + 1
	charge.element = element
	beneficiary.remove_status(charge.status_id)
	beneficiary.add_status(charge)


func _choice_indices(context: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for raw in context.get("choice_indices", []):
		var choice := int(raw)
		if result.has(choice):
			return []
		result.append(choice)
	result.sort()
	return result


func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
