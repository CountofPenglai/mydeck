extends CardEffect
class_name DruidForcedDrainCardEffect


func can_play(_context: Dictionary = {}) -> bool:
	return false


func on_zone_owner_card_drawn(owner: BattleUnitState, zone_card: CardData, _drawn_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null:
		return
	if str(context.get("zone_name", "")) != "mana":
		return

	var controller: BattleController = context.get("controller") as BattleController
	if owner.can_pay_mana_excluding_card(1, zone_card):
		owner.pay_mana_excluding_card(1, zone_card)
		if controller != null:
			controller._emit_log("%s 支付 1 点法力，压制 %s 的汲取。" % [owner.get_display_name(), zone_card.card_name])
		return

	if controller == null:
		return

	var loss := owner.hand.size()
	if loss > 0:
		controller.apply_damage(owner, owner, loss, "强制汲取")
