extends CardEffect
class_name DruidCorrosionCurseEffect


func can_play(_context: Dictionary = {}) -> bool:
	return false


func on_self_drawn(owner: BattleUnitState, card: CardData, context: Dictionary = {}) -> void:
	if owner == null or card == null:
		return
	var pending := DruidCorrosionPendingStatus.new()
	pending.pending_card = card
	pending.expires_on_turn_serial = owner.turn_serial
	owner.add_status(pending)
	var controller := context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 抽到了蛊蚀咒害，本回合结束时若仍持有将受到反噬。" % owner.get_display_name())
