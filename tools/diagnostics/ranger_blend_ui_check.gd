extends Node

const STEAM := BattleSurfaceState.Element.STEAM
const FIRE := BattleSurfaceState.Element.FIRE
const WATER := BattleSurfaceState.Element.WATER

var _exit_code := 0


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("RANGER_BLEND_UI: battle scene failed to load")
		_finish()
		return
	var battle_scene := packed.instantiate() as BattleScene
	add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var ranger := _prepare_active_ranger(battle_scene)
	if ranger != null:
		await _test_nonstealth_eligible_action_and_popup(battle_scene, ranger)
		await _test_unavailable_action_stays_visible_with_feedback(battle_scene, ranger)
		await _test_popup_selection_revalidates(battle_scene, ranger)

	battle_scene.queue_free()
	await get_tree().process_frame
	_finish()


func _prepare_active_ranger(battle_scene: BattleScene) -> BattleUnitState:
	var controller := battle_scene.controller as BattleController
	var ranger := _find_ranger(controller)
	if ranger == null:
		_fail("RANGER_BLEND_UI: sample battle has no ranger")
		return null
	for unit in controller.player_units:
		unit.is_deployed = true
	ranger.is_deployed = true
	ranger.turn_serial = 1
	ranger.leave_stealth()
	ranger.ranger_state.prepared_blend = BattleSurfaceState.Element.NONE
	ranger.ranger_state.prepared_weapon_slot = ""
	ranger.ranger_state.element_inventory.clear()
	ranger.ranger_state.add_element(FIRE)
	ranger.ranger_state.add_element(WATER)
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	battle_scene._refresh()
	return ranger


func _test_nonstealth_eligible_action_and_popup(battle_scene: BattleScene, ranger: BattleUnitState) -> void:
	var controller := battle_scene.controller as BattleController
	if not _can_prepare(controller, ranger, "non-stealth active turn"):
		return
	battle_scene._refresh()
	await get_tree().process_frame
	var action := _blend_action(battle_scene)
	if action == null:
		_fail("RANGER_BLEND_UI: eligible non-stealthed ranger has no 特调 action")
		return
	if action.disabled:
		_fail("RANGER_BLEND_UI: eligible non-stealthed ranger 特调 action is disabled")
	if not action.tooltip_text.contains("每回合一次") or not action.tooltip_text.contains("实际进入潜行"):
		_fail("RANGER_BLEND_UI: 特调 tooltip does not explain turn opportunity and actual stealth refresh")
	action.pressed.emit()
	await get_tree().process_frame
	var popup := battle_scene.get("_ranger_blend_popup") as PopupPanel
	if popup == null or not popup.visible:
		_fail("RANGER_BLEND_UI: eligible 特调 action did not open the blend popup")
		return
	if _find_blend_button(battle_scene, STEAM, "weapon") == null:
		_fail("RANGER_BLEND_UI: payable Steam melee recipe is absent from blend popup")
	popup.hide()


func _test_unavailable_action_stays_visible_with_feedback(battle_scene: BattleScene, ranger: BattleUnitState) -> void:
	var controller := battle_scene.controller as BattleController
	controller.turn_flow_state = BattleController.TurnFlowState.END_PENDING
	if _can_prepare(controller, ranger, "resolving action guard", false):
		_fail("RANGER_BLEND_UI: controller allowed 特调 outside the active free-time state")
		controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
		return
	battle_scene._refresh()
	await get_tree().process_frame
	var action := _blend_action(battle_scene)
	if action == null:
		_fail("RANGER_BLEND_UI: unavailable Ranger opportunity disappeared instead of showing feedback")
	elif not action.disabled:
		_fail("RANGER_BLEND_UI: 特调 action stays enabled outside free time")
	elif not action.tooltip_text.contains("当前不能调配"):
		_fail("RANGER_BLEND_UI: unavailable 特调 action has no current-state feedback")
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE


func _test_popup_selection_revalidates(battle_scene: BattleScene, ranger: BattleUnitState) -> void:
	var controller := battle_scene.controller as BattleController
	if not _can_prepare(controller, ranger, "selection precondition"):
		return
	battle_scene._show_ranger_blend_popup(ranger)
	await get_tree().process_frame
	var before_elements := ranger.ranger_state.element_inventory.duplicate(true)
	controller.turn_flow_state = BattleController.TurnFlowState.END_PENDING
	battle_scene._on_ranger_blend_selected(ranger, STEAM, "weapon")
	if ranger.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE \
			or ranger.ranger_state.element_inventory != before_elements:
		_fail("RANGER_BLEND_UI: stale blend popup selection bypassed controller revalidation")
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE


func _can_prepare(controller: BattleController, ranger: BattleUnitState, label: String, fail_when_missing: bool = true) -> bool:
	if not controller.has_method("can_prepare_ranger_blend"):
		if fail_when_missing:
			_fail("RANGER_BLEND_UI: missing can_prepare_ranger_blend contract for %s" % label)
		return false
	return bool(controller.call("can_prepare_ranger_blend", ranger))


func _blend_action(battle_scene: BattleScene) -> Button:
	var hud_root := battle_scene.get_node_or_null("%BattleHudRoot") as Control
	var bottom_hud := hud_root.get_node_or_null("%BattleBottomHud") as Control if hud_root != null else null
	var action_list := bottom_hud.get_node_or_null("%ResourceActionList") as Container if bottom_hud != null else null
	if action_list == null:
		_fail("RANGER_BLEND_UI: bottom HUD class action list is missing")
		return null
	for child in action_list.get_children():
		if child is Button and (child as Button).text == "特调":
			return child as Button
	return null


func _find_blend_button(battle_scene: BattleScene, blend: int, slot: String) -> Button:
	var list := battle_scene.get("_ranger_blend_list") as VBoxContainer
	if list == null:
		return null
	for row in list.get_children():
		if not (row is HBoxContainer):
			continue
		var label := row.get_child(0) as Label
		if label == null or label.text != BattleSurfaceState.label(blend):
			continue
		for child in row.get_children():
			if child is Button and (child as Button).text == ("近战" if slot == "weapon" else "远程"):
				return child as Button
	return null


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_ranger():
			return unit
	return null


func _finish() -> void:
	if _exit_code == 0:
		print("RANGER_BLEND_UI: PASS")
	get_tree().quit(_exit_code)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
