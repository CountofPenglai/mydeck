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

	for node_name in ["TurnOrderBar", "DeploymentPanel", "DetailPanel", "BottomHud", "MenuButton"]:
		if hud_root.get_node_or_null("%%%s" % node_name) == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s missing at %s" % [node_name, target_size])
			break

	var bottom_hud := hud_root.get_node_or_null("%BottomHud") as Control
	if bottom_hud != null:
		var height := bottom_hud.size.y
		var expected_height := clampf(float(target_size.y) * 0.26, 176.0, 224.0)
		_assert_close(height, expected_height, 1.1, "bottom HUD height", target_size)
		if bottom_hud.get_global_rect().end.y > float(target_size.y) + 1.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD leaves viewport at %s" % target_size)

	var equipment_region := hud_root.get_node_or_null("%EquipmentRegion")
	if equipment_region == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: EquipmentRegion missing at %s" % target_size)
	elif _contains_scroll_container(equipment_region):
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment region contains scrolling at %s" % target_size)

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

	var detail_panel := hud_root.get_node_or_null("%DetailPanel") as Control
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
