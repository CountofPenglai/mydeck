extends PanelContainer
class_name BattleTurnOrderBar

signal unit_hovered(unit: BattleUnitState)
signal unit_unhovered(unit: BattleUnitState)
signal unit_pressed(unit: BattleUnitState)

const ALLY_COLOR := Color(0.18, 0.78, 0.46, 1.0)
const ENEMY_COLOR := Color(0.84, 0.19, 0.22, 1.0)
const CURRENT_COLOR := Color(1.0, 0.66, 0.18, 1.0)
const ACTED_MODULATE := Color(0.48, 0.48, 0.48, 0.72)

@onready var order_scroll: ScrollContainer = %OrderScroll
@onready var order_list: HBoxContainer = %OrderList
@onready var round_label: Label = %RoundLabel


func bind_round(order: Array[BattleUnitState], current_index: int, round_number: int) -> void:
	_clear_children(order_list)
	round_label.text = "第 %d 轮" % maxi(1, round_number)
	for index in range(order.size()):
		var unit := order[index]
		if unit == null:
			continue
		order_list.add_child(_create_entry(unit, index, current_index))


func set_compact(compact: bool) -> void:
	order_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if compact else ScrollContainer.SCROLL_MODE_DISABLED


func _create_entry(unit: BattleUnitState, index: int, current_index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(66.0, 54.0)
	button.text = unit.get_display_name()
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = "%s\n生命 %d/%d" % [unit.get_display_name(), unit.get_current_health(), unit.get_max_health()]
	button.set_meta("unit", unit)
	button.set_meta("faction", unit.faction)
	button.set_meta("acted", current_index >= 0 and index < current_index)
	button.set_meta("current", index == current_index)
	button.add_theme_font_size_override("font_size", 11)
	var faction_color := ALLY_COLOR if unit.faction == BattleUnitState.Faction.PLAYER else ENEMY_COLOR
	button.add_theme_color_override("font_color", CURRENT_COLOR if index == current_index else faction_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	if current_index >= 0 and index < current_index:
		button.modulate = ACTED_MODULATE
	var portrait := _get_portrait(unit)
	if portrait != null:
		button.icon = portrait
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
	button.mouse_entered.connect(func() -> void: unit_hovered.emit(unit))
	button.mouse_exited.connect(func() -> void: unit_unhovered.emit(unit))
	button.pressed.connect(func() -> void: unit_pressed.emit(unit))
	return button


func _get_portrait(unit: BattleUnitState) -> Texture2D:
	if unit.character_state != null and unit.character_state.character_data != null:
		return unit.character_state.character_data.portrait
	if unit.enemy_state != null and unit.enemy_state.enemy_data != null:
		return unit.enemy_state.enemy_data.portrait
	return null


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
