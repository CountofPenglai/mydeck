extends CardEffect
class_name DruidVerdantStrikeCardEffect

@export_range(0, 99, 1) var inverted_armor: int = 2


func _init() -> void:
	uses_strike = true


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and (not _is_inverted(context) or user.get_active_weapon_equipment() != null)


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return _is_inverted(context)


func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	if not _is_inverted(context):
		user.gain_mana(1, context)
		controller.request_druid_form_change(user, true, context.merged({"source_card": card}))
		return
	if targets.is_empty() or not (targets[0] is BattleUnitState):
		return
	controller.perform_unit_strike_with_after_effects(
		user, targets[0] as BattleUnitState, card, "兽形猛击", str(context.get("equipment_slot", "")),
		Callable(self, "_finish_strike").bind(context)
	)


func _finish_strike(context: Dictionary) -> void:
	var user := context.get("user") as BattleUnitState
	var controller := context.get("controller") as BattleController
	user.gain_armor(inverted_armor, context)
	controller.mark_played_card_to_mana(context)
