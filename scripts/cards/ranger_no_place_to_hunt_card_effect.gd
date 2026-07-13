extends RangerWeaponCardEffect
class_name RangerNoPlaceToHuntCardEffect


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var target: BattleUnitState = targets[0] as BattleUnitState if targets.size() == 1 else null
	if target != null:
		_enqueue_weapon_strike(context, target, "无处不猎", 0, 1.0, {}, effect_priority)
