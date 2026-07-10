extends CardEffect
class_name ChargeCardEffect

@export var agility_modifier: int = 3
@export var move_ap_budget: int = 2
@export var strike_damage_modifier: int = -2

func _init() -> void:
	uses_strike = true


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller = context.get("controller")
	var user = context.get("user")
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2):
		return false

	return controller.can_unit_reach_position_with_ap_and_agility_modifier(user, targets[0], move_ap_budget, agility_modifier, write_log)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	var card = context.get("card")
	if controller == null or user == null or targets.is_empty() or not (targets[0] is Vector2):
		return

	var requested_position: Vector2 = targets[0]
	var movement = controller.apply_movement_effect(user, requested_position, agility_modifier, false, move_ap_budget)
	if not bool(movement.get("success", false)):
		return

	var start_position: Vector2 = movement.get("start_position", user.position)
	var end_position: Vector2 = movement.get("end_position", user.position)
	var hits = controller.get_units_in_swept_circle(
		user,
		start_position,
		end_position,
		user.radius,
		BattleController.UnitFilter.OPPONENTS
	)
	for target in hits:
		controller.enqueue_effect(
			Callable(controller, "perform_strike_with_modifier"),
			[user, target, card, strike_damage_modifier, "冲锋打击", str(context.get("equipment_slot", ""))],
			effect_priority,
			"冲锋途经打击",
			{
				"controller": controller,
				"user": user,
				"target": target,
				"card": card,
			}
		)
