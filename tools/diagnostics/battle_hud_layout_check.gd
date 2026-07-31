extends Node

const TARGET_SIZES := [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
]

var _exit_code := 0


func _ready() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: battle scene failed to load")
		get_tree().quit(_exit_code)
		return

	for target_size in TARGET_SIZES:
		await _check_size(packed, target_size)
		if _exit_code != 0:
			break

	if _exit_code == 0:
		print("BATTLE_HUD_LAYOUT_CHECK: PASS")
	get_tree().quit(_exit_code)


func _check_size(packed: PackedScene, target_size: Vector2i) -> void:
	get_window().size = target_size
	var host := Control.new()
	host.size = Vector2(target_size)
	add_child(host)
	var battle_scene := packed.instantiate() as Control
	host.add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud_root := battle_scene.get_node_or_null("%BattleHudRoot") as Control
	if hud_root == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: BattleHudRoot missing at %s" % target_size)
		host.queue_free()
		await get_tree().process_frame
		return

	for node_name in ["TurnOrderBar", "DeploymentPanel", "BattleDetailPanel", "BattleBottomHud", "MenuButton"]:
		if hud_root.get_node_or_null("%%%s" % node_name) == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s missing at %s" % [node_name, target_size])
			break

	var bottom_hud := hud_root.get_node_or_null("%BattleBottomHud") as Control
	if bottom_hud != null:
		var height := bottom_hud.size.y
		var expected_height := clampf(float(target_size.y) * 0.26, 176.0, 224.0)
		_assert_close(height, expected_height, 1.1, "bottom HUD height", target_size)
		if bottom_hud.get_global_rect().end.y > float(target_size.y) + 1.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD leaves viewport at %s" % target_size)

	var equipment_region := bottom_hud.get_node_or_null("%EquipmentRegion") if bottom_hud != null else null
	if equipment_region == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: EquipmentRegion missing at %s" % target_size)
	elif _contains_scroll_container(equipment_region):
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment region contains scrolling at %s" % target_size)
	var equipment_popup := hud_root.get_node_or_null("%EquipmentActionsPopup")
	if equipment_popup == null or not equipment_popup.has_method("set_actions"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment action popup API missing at %s" % target_size)
	else:
		equipment_popup.call("set_actions", null, [
			{"label": "动作一", "action_id": "one"},
			{"label": "动作二", "action_id": "two"},
			{"label": "动作三", "action_id": "three"},
		], Callable(), target_size.x < 1100)
		if int(equipment_popup.call("get_action_count")) != 3:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup lost actions at %s" % target_size)
		var expected_popup_columns := 1 if target_size.x < 1100 else 2
		if int(equipment_popup.call("get_column_count")) != expected_popup_columns:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup columns mismatch at %s" % target_size)
		if _contains_scroll_container(equipment_popup):
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup contains scrolling at %s" % target_size)

	if hud_root.has_method("get_equipment_column_count"):
		var expected_columns := 1 if target_size.x < 1100 else 2
		if int(hud_root.call("get_equipment_column_count")) != expected_columns:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment columns mismatch at %s" % target_size)
	else:
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment column API missing")

	if hud_root.has_method("is_compact_mode"):
		if bool(hud_root.call("is_compact_mode")) != (target_size.x < 1100):
			_fail("BATTLE_HUD_LAYOUT_CHECK: compact mode mismatch at %s" % target_size)
	else:
		_fail("BATTLE_HUD_LAYOUT_CHECK: compact mode API missing")

	var state_controller = battle_scene.get("controller")
	var deploy_list := hud_root.get_node_or_null("%DeployList") as Container
	if state_controller is BattleController and deploy_list != null:
		hud_root.call("refresh_view")
		if deploy_list.get_child_count() != state_controller.player_units.size():
			_fail("BATTLE_HUD_LAYOUT_CHECK: deployment rows do not match player units at %s" % target_size)
		state_controller.call("_rebuild_turn_order")
		state_controller.current_turn_index = mini(1, state_controller.turn_order.size() - 1)
		if state_controller.current_turn_index >= 0:
			state_controller.current_unit = state_controller.turn_order[state_controller.current_turn_index]
		hud_root.call("refresh_view")
		var order_list := hud_root.get_node_or_null("%OrderList") as Container
		if order_list == null or order_list.get_child_count() != state_controller.turn_order.size():
			_fail("BATTLE_HUD_LAYOUT_CHECK: turn order does not match locked round at %s" % target_size)
		elif not state_controller.turn_order.is_empty():
			var first_entry := order_list.get_child(0)
			if not first_entry.has_meta("faction") or not first_entry.has_meta("acted") or not first_entry.has_meta("current"):
				_fail("BATTLE_HUD_LAYOUT_CHECK: turn order metadata missing at %s" % target_size)
		var bottom_module := hud_root.get_node_or_null("%BattleBottomHud")
		if bottom_module == null or not bottom_module.has_method("get_bound_unit"):
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD binding API missing at %s" % target_size)
		else:
			var selected_unit = battle_scene.get("selected_deploy_unit")
			if bottom_module.call("get_bound_unit") != selected_unit:
				_fail("BATTLE_HUD_LAYOUT_CHECK: deployment HUD is not bound to selected unit at %s" % target_size)
			if state_controller.current_turn_index >= 0:
				state_controller.phase = BattleController.Phase.BATTLE
				hud_root.call("refresh_view")
				if bottom_module.call("get_bound_unit") != state_controller.current_unit:
					_fail("BATTLE_HUD_LAYOUT_CHECK: battle HUD is not bound to acting unit at %s" % target_size)
				var hand_list := bottom_module.get_node_or_null("%HandList") as Container
				if state_controller.current_unit.faction == BattleUnitState.Faction.PLAYER \
						and not state_controller.current_unit.hand.is_empty() \
						and (hand_list == null or hand_list.get_child_count() != state_controller.current_unit.hand.size()):
					_fail("BATTLE_HUD_LAYOUT_CHECK: hand cards do not match acting unit at %s" % target_size)

	var map_view := battle_scene.get_node_or_null("%MapView") as Control
	if map_view == null or not map_view.has_method("set_fit_safe_rect"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: map safe-area API missing at %s" % target_size)
	elif hud_root.has_method("get_battle_safe_rect"):
		var safe_rect: Rect2 = hud_root.call("get_battle_safe_rect")
		map_view.call("set_fit_safe_rect", safe_rect)
		map_view.call("_reset_view_to_fit")
		var controller = battle_scene.get("controller")
		if controller is BattleController and controller.map_data != null:
			var top_left: Vector2 = map_view.call("map_to_screen", Vector2.ZERO)
			var bottom_right: Vector2 = map_view.call("map_to_screen", controller.map_data.map_size)
			if top_left.x < safe_rect.position.x - 1.0 or top_left.y < safe_rect.position.y - 1.0 \
					or bottom_right.x > safe_rect.end.x + 1.0 or bottom_right.y > safe_rect.end.y + 1.0:
				_fail("BATTLE_HUD_LAYOUT_CHECK: map does not fit HUD safe area at %s" % target_size)

	var detail_panel := hud_root.get_node_or_null("%BattleDetailPanel") as Control
	if detail_panel == null or not detail_panel.has_method("preview_card"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: unified detail API missing at %s" % target_size)
	elif state_controller is BattleController and not state_controller.player_units.is_empty():
		var detail_card: CardData = null
		var detail_unit: BattleUnitState = state_controller.player_units[0]
		if not detail_unit.hand.is_empty():
			detail_card = detail_unit.hand[0]
		elif not detail_unit.draw_pile.is_empty():
			detail_card = detail_unit.draw_pile[0]
		if detail_card != null:
			detail_panel.call("preview_card", detail_card, {"user": detail_unit})
			detail_panel.call("lock_current")
			detail_panel.call("preview_unit", state_controller.enemy_units[0] if not state_controller.enemy_units.is_empty() else detail_unit)
			detail_panel.call("clear_preview")
			if str(detail_panel.call("get_display_title")) != detail_card.card_name:
				_fail("BATTLE_HUD_LAYOUT_CHECK: detail hover did not restore locked card at %s" % target_size)
			detail_panel.call("clear_lock")
			if detail_panel.visible:
				_fail("BATTLE_HUD_LAYOUT_CHECK: clearing detail lock did not hide panel at %s" % target_size)
		if not battle_scene.has_method("handle_map_hover"):
			_fail("BATTLE_HUD_LAYOUT_CHECK: map hover detail bridge missing at %s" % target_size)
		elif not state_controller.enemy_units.is_empty():
			var hover_enemy: BattleUnitState = state_controller.enemy_units[0]
			battle_scene.call("handle_map_hover", hover_enemy.position)
			if str(detail_panel.call("get_display_title")) != hover_enemy.get_display_name():
				_fail("BATTLE_HUD_LAYOUT_CHECK: map hover did not preview enemy at %s" % target_size)
	var battle_controller = battle_scene.get("controller")
	if detail_panel != null and battle_controller is BattleController and not battle_controller.player_units.is_empty():
		detail_panel.visible = true
		battle_controller.phase = BattleController.Phase.BATTLE
		battle_controller.current_unit = battle_controller.player_units[0]
		battle_controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
		var empty_cell := _find_empty_cell(battle_controller)
		if empty_cell.x >= 0:
			battle_scene.call("handle_map_click", battle_controller.map_data.cell_to_map(empty_cell))
			if detail_panel.visible:
				_fail("BATTLE_HUD_LAYOUT_CHECK: blank map click did not close detail at %s" % target_size)

	host.queue_free()
	await get_tree().process_frame


func _contains_scroll_container(root: Node) -> bool:
	for child in root.get_children():
		if child is ScrollContainer or _contains_scroll_container(child):
			return true
	return false


func _find_empty_cell(controller: BattleController) -> Vector2i:
	for cell in controller.map_data.get_all_cells():
		if controller.get_unit_at_cell(cell) == null and controller.get_battle_object_at_cell(cell) == null:
			return cell
	return Vector2i(-1, -1)


func _assert_close(actual: float, expected: float, tolerance: float, label: String, target_size: Vector2i) -> void:
	if absf(actual - expected) > tolerance:
		_fail("BATTLE_HUD_LAYOUT_CHECK: %s %.1f expected %.1f at %s" % [label, actual, expected, target_size])


func _fail(message: String) -> void:
	if _exit_code == 0:
		push_error(message)
		print("ERROR: " + message)
	_exit_code = 1
