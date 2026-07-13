extends CardEffect
class_name GatherMomentumWhirlwindCardEffect

@export_range(0, 99, 1) var momentum_gain: int = 3
@export_range(0, 12, 1) var attack_range_bonus: int = 1
@export_range(0, 99, 1) var damage_per_momentum: int = 2


func get_target_type_for_mode(_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		return CardEnums.TargetType.ALL

	return default_target_type


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], write_log: bool = true) -> bool:
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	if play_mode != CardEnums.CardPlayMode.MOMENTUM:
		return true

	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return false

	var targets: Array[BattleUnitState] = controller.get_units_in_attack_range(
		user,
		attack_range_bonus,
		BattleController.UnitFilter.OPPONENTS,
		str(context.get("equipment_slot", ""))
	)
	if targets.is_empty():
		if write_log:
			controller._emit_log("%s 攻击范围 + %.0f 内没有敌人。" % [user.get_display_name(), attack_range_bonus])
		return false

	return true


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null:
		return

	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		_play_whirlwind(context, controller, user, card)
		return

	controller.enqueue_effect(
		Callable(controller, "gain_class_resource"),
		[user, BattleController.WARRIOR_MOMENTUM_RESOURCE, momentum_gain],
		effect_priority,
		"蓄势：获得势",
		context
	)


func _play_whirlwind(context: Dictionary, controller: BattleController, user: BattleUnitState, card: CardData) -> void:
	var equipment_slot := str(context.get("equipment_slot", ""))
	var momentum_stacks := user.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	var damage_modifier := momentum_stacks * damage_per_momentum
	var targets: Array[BattleUnitState] = controller.get_units_in_attack_range(
		user,
		attack_range_bonus,
		BattleController.UnitFilter.OPPONENTS,
		equipment_slot
	)

	for target in targets:
		controller.enqueue_effect(
			Callable(controller, "perform_strike_with_modifier"),
			[user, target, card, damage_modifier, "回旋斩", equipment_slot],
			effect_priority,
			"回旋斩：范围打击",
			{
				"controller": controller,
				"user": user,
				"target": target,
				"card": card,
				"momentum_stacks": momentum_stacks,
				"damage_modifier": damage_modifier,
			}
		)
