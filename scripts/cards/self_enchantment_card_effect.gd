extends CardEffect
class_name SelfEnchantmentCardEffect


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if not user.move_hand_card_to_enchant(card, context):
		return
	controller._emit_log("%s 将 %s 置入自己的附魔区。" % [user.get_display_name(), card.card_name])
