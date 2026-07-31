extends Control
class_name BattleHudRoot

signal layout_changed(safe_rect: Rect2)
signal deployment_unit_selected(unit: BattleUnitState)
signal start_battle_pressed

const COMPACT_WIDTH := 1100.0
const WIDE_WIDTH := 1600.0
const BOTTOM_HEIGHT_RATIO := 0.26
const BOTTOM_MIN_HEIGHT := 176.0
const BOTTOM_MAX_HEIGHT := 196.0
const WIDE_BOTTOM_MAX_WIDTH := 1560.0
const MAP_HORIZONTAL_INSET := 24.0
const MAP_VERTICAL_SHIFT_RATIO := 0.42
const VITALS_OVERFLOW_HEIGHT := 36.0

var battle_scene: BattleScene
var controller: BattleController
var _compact_mode := false
var _equipment_column_count := 2
var _equipment_actions: Array[Dictionary] = []
var _equipment_action_unit: BattleUnitState
var _message_serial := 0

@onready var turn_order_bar: Control = %TurnOrderBar
@onready var deployment_panel: Control = %DeploymentPanel
@onready var detail_panel: Control = %BattleDetailPanel
@onready var bottom_hud: Control = %BattleBottomHud
@onready var menu_button: Button = %MenuButton
@onready var equipment_region: Control = bottom_hud.get_node("%EquipmentRegion")
@onready var deploy_list: VBoxContainer = %DeployList
@onready var start_battle_button: Button = %StartBattleButton
@onready var equipment_popup: PopupPanel = %EquipmentActionsPopup
@onready var battle_message_panel: PanelContainer = %BattleMessagePanel
@onready var battle_message_label: Label = %BattleMessageLabel


func _ready() -> void:
	resized.connect(_apply_responsive_layout)
	start_battle_button.pressed.connect(func() -> void: start_battle_pressed.emit())
	call_deferred("_apply_responsive_layout")


func bind_battle(scene: BattleScene, battle_controller: BattleController) -> void:
	battle_scene = scene
	controller = battle_controller
	if not deployment_unit_selected.is_connected(scene._select_deploy_unit):
		deployment_unit_selected.connect(scene._select_deploy_unit)
	if not start_battle_pressed.is_connected(scene._on_start_pressed):
		start_battle_pressed.connect(scene._on_start_pressed)
	if not menu_button.pressed.is_connected(scene._open_battle_menu):
		menu_button.pressed.connect(scene._open_battle_menu)
	_connect_bottom_hud(scene)
	_connect_turn_order()
	if not equipment_popup.is_connected("action_selected", _on_equipment_action_selected):
		equipment_popup.connect("action_selected", _on_equipment_action_selected)
	if not detail_panel.is_connected("lock_changed", _on_detail_lock_changed):
		detail_panel.connect("lock_changed", _on_detail_lock_changed)
	refresh_view()


func refresh_view() -> void:
	if not is_node_ready():
		return
	_refresh_deployment()
	_refresh_turn_order()
	_refresh_bottom_hud()
	_apply_responsive_layout()


func is_compact_mode() -> bool:
	return _compact_mode


func get_equipment_column_count() -> int:
	return _equipment_column_count


func focus_menu_button() -> void:
	menu_button.grab_focus()


func append_log_message(message: String) -> void:
	if message.is_empty():
		return
	_message_serial += 1
	var serial := _message_serial
	battle_message_label.text = message
	battle_message_panel.visible = true
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and serial == _message_serial:
		battle_message_panel.visible = false


func get_battle_safe_rect() -> Rect2:
	if not is_node_ready():
		return Rect2(Vector2.ZERO, size)
	var vertical_shift := bottom_hud.size.y * MAP_VERTICAL_SHIFT_RATIO
	return Rect2(
		Vector2(MAP_HORIZONTAL_INSET, -vertical_shift),
		Vector2(
			maxf(1.0, size.x - MAP_HORIZONTAL_INSET * 2.0),
			size.y
		)
	)


