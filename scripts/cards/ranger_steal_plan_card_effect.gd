extends CardEffect
class_name RangerStealPlanCardEffect

@export_range(-9, 0, 1) var copied_card_ap_delta: int = -1
@export_range(0, 9, 1) var crossbow_draw_count: int = 1


func _init() -> void:
	uses_strike = true


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and not _get_weapon_mode(user, str(context.get("equipment_slot", "")), context).is_empty()


func get_copyable_enemy_cards(context: Dictionary = {}, target: BattleUnitState = null) -> Array[CardData]:
	var result: Array[CardData] = []
	if target == null:
		return result
	for enemy_card in target.hand:
		if _can_copy_card(context, target, enemy_card):
			result.append(enemy_card)
	return result


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null:
		return

	var equipment_slot := str(context.get("equipment_slot", ""))
	var mode := _get_weapon_mode(user, equipment_slot, context)
	controller.perform_strike(user, target, card, "窃取预案", equipment_slot)
	if target.hand.is_empty():
		return
	var selected := _selected_enemy_card(context, target, mode == "dagger")
	if selected == null:
		return

	if mode == "dagger":
		var copied := selected.duplicate(true) as CardData
		if copied == null:
			return
		user.hand.append(copied)
		user.mark_temporary_card(copied, copied_card_ap_delta, true, true)
		controller._emit_log("%s 复制 %s：本回合费用 -%d，打出后或回合结束时放逐。" % [
			user.get_display_name(),
			selected.card_name,
			absi(copied_card_ap_delta),
		])
	elif target.discard_card(selected, context):
		var drawn := user.draw_cards(crossbow_draw_count, controller.rng, context)
		controller._emit_log("%s 弃置 %s 的 %s，并抽取 %d 张牌。" % [
			user.get_display_name(),
			target.get_display_name(),
			selected.card_name,
			drawn,
		])


func _selected_enemy_card(context: Dictionary, target: BattleUnitState, require_copyable: bool) -> CardData:
	var selected: CardData = context.get("selected_enemy_card") as CardData
	if selected != null and target.has_card_in_hand(selected):
		if not require_copyable or _can_copy_card(context, target, selected):
			return selected
	for enemy_card in target.hand:
		if enemy_card != null and (not require_copyable or _can_copy_card(context, target, enemy_card)):
			return enemy_card
	return null


func _can_copy_card(context: Dictionary, target: BattleUnitState, enemy_card: CardData) -> bool:
	if enemy_card == null:
		return false
	var blocked_value: Variant = context.get("uncopyable_enemy_cards", [])
	if blocked_value is Array and (blocked_value as Array).has(enemy_card):
		return false
	var runtime_state := target.get_card_runtime_state(enemy_card, false)
	return not bool(runtime_state.get("enemy_only", false))


func _get_weapon_mode(user: BattleUnitState, equipment_slot: String, context: Dictionary) -> String:
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot, context)
	if profile.primary_equipment == null:
		return ""
	if profile.primary_equipment.has_tag("匕首"):
		return "dagger"
	if profile.primary_equipment.has_tag("弩"):
		return "crossbow"
	return ""
