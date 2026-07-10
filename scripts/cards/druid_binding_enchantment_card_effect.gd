extends CardEffect
class_name DruidBindingEnchantmentCardEffect

@export_range(0, 99, 1) var hand_armor_multiplier: int = 1
@export_range(0, 9, 1) var draw_count: int = 2
@export_range(0, 9, 1) var mana_cost: int = 1


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.is_empty():
		return
	if not (targets[0] is BattleUnitState):
		return

	var target_unit: BattleUnitState = targets[0] as BattleUnitState
	var hand_index := user.hand.find(card)
	if hand_index >= 0:
		user.hand.remove_at(hand_index)
		target_unit.add_card_to_enchant_zone(card, context)
		controller._emit_log("%s 将 %s 置入 %s 的附魔区。" % [user.get_display_name(), card.card_name, target_unit.get_display_name()])


func on_zone_owner_card_ap_cost_paid(owner: BattleUnitState, zone_card: CardData, played_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or played_card == null:
		return
	if str(context.get("zone_name", "")) != "mana":
		return
	if mana_cost > 0 and not owner.pay_mana(mana_cost):
		return

	var controller: BattleController = context.get("controller") as BattleController
	if controller == null:
		return

	var drawn := owner.draw_cards(draw_count, controller.rng, context)
	controller._emit_log("%s 的 %s 触发，支付 %d 法力抽取 %d 张牌。" % [owner.get_display_name(), zone_card.card_name, mana_cost, drawn])


func on_zone_owner_after_strike(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null:
		return
	if str(context.get("zone_name", "")) != "enchant":
		return

	var armor_amount := owner.hand.size() * hand_armor_multiplier
	if armor_amount <= 0:
		return

	var armor := ArmorStatus.new()
	armor.stacks = armor_amount
	owner.add_status(armor)
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 的 %s 触发，获得 %d 点护甲。" % [owner.get_display_name(), zone_card.card_name, armor_amount])

