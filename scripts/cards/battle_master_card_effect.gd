extends CardEffect
class_name BattleMasterCardEffect

@export_range(0, 10, 1) var move_ap_limit: int = 1
@export var momentum_gain: int = 1
@export var free_attack_card_stacks: int = 1


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller = context.get("controller")
	var user = context.get("user")
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return false

	return controller.can_unit_reach_cell_with_ap(user, targets[0], move_ap_limit, write_log, false)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return

	controller.enqueue_effect(
		Callable(controller, "apply_card_movement_to_cell"),
		[user, targets[0], "战斗大师"],
		effect_priority,
		"战斗大师：移动",
		context
	)
	controller.enqueue_effect(
		Callable(controller, "switch_weapon_from_inventory"),
		[user],
		effect_priority,
		"战斗大师：切换武器",
		context
	)
	controller.enqueue_effect(
		Callable(controller, "gain_class_resource"),
		[user, BattleController.WARRIOR_MOMENTUM_RESOURCE, momentum_gain],
		effect_priority,
		"战斗大师：获得势",
		context
	)
	controller.enqueue_effect(
		Callable(controller, "grant_next_attack_card_free"),
		[user, free_attack_card_stacks],
		effect_priority,
		"战斗大师：下一张攻击牌免费",
		context
	)
