extends "res://scripts/cards/self_enchantment_card_effect.gd"
class_name BloodiedBattleCardEffect

@export_range(0, 99, 1) var armored_heal: int = 1
@export_range(0, 99, 1) var unarmored_heal: int = 3
@export_range(1, 99, 1) var trigger_limit: int = 4


func on_zone_owner_after_damage_dealt(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or str(context.get("zone_name", "")) != "enchant":
		return
	if int(context.get("amount", 0)) <= 0:
		return
	var target: BattleUnitState = context.get("target") as BattleUnitState
	if target == null or target.faction == owner.faction:
		return
	var action_id := int(context.get("action_id", 0))
	if action_id <= 0:
		return

	var state := owner.get_card_runtime_state(zone_card)
	if int(state.get("last_trigger_action", -1)) == action_id:
		return
	state["last_trigger_action"] = action_id
	var trigger_count := int(state.get("trigger_count", 0)) + 1
	state["trigger_count"] = trigger_count

	var controller: BattleController = context.get("controller") as BattleController
	if controller == null:
		return
	var heal_amount := unarmored_heal if owner.get_armor_stacks() <= 0 else armored_heal
	controller.heal_unit(owner, owner, heal_amount, "浴血奋战")
	if trigger_count >= trigger_limit and owner.move_enchant_card_to_discard(zone_card, {
		"controller": controller,
		"reason": "bloodied_battle_completed",
		"source_card": zone_card,
	}):
		controller._emit_log("%s 的浴血奋战触发 %d 次后进入弃牌堆。" % [owner.get_display_name(), trigger_count])
