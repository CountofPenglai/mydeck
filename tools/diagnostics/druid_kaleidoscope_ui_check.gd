extends Node

var _exit_code := 0


func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	var battle_scene := packed.instantiate()
	add_child(battle_scene)
	await get_tree().process_frame

	var controller := battle_scene.controller as BattleController
	var druid: BattleUnitState = null
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			druid = unit
			break
	if druid == null:
		_fail("DRUID_KALEIDOSCOPE_UI: missing druid")
		get_tree().quit(_exit_code)
		return

	druid.character_state.weapon_equipment = load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData
	druid.equipment_runtime_states.clear()
	druid.set_druid_transformed(false)
	druid.turn_serial = 1
	druid.is_deployed = true
	var next_player: BattleUnitState = null
	for unit in controller.player_units:
		if unit != druid:
			next_player = unit
			next_player.is_deployed = true
			break
	if next_player == null:
		_fail("DRUID_KALEIDOSCOPE_UI: missing next player")
		get_tree().quit(_exit_code)
		return
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_order = [druid, next_player]
	controller.current_turn_index = 0
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	druid.notify_equipment_turn_start({"controller": controller, "phase": "turn_start"})
	var runtime := druid.get_equipment_runtime_state(druid.character_state.weapon_equipment)
	runtime.set_flag("wager_pending", true)
	battle_scene._refresh()
	await get_tree().process_frame

	var hud_root := battle_scene.get_node_or_null("%BattleHudRoot") as Control
	var bottom_hud := hud_root.get_node_or_null("%BattleBottomHud") as Control if hud_root != null else null
	var end_button := bottom_hud.get_node_or_null("%HudEndTurnButton") as Button if bottom_hud != null else null
	var equipment_button := bottom_hud.get_node_or_null("%EquipmentButton") as Button if bottom_hud != null else null
	var equipment_label := bottom_hud.get_node_or_null("%EquipmentLabel") as Label if bottom_hud != null else null
	var equipment_popup := hud_root.get_node_or_null("%EquipmentActionsPopup") if hud_root != null else null
	var viewport_rect: Rect2 = battle_scene.get_viewport_rect()
	var button_rect := end_button.get_global_rect() if end_button != null else Rect2()
	var equipment_button_rect := equipment_button.get_global_rect() if equipment_button != null else Rect2()
	var equipment_label_rect := equipment_label.get_global_rect() if equipment_label != null else Rect2()
	print("DRUID_KALEIDOSCOPE_UI: viewport=%s hud=%s end=%s disabled=%s" % [
		viewport_rect,
		bottom_hud.get_global_rect() if bottom_hud != null else Rect2(),
		button_rect,
		end_button.disabled if end_button != null else true,
	])
	if hud_root == null or bottom_hud == null or end_button == null or equipment_button == null \
			or equipment_label == null or equipment_popup == null:
		_fail("DRUID_KALEIDOSCOPE_UI: new battle HUD modules are missing")
	elif not viewport_rect.encloses(button_rect):
		_fail("DRUID_KALEIDOSCOPE_UI: end-turn button is outside the viewport")
	elif end_button.disabled:
		_fail("DRUID_KALEIDOSCOPE_UI: end-turn button is unexpectedly disabled")
	elif not equipment_button.is_visible_in_tree() or not equipment_label.is_visible_in_tree():
		_fail("DRUID_KALEIDOSCOPE_UI: multifunction equipment affordance is hidden")
	elif not viewport_rect.encloses(equipment_button_rect) or not viewport_rect.encloses(equipment_label_rect):
		_fail("DRUID_KALEIDOSCOPE_UI: multifunction equipment affordance is outside the viewport")
	elif equipment_button.disabled:
		_fail("DRUID_KALEIDOSCOPE_UI: multifunction equipment affordance is disabled")
	elif not equipment_label.text.contains("展开"):
		_fail("DRUID_KALEIDOSCOPE_UI: multifunction equipment has no expand affordance")
	else:
		equipment_button.pressed.emit()
		await get_tree().process_frame
		if not bool(equipment_popup.call("is_open")):
			_fail("DRUID_KALEIDOSCOPE_UI: multifunction equipment popup did not open")
		elif int(equipment_popup.call("get_action_count")) < 6:
			_fail("DRUID_KALEIDOSCOPE_UI: kaleidoscope actions were not rendered")
		elif _contains_scroll_container(equipment_popup):
			_fail("DRUID_KALEIDOSCOPE_UI: equipment popup must not contain scrolling")
		equipment_popup.call("close")
		battle_scene._on_end_turn_pressed()
		if controller.current_unit != next_player \
				or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE \
				or controller.is_resolving_actions():
			_fail("DRUID_KALEIDOSCOPE_UI: scene end-turn handler did not advance the turn")

	battle_scene.queue_free()
	await get_tree().process_frame
	if _exit_code == 0:
		print("DRUID_KALEIDOSCOPE_UI: PASS")
	get_tree().quit(_exit_code)


func _contains_scroll_container(root: Node) -> bool:
	for child in root.get_children():
		if child is ScrollContainer or _contains_scroll_container(child):
			return true
	return false


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
