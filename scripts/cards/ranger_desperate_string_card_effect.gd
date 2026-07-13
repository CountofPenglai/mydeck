extends CardEffect
class_name RangerDesperateStringCardEffect

@export_range(0, 9, 1) var draw_count: int = 3


func _init() -> void:
	uses_strike = true


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and _uses_ranger_weapon(user, str(context.get("equipment_slot", "")), context)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null:
		return

	controller.perform_strike(user, target, card, "绝处续弦", str(context.get("equipment_slot", "")))
	var drawn := user.draw_cards(draw_count, controller.rng, context)
	if user.hand.size() > 1:
		user.ranger_state.pending_hand_discard_count += 1
	controller._emit_log("%s 抽取 %d 张牌，结算完成后选择弃置 1 张。" % [user.get_display_name(), drawn])


func _uses_ranger_weapon(user: BattleUnitState, equipment_slot: String, context: Dictionary) -> bool:
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot, context)
	return profile.primary_equipment != null and (
		profile.primary_equipment.has_tag("匕首") or profile.primary_equipment.has_tag("弩")
	)
