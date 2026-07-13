extends RangerWeaponCardEffect
class_name RangerPerilousAssaultCardEffect


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	_enqueue_weapon_strike(context, targets[0] as BattleUnitState, "险步突袭", 0, 1.0, {}, effect_priority)
	_enqueue_combo_completion(context)
