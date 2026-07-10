extends CardEffect
class_name HiddenBladeAgainCardEffect

@export_range(0, 99, 1) var momentum_damage_bonus: int = 2


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
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	var damage_bonus := momentum_damage_bonus if play_mode == CardEnums.CardPlayMode.MOMENTUM else 0
	controller.enqueue_effect(
		Callable(controller, "perform_strike_with_modifier"),
		[user, target, card, damage_bonus, "藏锋再起", str(context.get("equipment_slot", ""))],
		effect_priority,
		"藏锋再起：武器打击",
		context
	)
