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

	var end_button := battle_scene.end_turn_button as Button
	var viewport_rect: Rect2 = battle_scene.get_viewport_rect()
	var button_rect: Rect2 = end_button.get_global_rect()
	var top_overlay := battle_scene.get_node("TopOverlay") as Control
	var equipment_panel := battle_scene.get_node("CurrentUnitPanel") as Control
	var bottom_hud := battle_scene.get_node("BottomHud") as Control
	print("DRUID_KALEIDOSCOPE_UI: viewport=%s overlay=%s end=%s disabled=%s" % [
		viewport_rect,
		top_overlay.get_global_rect(),
		button_rect,
		end_button.disabled,
	])
	if not viewport_rect.encloses(button_rect):
		_fail("DRUID_KALEIDOSCOPE_UI: end-turn button is outside the viewport")
	elif end_button.disabled:
		_fail("DRUID_KALEIDOSCOPE_UI: end-turn button is unexpectedly disabled")
	elif button_rect.intersects(bottom_hud.get_global_rect()):
		_fail("DRUID_KALEIDOSCOPE_UI: bottom HUD occludes the end-turn button")
	elif not viewport_rect.encloses(equipment_panel.get_global_rect()):
		_fail("DRUID_KALEIDOSCOPE_UI: equipment panel is outside the viewport")
	elif battle_scene.equipment_list.get_child_count() < 7:
		_fail("DRUID_KALEIDOSCOPE_UI: kaleidoscope actions were not rendered in equipment panel")
	else:
		battle_scene._on_end_turn_pressed()
		if controller.current_unit != next_player \
				or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE \
				or controller.is_resolving_actions():
			_fail("DRUID_KALEIDOSCOPE_UI: scene end-turn handler did not advance the turn")

	battle_scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(_exit_code)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
