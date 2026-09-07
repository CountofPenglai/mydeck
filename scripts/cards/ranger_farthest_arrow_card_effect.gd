extends RangerWeaponCardEffect
class_name RangerFarthestArrowCardEffect

const PAIRED_SLOT := "paired"


func get_fixed_equipment_slot(_context: Dictionary = {}) -> String:
	return PAIRED_SLOT


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return false


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	var controller := context.get("controller") as BattleController
	return _has_range_component(user) and user.can_use_attack_mode(PAIRED_SLOT, {"controller": controller})


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	return targets.size() == 1 and _has_range_component(context.get("user") as BattleUnitState)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if targets.size() != 1 or not targets[0] is BattleUnitState:
		return
	var user := context.get("user") as BattleUnitState
	var target := targets[0] as BattleUnitState
	if user == null:
		return
	var distance := user.get_range_distance_to(target, {"controller": context.get("controller"), "equipment_slot": PAIRED_SLOT, "card": context.get("card")})
	_enqueue_weapon_strike(context, target, "尽程一矢", mini(maxi(0, distance - 1), 3), 1.0, {}, effect_priority)


func play_on_object(context: Dictionary = {}, target: BattleObjectState = null) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or target == null:
		return
	var distance := controller.map_data.get_distance(user.cell, target.cell)
	controller.perform_object_strike_with_modifier(user, target, card, mini(maxi(0, distance - 1), 3), "尽程一矢", PAIRED_SLOT)


func _has_range_component(user: BattleUnitState) -> bool:
	if user == null or user.character_state == null:
		return false
	var equipment := user.character_state.get_equipment_for_attack_slot(PAIRED_SLOT, user.get_active_weapon_face_index())
	return equipment != null and equipment.range_type == EquipmentData.WeaponRangeType.RANGED
