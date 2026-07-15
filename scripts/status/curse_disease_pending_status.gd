extends StatusEffect
class_name CurseDiseasePendingStatus

var pending_card: CardData
var expires_turn_serial: int = -1


func _init() -> void:
	status_id = "curse_disease_pending:%d" % get_instance_id()
	display_name = "病症待发"


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or unit.turn_serial < expires_turn_serial:
		return
	if unit.hand.has(pending_card):
		unit.move_card_to_exile(pending_card)
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.lose_life(null, unit, 2, "病症咒害", {"curse_harm": true})
			unit.gain_curse_wave(1, {"controller": controller, "reason": "disease_harm"})
	stacks = 0