func clear_detail_inspection() -> void:
	equipment_popup.call("close")
	detail_panel.call("clear_preview")
	detail_panel.call("clear_lock")
	_apply_responsive_layout()


func preview_unit(unit: BattleUnitState, lock: bool = false) -> void:
	detail_panel.call("preview_unit", unit)
	if lock:
		detail_panel.call("lock_current")
	_apply_responsive_layout()


func preview_object(object_state: BattleObjectState, lock: bool = false) -> void:
	detail_panel.call("preview_object", object_state)
	if lock:
		detail_panel.call("lock_current")
	_apply_responsive_layout()


func preview_terrain(cell: Vector2i, detail_text: String) -> void:
	detail_panel.call("preview_terrain", cell, detail_text)
	_apply_responsive_layout()


func clear_detail_preview() -> void:
	detail_panel.call("clear_preview")
	_apply_responsive_layout()


func _refresh_deployment() -> void:
	_clear_children(deploy_list)
	if controller == null:
		deployment_panel.visible = false
		return
	deployment_panel.visible = controller.phase == BattleController.Phase.DEPLOYMENT
	if not deployment_panel.visible:
		return
	var selected_unit: BattleUnitState = null
	if battle_scene != null:
		selected_unit = battle_scene.selected_deploy_unit
	for unit in controller.player_units:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 34.0)
		button.text = "%s  %s" % [unit.get_display_name(), "已部署" if unit.is_deployed else "待部署"]
		button.disabled = controller.is_resolving_actions()
		button.button_pressed = unit == selected_unit
		button.toggle_mode = true
		button.pressed.connect(func() -> void: deployment_unit_selected.emit(unit))
		deploy_list.add_child(button)
	start_battle_button.disabled = controller.is_resolving_actions() or not controller.can_start_battle()


func _refresh_turn_order() -> void:
	if controller == null:
		turn_order_bar.call("bind_round", [], -1, 0)
		return
	turn_order_bar.call("set_compact", _compact_mode)
	turn_order_bar.call("bind_round", controller.turn_order, controller.current_turn_index, controller.battle_round)


func _refresh_bottom_hud() -> void:
	if controller == null:
		bottom_hud.call("bind_unit", null, null, false)
		bottom_hud.call("bind_hand", [], [], false)
		return
	var display_unit := _get_display_unit()
	var interactive := controller.phase == BattleController.Phase.BATTLE \
		and controller.turn_flow_state == BattleController.TurnFlowState.ACTIVE \
		and display_unit != null \
		and display_unit == controller.current_unit \
		and display_unit.faction == BattleUnitState.Faction.PLAYER \
		and not controller.is_resolving_actions()
	bottom_hud.call("bind_unit", display_unit, controller, interactive)
	_refresh_equipment_actions(display_unit)
	var cards: Array[CardData] = []
	var costs: Array[int] = []
	if interactive:
		cards = display_unit.hand
		for card in cards:
			costs.append(controller.get_card_ap_cost(display_unit, card, {
				"controller": controller,
				"user": display_unit,
				"card": card,
			}))
	bottom_hud.call("bind_hand", cards, costs, interactive)


func _get_display_unit() -> BattleUnitState:
	if controller == null:
		return null
	if controller.phase == BattleController.Phase.BATTLE and controller.current_unit != null:
		return controller.current_unit
	if battle_scene != null and battle_scene.selected_deploy_unit != null:
		return battle_scene.selected_deploy_unit
	if not controller.player_units.is_empty():
		return controller.player_units[0]
	return null


