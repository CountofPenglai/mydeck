extends CardEffect
class_name DruidWildWanderCardEffect


@export_range(1, 12, 1) var movement_range := 7


func grants_elemental_surface_protection(_owner: BattleUnitState) -> bool:
	return true


func grants_druid_extra_earth(_owner: BattleUnitState) -> bool:
	return true


func provides_area_target_cells() -> bool:
	return true


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return result
	for cell in controller.map_data.get_all_cells():
		if _is_valid_landing(controller, user, cell):
			result.append(cell)
	return result


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var valid := controller != null and user != null and targets.size() == 1 and targets[0] is Vector2i \
		and _is_valid_landing(controller, user, targets[0] as Vector2i)
	if not valid and write_log and controller != null:
		controller._emit_log("随风入野需要选择范围 %d 内未被占据的元素地表空格。" % movement_range)
	return valid


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return
	var landing := targets[0] as Vector2i
	if not _is_valid_landing(controller, user, landing):
		return
	controller.mark_played_card_to_mana(context)
	var card_context := context.get("card_context") as CardPlayContext
	if not user.move_hand_card_to_mana(card, {
		"controller": controller,
		"reason": "druid_wild_wander",
		"source": user,
		"source_card": card,
		"card_context": card_context,
	}):
		return
	if card_context != null:
		card_context.extra["druid_mana_entry_committed"] = true
	controller.resolution_runner.enqueue_after_current_effect_queue(
		Callable(self, "_resolve_teleport"),
		[controller, user, landing],
		"随风入野：传送"
	)


func _resolve_teleport(controller: BattleController, user: BattleUnitState, landing: Vector2i) -> void:
	if _is_valid_landing(controller, user, landing):
		controller.apply_card_movement_to_cell(user, landing, "随风入野")


func _is_valid_landing(controller: BattleController, user: BattleUnitState, cell: Vector2i) -> bool:
	return controller != null and user != null and controller.phase == BattleController.Phase.BATTLE \
		and user.is_alive() and user.can_start_voluntary_movement() and controller.map_data.is_valid_cell(cell) \
		and cell != user.cell \
		and controller.map_data.get_distance(user.cell, cell) <= movement_range \
		and not controller.surface_state.get_readable_elements(cell).is_empty() \
		and controller.targeting.is_unit_cell_clear(user, cell, false)
