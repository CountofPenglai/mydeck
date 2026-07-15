extends CardEffect
class_name CurseDiseaseCardEffect


func can_play(_context: Dictionary = {}) -> bool:
	return false


func on_self_drawn(owner: BattleUnitState, card: CardData, context: Dictionary = {}) -> void:
	if owner == null or card == null:
		return
	var pending := CurseDiseasePendingStatus.new()
	pending.pending_card = card
	pending.expires_turn_serial = owner.turn_serial
	owner.add_status(pending)
	var controller := context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 抽到了病症咒害。" % owner.get_display_name())
