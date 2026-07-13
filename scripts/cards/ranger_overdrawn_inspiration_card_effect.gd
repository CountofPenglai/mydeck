extends RangerCardEffectBase
class_name RangerOverdrawnInspirationCardEffect

const DISCARD_DEBT_STATUS := preload("res://scripts/status/ranger_discard_debt_status.gd")

@export_range(0, 9, 1) var draw_count: int = 2
@export_range(0, 9, 1) var combo_debt: int = 2


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	controller.enqueue_effect(
		Callable(user, "draw_cards"),
		[draw_count, controller.rng, context],
		effect_priority,
		"透支灵感：抽牌",
		context
	)
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.COMBO:
		controller.enqueue_effect(
			Callable(self, "_add_discard_debt"),
			[user, combo_debt],
			-10,
			"透支灵感：记录弃牌债务",
			context
		)
	_enqueue_combo_completion(context)


func _add_discard_debt(user: BattleUnitState, amount: int) -> void:
	if user == null or not user.is_ranger() or amount <= 0:
		return
	user.ranger_state.discard_debt += amount
	var status: StatusEffect = user.get_status("ranger_discard_debt")
	if status == null:
		status = DISCARD_DEBT_STATUS.new() as StatusEffect
		status.stacks = 1
		user.add_status(status)
