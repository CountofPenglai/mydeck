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

	host.queue_free()
	await get_tree().process_frame


func _contains_scroll_container(root: Node) -> bool:
	for child in root.get_children():
		if child is ScrollContainer or _contains_scroll_container(child):
			return true
	return false


func _assert_close(actual: float, expected: float, tolerance: float, label: String, target_size: Vector2i) -> void:
	if absf(actual - expected) > tolerance:
		_fail("BATTLE_HUD_LAYOUT_CHECK: %s %.1f expected %.1f at %s" % [label, actual, expected, target_size])


func _fail(message: String) -> void:
	if _exit_code == 0:
		push_error(message)
		print("ERROR: " + message)
	_exit_code = 1
