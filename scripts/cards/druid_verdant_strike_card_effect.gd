extends CardEffect
class_name DruidVerdantStrikeCardEffect

@export_range(0, 99, 1) var armor_per_hand_card: int = 1
@export_range(0, 99, 1) var inverted_armor_per_mana: int = 1


func _init() -> void:
	uses_strike = true


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.get_active_weapon_equipment() != null


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	var orientation := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	var equipment_slot := str(context.get("equipment_slot", ""))
	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue
		var target_unit: BattleUnitState = target as BattleUnitState
		controller.perform_strike(user, target_unit, card, card.get_display_name_for_context(context), equipment_slot)

	var armor_amount := user.hand.size() * armor_per_hand_card
	if orientation == CardEnums.DruidOrientation.INVERTED:
		armor_amount = user.get_available_mana() * inverted_armor_per_mana
	if armor_amount <= 0:
		return

	var armor := ArmorStatus.new()
	armor.stacks = armor_amount
	user.add_status(armor)
	controller._emit_log("%s 获得 %d 点护甲。" % [user.get_display_name(), armor_amount])
