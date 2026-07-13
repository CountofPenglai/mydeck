extends CardEffect
class_name RangerDualPhaseHuntCardEffect


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	var existing := user.get_status("ranger_dual_phase_hunt") as RangerDualPhaseHuntStatus
	if existing != null:
		existing.force_cleanup(user, context)
		user.remove_status(existing.status_id)
	if not user.move_hand_card_to_enchant(card, context):
		return

	var status := RangerDualPhaseHuntStatus.new()
	status.configure(controller, user, card)
	status.expires_turn_serial = user.turn_serial + 1
	user.add_status(status)
	controller.enter_ranger_stealth(user, "双相猎影")
	controller._emit_log("%s 获得一次进攻续接和一次防御续接。" % user.get_display_name())
