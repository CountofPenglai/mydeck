extends CardEffect
class_name WarriorTurningSlashCardEffect

@export_range(1, 99, 1) var post_switch_fixed_damage: int = 1


func _init() -> void:
	uses_strike = true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	controller.perform_unit_strike_with_after_effects(user, target, card, "转锋斩", str(context.get("equipment_slot", "")), Callable(self, "_switch_and_damage").bind(controller, user, card, context))


func _switch_and_damage(controller: BattleController, user: BattleUnitState, card: CardData, context: Dictionary) -> void:
	if controller == null or user == null:
		return
	if not bool(controller.switch_prepared_weapon(user).get("success", false)):
		return
	for target in controller.get_units_in_attack_range(user, 0, BattleController.UnitFilter.OPPONENTS, "weapon"):
		controller.apply_damage(user, target, post_switch_fixed_damage, "转锋斩", {"source_card": card, "fixed_damage": true}.merged(context))
