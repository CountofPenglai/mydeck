extends PopupPanel
class_name BattleEquipmentActionsPopup

signal action_selected(unit: BattleUnitState, effect: EquipmentEffect, action_id: String)
signal detail_selected(equipment: EquipmentData, unit: BattleUnitState)

var bound_unit: BattleUnitState
var actions: Array[Dictionary] = []
var _column_count := 2
var _can_activate := Callable()
var _show_weapon_details := false

@onready var title_label: Label = %EquipmentPopupTitle
@onready var action_grid: GridContainer = %EquipmentActionGrid


func set_actions(
	unit: BattleUnitState,
	new_actions: Array,
	can_activate: Callable,
	compact: bool,
	show_weapon_details: bool = false
) -> void:
	bound_unit = unit
	actions.clear()
	for action_value in new_actions:
		if action_value is Dictionary:
			actions.append((action_value as Dictionary).duplicate())
	_can_activate = can_activate
	_show_weapon_details = show_weapon_details
	_column_count = 1 if compact else 2
	action_grid.columns = _column_count
	title_label.text = "%s的装备动作" % (unit.get_display_name() if unit != null else "装备")
	_rebuild_buttons()


func open_above(anchor: Control) -> void:
	var entry_count := actions.size() + _get_detail_entry_count()
	if anchor == null or entry_count <= 0:
		return
	var rows := ceili(float(entry_count) / float(maxi(1, _column_count)))
	var popup_size := Vector2i(250 if _column_count == 1 else 480, 54 + rows * 44)
	size = popup_size
	var anchor_rect := anchor.get_global_rect()
	position = Vector2i(
		roundi(anchor_rect.get_center().x - float(popup_size.x) * 0.5),
		roundi(anchor_rect.position.y - float(popup_size.y) - 8.0)
	)
	popup()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


func get_column_count() -> int:
	return _column_count


func get_action_count() -> int:
	return actions.size()


func get_detail_entry_count() -> int:
	return _get_detail_entry_count()


func _rebuild_buttons() -> void:
	_clear_children(action_grid)
	if _show_weapon_details and bound_unit != null and bound_unit.character_state != null:
		_add_detail_button("当前", bound_unit.character_state.weapon_equipment)
		_add_detail_button("备战", bound_unit.character_state.reserve_weapon_equipment)
	for action in actions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(222.0 if _column_count == 2 else 226.0, 38.0)
		button.text = str(action.get("label", "装备动作"))
		button.tooltip_text = str(action.get("description", button.text))
		var effect := action.get("effect") as EquipmentEffect
		var action_id := str(action.get("action_id", "default"))
		button.disabled = _can_activate.is_valid() and not bool(_can_activate.call(bound_unit, effect, action_id))
		button.pressed.connect(_select_action.bind(effect, action_id))
		action_grid.add_child(button)


func _add_detail_button(slot_label: String, equipment: EquipmentData) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(222.0 if _column_count == 2 else 226.0, 38.0)
	button.text = "%s详情：%s" % [slot_label, equipment.item_name if equipment != null else "无"]
	button.tooltip_text = "查看%s武器的完整信息" % slot_label
	button.disabled = equipment == null
	button.pressed.connect(_select_detail.bind(equipment))
	action_grid.add_child(button)


func _select_detail(equipment: EquipmentData) -> void:
	hide()
	detail_selected.emit(equipment, bound_unit)


func _get_detail_entry_count() -> int:
	if not _show_weapon_details or bound_unit == null or bound_unit.character_state == null:
		return 0
	return 2


func _select_action(effect: EquipmentEffect, action_id: String) -> void:
	hide()
	action_selected.emit(bound_unit, effect, action_id)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
