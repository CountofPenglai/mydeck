extends RangerCardEffectBase
class_name RangerFullFlavorCardEffect

@export_range(0, 9, 1) var base_draw_count: int = 2
@export_range(0, 9, 1) var diverse_bonus_draw: int = 1
@export_range(0, 9, 1) var complete_bonus_draw: int = 1


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or not user.is_ranger():
		return
	var type_count := user.ranger_state.get_element_type_count()
	var draw_total := base_draw_count
	if type_count >= 2:
		draw_total += diverse_bonus_draw
	if type_count >= 4:
		draw_total += complete_bonus_draw
	controller.enqueue_effect(
		Callable(user, "draw_cards"),
		[draw_total, controller.rng, context],
		effect_priority,
		"百味齐备：抽牌",
		context
	)
