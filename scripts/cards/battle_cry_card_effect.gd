extends CardEffect
class_name BattleCryCardEffect

@export_range(0, 99, 1) var mill_count: int = 2
@export_range(0, 99, 1) var stun_stacks: int = 3


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1:
		return
	if not (targets[0] is BattleUnitState):
		return

	var target := targets[0] as BattleUnitState
	controller.enqueue_effect(Callable(self, "_mill"), [controller, user, context], effect_priority, "临阵怒喝：磨牌", context)
	controller.enqueue_effect(Callable(self, "_stun"), [controller, target], effect_priority, "临阵怒喝：眩晕", context)
	controller.enqueue_effect(Callable(controller, "switch_prepared_weapon"), [user], effect_priority, "临阵怒喝：切换武器", context)


func _mill(controller: BattleController, user: BattleUnitState, context: Dictionary) -> void:
	var milled := user.mill_cards(mill_count, context)
	controller._emit_log("%s 磨了 %d 张牌。" % [user.get_display_name(), milled.size()])


func _stun(controller: BattleController, target: BattleUnitState) -> void:
	if target == null or not target.is_alive():
		return
	var status := StunStatus.new()
	status.stacks = stun_stacks
	target.add_status(status)
	controller._emit_log("%s 获得 %d 层眩晕。" % [target.get_display_name(), stun_stacks])
