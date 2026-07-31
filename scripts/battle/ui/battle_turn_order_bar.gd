extends PanelContainer
class_name BattleTurnOrderBar

signal unit_hovered(unit: BattleUnitState)
signal unit_unhovered(unit: BattleUnitState)
signal unit_pressed(unit: BattleUnitState)

const ALLY_COLOR := Color(0.18, 0.78, 0.46, 1.0)
const ENEMY_COLOR := Color(0.84, 0.19, 0.22, 1.0)
const CURRENT_COLOR := Color(1.0, 0.66, 0.18, 1.0)
const ACTED_MODULATE := Color(0.48, 0.48, 0.48, 0.72)
const CURRENT_FRAME := preload("res://assets/art/ui/battle_hud/current_unit_ring.png")
const ALLY_FRAME := preload("res://assets/art/ui/battle_hud/turn_ally_frame.png")
const ENEMY_FRAME := preload("res://assets/art/ui/battle_hud/turn_enemy_frame.png")

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
	button.custom_minimum_size = Vector2(68.0, 62.0)
	button.text = ""
	button.tooltip_text = "%s\n生命 %d/%d" % [unit.get_display_name(), unit.get_current_health(), unit.get_max_health()]
	button.set_meta("unit", unit)
	button.set_meta("faction", unit.faction)
	button.set_meta("acted", current_index >= 0 and index < current_index)
	button.set_meta("current", index == current_index)
	var faction_color := ALLY_COLOR if unit.faction == BattleUnitState.Faction.PLAYER else ENEMY_COLOR
	if current_index >= 0 and index < current_index:
		button.modulate = ACTED_MODULATE
	var portrait := _get_portrait(unit)
	var portrait_rect := TextureRect.new()
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_rect.offset_left = 13.0
	portrait_rect.offset_top = 7.0
	portrait_rect.offset_right = -13.0
	portrait_rect.offset_bottom = -13.0
	portrait_rect.texture = portrait
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait_rect)

	var frame_rect := TextureRect.new()
	frame_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame_rect.texture = CURRENT_FRAME if index == current_index else (ALLY_FRAME if unit.faction == BattleUnitState.Faction.PLAYER else ENEMY_FRAME)
	frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(frame_rect)
	button.set_meta("frame_texture_bound", frame_rect.texture != null)

	var name_label := Label.new()
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -17.0
	name_label.offset_bottom = 0.0
	name_label.text = unit.get_display_name()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", CURRENT_COLOR if index == current_index else faction_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)
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
