extends "res://scripts/cards/self_enchantment_card_effect.gd"
class_name ArmedAndArmoredCardEffect

@export_range(0, 99, 1) var armor_gain: int = 3


func on_zone_owner_equipment_switched(owner: BattleUnitState, zone_card: CardData, switch_result: Dictionary, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or str(context.get("zone_name", "")) != "enchant":
		return
	if not bool(switch_result.get("success", false)) or str(switch_result.get("slot", "")) != "weapon":
		return

	var state := owner.get_card_runtime_state(zone_card)
	if int(state.get("last_switch_turn", -1)) == owner.turn_serial:
		return
	state["last_switch_turn"] = owner.turn_serial
	owner.gain_armor(armor_gain, context)
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 的披坚执锐触发，获得 %d 护甲。" % [owner.get_display_name(), armor_gain])


func can_activate_from_enchant(context: Dictionary = {}) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return controller != null and user != null and card != null and user.has_card_in_enchant(card) and controller.can_switch_prepared_weapon(user)


func get_enchant_action_label(_context: Dictionary = {}) -> String:
	return "0 AP：先弃置本牌，再切换一次武器"


func activate_from_enchant(context: Dictionary = {}) -> void:
	if not can_activate_from_enchant(context):
		return
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if not user.move_enchant_card_to_discard(card, {
		"controller": controller,
		"reason": "armed_and_armored_active",
		"source_card": card,
	}):
		return
	controller._emit_log("%s 主动弃置披坚执锐。" % user.get_display_name())
	controller.switch_prepared_weapon(user)