func _connect_bottom_hud(scene: BattleScene) -> void:
	var bindings := {
		"move_pressed": Callable(scene, "_on_move_pressed"),
		"end_turn_pressed": Callable(scene, "_on_end_turn_pressed"),
		"deck_pressed": Callable(scene, "_on_deck_pressed"),
		"discard_pressed": Callable(scene, "_on_discard_pressed"),
		"curse_pressed": Callable(scene, "_show_curse_popup"),
		"enchant_pressed": Callable(scene, "_on_discard_pressed"),
	}
	for signal_name in bindings:
		var callable: Callable = bindings[signal_name]
		if not bottom_hud.is_connected(signal_name, callable):
			bottom_hud.connect(signal_name, callable)
	if not bottom_hud.is_connected("card_pressed", _on_card_pressed):
		bottom_hud.connect("card_pressed", _on_card_pressed)
	if not bottom_hud.is_connected("card_hovered", _on_card_hovered):
		bottom_hud.connect("card_hovered", _on_card_hovered)
	if not bottom_hud.is_connected("card_unhovered", _on_card_unhovered):
		bottom_hud.connect("card_unhovered", _on_card_unhovered)
	if not bottom_hud.is_connected("equipment_pressed", _on_equipment_pressed):
		bottom_hud.connect("equipment_pressed", _on_equipment_pressed)
	if not bottom_hud.is_connected("class_action_pressed", _on_class_action_pressed):
		bottom_hud.connect("class_action_pressed", _on_class_action_pressed)


func _connect_turn_order() -> void:
	if not turn_order_bar.is_connected("unit_hovered", _on_unit_hovered):
		turn_order_bar.connect("unit_hovered", _on_unit_hovered)
	if not turn_order_bar.is_connected("unit_unhovered", _on_unit_unhovered):
		turn_order_bar.connect("unit_unhovered", _on_unit_unhovered)
	if not turn_order_bar.is_connected("unit_pressed", _on_unit_pressed):
		turn_order_bar.connect("unit_pressed", _on_unit_pressed)


func _on_card_hovered(card: CardData) -> void:
	detail_panel.call("preview_card", card, {"user": _get_display_unit()})


func _on_card_unhovered(_card: CardData) -> void:
	detail_panel.call("clear_preview")


func _on_card_pressed(card: CardData) -> void:
	detail_panel.call("preview_card", card, {"user": _get_display_unit()})
	detail_panel.call("lock_current")
	if battle_scene != null:
		battle_scene._select_card(card)


func _on_unit_hovered(unit: BattleUnitState) -> void:
	detail_panel.call("preview_unit", unit)


func _on_unit_unhovered(_unit: BattleUnitState) -> void:
	detail_panel.call("clear_preview")


func _on_unit_pressed(unit: BattleUnitState) -> void:
	equipment_popup.call("close")
	detail_panel.call("preview_unit", unit)
	detail_panel.call("lock_current")


func _refresh_equipment_actions(unit: BattleUnitState) -> void:
	if unit != _equipment_action_unit:
		equipment_popup.call("close")
	_equipment_action_unit = unit
	_equipment_actions.clear()
	if unit == null:
		bottom_hud.call("set_equipment_actions", 0)
		return
	var phase_name := "deployment" if controller.phase == BattleController.Phase.DEPLOYMENT else "battle"
	_equipment_actions = unit.get_equipment_actions({"controller": controller, "unit": unit, "phase": phase_name})
	if _equipment_actions.size() == 1:
		var action := _equipment_actions[0]
		var effect := action.get("effect") as EquipmentEffect
		var action_id := str(action.get("action_id", "default"))
		bottom_hud.call(
			"set_equipment_actions",
			1,
			str(action.get("label", "装备动作")),
			controller.can_activate_equipment_action(unit, effect, action_id)
		)
	else:
		bottom_hud.call("set_equipment_actions", _equipment_actions.size())


