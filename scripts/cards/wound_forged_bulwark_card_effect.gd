extends CardEffect
class_name WoundForgedBulwarkCardEffect

const CLEAR_ARMOR_STATUS_SCRIPT := preload("res://scripts/status/clear_armor_next_turn_status.gd")

@export var effect_range: float = 90.0


func get_target_type_for_mode(_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL, _default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return CardEnums.TargetType.ALL if play_mode == CardEnums.CardPlayMode.MOMENTUM else CardEnums.TargetType.SELF


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return false
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM:
		return user.get_armor_stacks() > 0
	return true


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM:
		_play_momentum(controller, user, context)
		return

	var armor_gain := maxi(0, user.get_max_health() - user.get_current_health())
	user.gain_armor(armor_gain, context)
	user.remove_status("clear_armor_next_turn")
	var clear_status := CLEAR_ARMOR_STATUS_SCRIPT.new()
	clear_status.stacks = 1
	user.add_status(clear_status)
	controller._emit_log("%s 获得 %d 护甲；这些护甲将在其下回合开始时清空。" % [user.get_display_name(), armor_gain])


func _play_momentum(controller: BattleController, user: BattleUnitState, context: Dictionary) -> void:
	var destroyed := user.clear_armor({
		"controller": controller,
		"reason": "wound_forged_bulwark_momentum",
	})
	var targets := controller.get_units_in_range(user, effect_range, BattleController.UnitFilter.OPPONENTS)
	controller._emit_log("%s 摧毁 %d 护甲，释放伤铸冲击。" % [user.get_display_name(), destroyed])
	for target in targets:
		controller.enqueue_effect(
			Callable(controller, "apply_damage"),
			[user, target, destroyed, "伤铸壁垒"],
			effect_priority,
			"伤铸壁垒：范围伤害",
			context
		)
