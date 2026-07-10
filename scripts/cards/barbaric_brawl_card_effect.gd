extends CardEffect
class_name BarbaricBrawlCardEffect

const EXILE_ACTION_ID := "barbaric_brawl_exile_action"

@export var momentum_range_bonus: float = 2.0
@export_range(0, 99, 1) var exile_power_bonus: int = 2


func get_target_type_for_mode(_context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, _default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return CardEnums.TargetType.ALL


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return false

	var targets := _get_targets(context, controller, user)
	if targets.is_empty():
		if write_log:
			controller._emit_log("%s 武器范围内没有敌人。" % user.get_display_name())
		return false

	return true


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null:
		return

	var targets := _get_targets(context, controller, user)
	for target in targets:
		controller.enqueue_effect(
			Callable(controller, "perform_strike_with_options"),
			[user, target, card, 0, 1.0, "野蛮斗殴", "weapon", {}],
			effect_priority,
			"野蛮斗殴：武器打击",
			{
				"controller": controller,
				"user": user,
				"target": target,
				"card": card,
				"weapon_only": true,
			}
		)


func can_activate_from_exile(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if user == null or card == null:
		return false
	if not user.has_card_in_exile(card):
		return false
	return not user.has_used_battle_action(EXILE_ACTION_ID)


func get_exile_action_label(_context: Dictionary = {}) -> String:
	return "每场战斗限一次：弃置所有手牌，移回弃牌堆，下一次打击 +%d 威力" % exile_power_bonus


func activate_from_exile(context: Dictionary = {}) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if not can_activate_from_exile(context):
		return

	var discarded_count := user.discard_all_hand(context)
	if not user.move_exiled_card_to_discard(card):
		return

	var status := OneShotPowerBonusStatus.new()
	status.stacks = 1
	status.bonus_amount = exile_power_bonus
	user.add_status(status)
	user.mark_battle_action_used(EXILE_ACTION_ID)
	controller._emit_log("%s 弃置 %d 张手牌，将 %s 从放逐区移回弃牌堆，本回合下一次打击 +%d 威力。" % [
		user.get_display_name(),
		discarded_count,
		card.card_name,
		exile_power_bonus,
	])


func _get_targets(context: Dictionary, controller: BattleController, user: BattleUnitState) -> Array[BattleUnitState]:
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	var range_bonus := momentum_range_bonus if play_mode == CardEnums.CardPlayMode.MOMENTUM else 0.0
	return controller.get_units_in_attack_range(
		user,
		range_bonus,
		BattleController.UnitFilter.OPPONENTS,
		"weapon"
	)