func _on_equipment_pressed() -> void:
	if _equipment_action_unit == null:
		return
	if _equipment_actions.size() == 1:
		var action := _equipment_actions[0]
		_on_equipment_action_selected(
			_equipment_action_unit,
			action.get("effect") as EquipmentEffect,
			str(action.get("action_id", "default"))
		)
		return
	if _equipment_actions.size() > 1:
		if bool(equipment_popup.call("is_open")):
			equipment_popup.call("close")
			return
		equipment_popup.call("set_actions", _equipment_action_unit, _equipment_actions, _can_activate_equipment_action, _compact_mode)
		equipment_popup.call("open_above", equipment_region)
		return
	var equipment := _get_primary_equipment(_equipment_action_unit)
	if equipment != null:
		detail_panel.call("preview_equipment", equipment, _equipment_action_unit)
		detail_panel.call("lock_current")


func _can_activate_equipment_action(unit: BattleUnitState, effect: EquipmentEffect, action_id: String) -> bool:
	return controller != null and controller.can_activate_equipment_action(unit, effect, action_id)


func _on_equipment_action_selected(unit: BattleUnitState, effect: EquipmentEffect, action_id: String) -> void:
	equipment_popup.call("close")
	if battle_scene != null:
		battle_scene._on_equipment_action_pressed(unit, effect, action_id)


func _on_class_action_pressed(action_id: StringName, unit: BattleUnitState) -> void:
	if battle_scene == null:
		return
	match action_id:
		&"druid_transform":
			battle_scene._on_druid_prepare_transform_pressed(unit)
		&"druid_untransform":
			battle_scene._on_druid_prepare_untransform_pressed(unit)
		&"ranger_blend":
			battle_scene._show_ranger_blend_popup(unit)


func _on_detail_lock_changed(_locked: bool) -> void:
	equipment_popup.call("close")


func _get_primary_equipment(unit: BattleUnitState) -> EquipmentData:
	if unit.character_state != null:
		return unit.character_state.weapon_equipment
	if unit.enemy_state != null:
		return unit.enemy_state.get_active_weapon()
	return null


func _apply_responsive_layout() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	_compact_mode = size.x < COMPACT_WIDTH
	_equipment_column_count = 1 if _compact_mode else 2
	turn_order_bar.call("set_compact", _compact_mode)
	bottom_hud.call("set_compact", _compact_mode)

	var bottom_height := clampf(size.y * BOTTOM_HEIGHT_RATIO, BOTTOM_MIN_HEIGHT, BOTTOM_MAX_HEIGHT)
	var bottom_width := size.x - 32.0
	if size.x > WIDE_WIDTH:
		bottom_width = minf(WIDE_BOTTOM_MAX_WIDTH, size.x - 64.0)
	bottom_hud.position = Vector2((size.x - bottom_width) * 0.5, size.y - bottom_height)
	bottom_hud.size = Vector2(bottom_width, bottom_height)

	menu_button.position = Vector2(14.0, 14.0)
	menu_button.size = Vector2(64.0, 64.0)
	deployment_panel.position = Vector2(14.0, 86.0)
	deployment_panel.size = Vector2(196.0 if not _compact_mode else 176.0, minf(226.0, bottom_hud.position.y - 102.0))

	var turn_width := minf(590.0, maxf(300.0, size.x * 0.42))
	turn_order_bar.position = Vector2((size.x - turn_width) * 0.5, 12.0)
	turn_order_bar.size = Vector2(turn_width, 68.0)

	var message_width := minf(560.0, size.x - 48.0)
	battle_message_panel.position = Vector2(
		(size.x - message_width) * 0.5,
		bottom_hud.position.y - VITALS_OVERFLOW_HEIGHT - 48.0
	)
	battle_message_panel.size = Vector2(message_width, 38.0)

	var detail_width := 260.0 if _compact_mode else clampf(size.x * 0.19, 260.0, 300.0)
	detail_panel.size = Vector2(detail_width, minf(420.0, bottom_hud.position.y - 28.0))
	detail_panel.position = Vector2(size.x - detail_width - 16.0, 16.0 if not _compact_mode else maxf(96.0, bottom_hud.position.y - detail_panel.size.y - 12.0))
	detail_panel.z_index = 30 if _compact_mode else 10

	layout_changed.emit(get_battle_safe_rect())


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
