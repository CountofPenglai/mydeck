extends PopupPanel
class_name BattleEquipmentActionsPopup

signal action_selected(unit: BattleUnitState, effect: EquipmentEffect, action_id: String)

var bound_unit: BattleUnitState
var actions: Array[Dictionary] = []
var _column_count := 2
var _can_activate := Callable()

@onready var title_label: Label = %EquipmentPopupTitle
@onready var action_grid: GridContainer = %EquipmentActionGrid


func set_actions(
	unit: BattleUnitState,
	new_actions: Array,
	can_activate: Callable,
	compact: bool
) -> void:
	bound_unit = unit
	actions.clear()
	for action_value in new_actions:
		if action_value is Dictionary:
			actions.append((action_value as Dictionary).duplicate())
	_can_activate = can_activate
	_column_count = 1 if compact else 2
	action_grid.columns = _column_count
	title_label.text = "%s的装备动作" % (unit.get_display_name() if unit != null else "装备")
	_rebuild_buttons()


func open_above(anchor: Control) -> void:
	if anchor == null or actions.is_empty():
		return
	var rows := ceili(float(actions.size()) / float(maxi(1, _column_count)))
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


func _rebuild_buttons() -> void:
	_clear_children(action_grid)
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


func _select_action(effect: EquipmentEffect, action_id: String) -> void:
	hide()
	action_selected.emit(bound_unit, effect, action_id)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
