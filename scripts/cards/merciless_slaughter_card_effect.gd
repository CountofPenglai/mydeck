extends CardEffect
class_name MercilessSlaughterCardEffect

@export_range(1, 99, 1) var execution_base_damage_multiplier: int = 2
@export_range(0, 99, 1) var self_stun_stacks: int = 2


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false

	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null or not target.is_alive() or target.faction == user.faction:
		if write_log:
			controller._emit_log("请选择一个敌方目标。")
		return false

	var main_range := user.get_attack_range("weapon")
	var distance := user.cell_distance_to(target)
	if distance > main_range:
		if write_log:
			controller._emit_log("%s 距离 %.0f，超出武器射程 %.0f。" % [target.get_display_name(), distance, main_range])
		return false

	return true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return

	var target: BattleUnitState = targets[0] as BattleUnitState
	controller.enqueue_effect(
		Callable(controller, "perform_strike_with_options"),
		[user, target, card, 0, 1.0, "无情屠杀", "weapon", {}],
		effect_priority,
		"无情屠杀：武器打击",
		context
	)
	controller.enqueue_effect(
		Callable(self, "_resolve_followup"),
		[controller, user, target],
		effect_priority,
		"无情屠杀：后续结算",
		context
	)


func _resolve_followup(controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> void:
	if controller == null or user == null:
		return

	if target != null and target.is_alive():
		var profile := user.build_strike_profile_object("weapon", {})
		var execution_threshold := profile.primary_base_damage * execution_base_damage_multiplier
		if target.get_current_health() <= execution_threshold:
			target.set_current_health(0)
			controller._emit_log("%s 的生命值不大于武器基础伤害的 %d 倍，被无情屠杀消灭。" % [
				target.get_display_name(),
				execution_base_damage_multiplier,
			])

	controller.switch_weapon_from_inventory(user)
	var stun := StunStatus.new()
	stun.stacks = self_stun_stacks
	user.add_status(stun)
	controller._emit_log("%s 获得 %d 层眩晕。" % [user.get_display_name(), self_stun_stacks])
	controller.state_changed.emit()
	controller._check_battle_end()
