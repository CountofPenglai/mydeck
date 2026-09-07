extends RangerWeaponCardEffect
class_name RangerSurfacePursuitCardEffect

const WEAPON_SLOT := "weapon"


func get_fixed_equipment_slot(_context: Dictionary = {}) -> String:
	return WEAPON_SLOT


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return false


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	var controller := context.get("controller") as BattleController
	return _has_melee_component(user) and user.can_use_attack_mode(WEAPON_SLOT, {"controller": controller})


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	return targets.size() == 1 and _has_melee_component(context.get("user") as BattleUnitState)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if targets.size() != 1 or not targets[0] is BattleUnitState:
		return
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	_enqueue_weapon_strike(context, targets[0] as BattleUnitState, "踏境追刃", 0, 1.0, {"after_strike_effect": Callable(self, "_collect_own_surface").bind(controller, user)}, effect_priority)


func play_on_object(context: Dictionary = {}, target: BattleObjectState = null) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or target == null:
		return
	controller.perform_object_strike_with_modifier(user, target, card, 0, "踏境追刃", WEAPON_SLOT)
	controller.enqueue_effect(
		Callable(self, "_collect_own_surface"),
		[controller, user],
		effect_priority,
		"踏境追刃：采集自身",
		context
	)


func _collect_own_surface(controller: BattleController, user: BattleUnitState) -> void:
	if controller != null and user != null:
		controller.collect_surface_elements(user, user.cell, "踏境追刃")


func _has_melee_component(user: BattleUnitState) -> bool:
	if user == null or user.character_state == null:
		return false
	var equipment := user.character_state.get_equipment_for_attack_slot(WEAPON_SLOT, user.get_active_weapon_face_index())
	return equipment != null and equipment.range_type == EquipmentData.WeaponRangeType.MELEE
