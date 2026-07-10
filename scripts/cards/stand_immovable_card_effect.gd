extends "res://scripts/cards/self_enchantment_card_effect.gd"
class_name StandImmovableCardEffect

@export_range(0, 99, 1) var initial_armor: int = 4
@export_range(0, 99, 1) var damage_reduction: int = 2


func play(context: Dictionary = {}, targets: Array = []) -> void:
	super.play(context, targets)
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or not user.has_card_in_enchant(card):
		return
	user.gain_armor(initial_armor, context)
	controller._emit_log("%s 的铁壁不移提供 %d 护甲。" % [user.get_display_name(), initial_armor])


func get_zone_owner_damage_reduction(owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> int:
	if owner == null or str(context.get("zone_name", "")) != "enchant":
		return 0
	return damage_reduction if owner.get_armor_stacks() > 0 else 0


func on_zone_owner_armor_changed(owner: BattleUnitState, zone_card: CardData, _previous: int, current: int, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or current > 0 or str(context.get("zone_name", "")) != "enchant":
		return
	var controller: BattleController = context.get("controller") as BattleController
	if owner.move_enchant_card_to_discard(zone_card, {
		"controller": controller,
		"reason": "stand_immovable_armor_depleted",
		"source_card": zone_card,
	}) and controller != null:
		controller._emit_log("%s 的护甲归零，铁壁不移进入弃牌堆。" % owner.get_display_name())
