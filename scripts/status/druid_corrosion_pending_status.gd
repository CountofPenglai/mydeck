extends StatusEffect
class_name DruidCorrosionPendingStatus

var pending_card: CardData
var expires_on_turn_serial: int = -1


func _init() -> void:
	status_id = "druid_corrosion_pending:%d" % get_instance_id()
	display_name = "蛊蚀待发"


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or unit.turn_serial < expires_on_turn_serial:
		return
	var index := unit.hand.find(pending_card)
	if index >= 0:
		var controller := context.get("controller") as BattleController
		if controller != null:
			unit.move_card_to_exile(pending_card)
			controller.lose_life(null, unit, 1, "蛊蚀咒害", {"curse_harm": true})
			unit.gain_curse_wave(1, {"controller": controller, "reason": "corrosion_harm"})
			controller._emit_log("%s 的蛊蚀咒害被放逐，并令其失去1点生命、获得1咒波。" % unit.get_display_name())
	stacks = 0
