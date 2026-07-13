extends RangerWeaponCardEffect
class_name RangerFinalHuntDeclarationCardEffect


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger() and user.is_stealthed()


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var target: BattleUnitState = targets[0] as BattleUnitState if targets.size() == 1 else null
	if controller == null or user == null or card == null or target == null:
		return
	var equipment_slot := str(context.get("equipment_slot", ""))
	var is_dagger := _is_dagger_slot(user, equipment_slot)
	var is_crossbow := _is_crossbow_slot(user, equipment_slot)
	if not is_dagger and not is_crossbow:
		return
	controller.enqueue_effect(
		Callable(self, "_resolve_final_hunt"),
		[controller, user, target, card, equipment_slot, is_dagger],
		effect_priority,
		"终猎宣告",
		context
	)


func _resolve_final_hunt(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, equipment_slot: String, is_dagger: bool) -> void:
	if user == null or target == null or not user.is_alive() or not target.is_alive():
		return
	var copied_blend := BattleSurfaceState.Element.NONE
	if not is_dagger and user.ranger_state.prepared_weapon_slot == equipment_slot:
		copied_blend = user.ranger_state.prepared_blend
	var multiplier := 3.0 if is_dagger else 2.0
	controller.perform_strike_with_options(
		user,
		target,
		card,
		0,
		1.0,
		"终猎宣告",
		equipment_slot,
		{"ranger_ambush_override": multiplier}
	)
	if is_dagger and target.is_alive():
		user.ranger_state.active_weapon_lock_slot = equipment_slot
		user.ranger_state.weapon_lock_expires_turn_serial = user.turn_serial + 1
	elif copied_blend != BattleSurfaceState.Element.NONE:
		user.ranger_state.prepared_blend = copied_blend
		user.ranger_state.prepared_weapon_slot = equipment_slot
