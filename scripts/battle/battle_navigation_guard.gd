extends RefCounted
class_name BattleNavigationGuard


static func check(controller: BattleController, ui_choice_pending: bool) -> Dictionary:
	if controller == null:
		return _blocked("战斗尚未准备好。")
	var runner := controller.resolution_runner
	if controller.is_resolving_actions() or runner.action_active or not runner.action_queue.is_empty() \
			or runner.queue_depth > 0 or runner.is_attack_scope_active() or runner.get_current_effect_queue_size() > 0 \
			or not runner.after_current_effect_queue.is_empty():
		return _blocked("当前行动尚未完全结算，请稍候。")
	if ui_choice_pending or runner.has_pending_hand_card_choice() or runner.has_pending_unit_target_choice():
		return _blocked("请先完成当前选择，再返回主菜单。")
	for unit in controller.player_units:
		if unit.ranger_state.pending_hand_discard_count > 0:
			return _blocked("请先完成需要弃置的手牌。")
	if controller.phase == BattleController.Phase.BATTLE:
		if controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE:
			return _blocked("正在切换回合，请稍候。")
		if controller.current_unit != null and controller.current_unit.faction == BattleUnitState.Faction.ENEMY:
			return _blocked("请等待敌方行动完成。")
	return {"ok": true, "message": ""}


static func _blocked(message: String) -> Dictionary:
	return {"ok": false, "message": message}
