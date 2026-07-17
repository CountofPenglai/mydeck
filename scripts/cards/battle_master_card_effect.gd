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

	var valid := get_area_target_cells(context).has(targets[0] as Vector2i)
	if not valid and write_log:
		controller._emit_log("战斗大师需要选择一个 %d AP 移动可达的位置。" % move_ap_limit)
	return valid


func provides_area_target_cells() -> bool:
	return true


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or controller.phase != BattleController.Phase.BATTLE \
			or not user.is_alive() or not user.can_start_voluntary_movement():
		return []
	return controller.get_reachable_cells_for_ap(user, move_ap_limit, false)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return

	controller.enqueue_effect(
		Callable(controller, "apply_card_path_movement_to_cell"),
		[user, targets[0], move_ap_limit, false, "战斗大师"],
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
