extends RangerCardEffectBase
class_name RangerWeaponCardEffect

const NEXT_DAGGER_STATUS_ID := "ranger_next_dagger_multiplier"


func _init() -> void:
	uses_strike = true


func _enqueue_weapon_strike(
		context: Dictionary,
		target: BattleUnitState,
		label: String,
		damage_modifier: int = 0,
		damage_multiplier: float = 1.0,
		options: Dictionary = {},
		priority: int = 0
	) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or target == null:
		return
	controller.enqueue_effect(
		Callable(self, "_resolve_weapon_strike"),
		[
			controller,
			user,
			target,
			card,
			str(context.get("equipment_slot", "")),
			label,
			damage_modifier,
			damage_multiplier,
			options.duplicate(),
		],
		priority,
		"%s：武器打击" % label,
		context
	)


func _resolve_weapon_strike(
		controller: BattleController,
		user: BattleUnitState,
		target: BattleUnitState,
		card: CardData,
		equipment_slot: String,
		label: String,
		damage_modifier: int,
		damage_multiplier: float,
		options: Dictionary
	) -> void:
	if controller == null or user == null or target == null or not user.is_alive() or not target.is_alive():
		return
	var resolved_options := options.duplicate()
	var after_effect: Callable = resolved_options.get("after_strike_effect", Callable()) as Callable
	resolved_options.erase("after_strike_effect")
	if _is_dagger_slot(user, equipment_slot):
		var status: StatusEffect = user.get_status(NEXT_DAGGER_STATUS_ID)
		if status != null and status.stacks > 0:
			var status_multiplier := float(status.get("damage_multiplier"))
			resolved_options["ranger_attack_multiplier"] = maxf(
				float(resolved_options.get("ranger_attack_multiplier", 1.0)),
				status_multiplier
			)
			status.stacks = 0
			user.remove_expired_statuses()
	controller.perform_unit_strike_with_options_and_after_effects(
		user,
		target,
		card,
		damage_modifier,
		damage_multiplier,
		label,
		equipment_slot,
		resolved_options,
		after_effect
	)


func _is_dagger_slot(user: BattleUnitState, equipment_slot: String) -> bool:
	if user == null:
		return false
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot)
	return profile.primary_equipment != null and profile.primary_range_type == EquipmentData.WeaponRangeType.MELEE


func _is_crossbow_slot(user: BattleUnitState, equipment_slot: String) -> bool:
	if user == null:
		return false
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot)
	return profile.primary_equipment != null and profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED
