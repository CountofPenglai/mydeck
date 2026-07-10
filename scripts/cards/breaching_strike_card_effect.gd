extends CardEffect
class_name BreachingStrikeCardEffect

const BREACH_STATUS_SCRIPT := preload("res://scripts/status/breach_status.gd")

@export_range(1.0, 4.0, 0.05) var breach_multiplier: float = 1.5


func _init() -> void:
	uses_strike = true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	if not (targets[0] is BattleUnitState):
		return

	var target := targets[0] as BattleUnitState
	controller.enqueue_effect(
		Callable(controller, "perform_strike"),
		[user, target, card, "凿阵一击", str(context.get("equipment_slot", ""))],
		effect_priority,
		"凿阵一击：武器打击",
		context
	)
	controller.enqueue_effect(
		Callable(self, "_apply_breach"),
		[controller, user, target],
		effect_priority,
		"凿阵一击：施加破绽",
		context
	)


func _apply_breach(controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> void:
	if controller == null or user == null or target == null or not target.is_alive():
		return
	var status := BREACH_STATUS_SCRIPT.new()
	status.status_id = "breach_%d" % user.unit_id
	status.applied_by = user
	status.expires_on_source_turn = user.turn_serial + 1
	status.damage_multiplier = breach_multiplier
	target.remove_status(status.status_id)
	target.add_status(status)
	controller._emit_log("%s 被凿开破绽：下一段友方正数伤害 x%.1f。" % [target.get_display_name(), breach_multiplier])
