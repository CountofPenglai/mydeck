extends Control
class_name AdventureMapView

signal room_selected(room_id: String)
signal room_hovered(room_id: String)

const ROOM_SIZE := Vector2(54.0, 54.0)
const MAP_PADDING := Vector2(54.0, 42.0)

var floor_state: AdventureFloorState
var selected_room_id: String = ""
var room_buttons: Dictionary = {}


func _ready() -> void:
	resized.connect(_layout_rooms)
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


func set_floor_state(value: AdventureFloorState) -> void:
	floor_state = value
	selected_room_id = floor_state.current_room_id if floor_state != null else ""
	_rebuild_rooms()


func set_selected_room(room_id: String) -> void:
	selected_room_id = room_id
	_refresh_button_styles()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#c7b78f"))
	for x in range(0, int(size.x), 48):
		draw_line(Vector2(x, 0), Vector2(x + 72, size.y), Color(0.24, 0.20, 0.14, 0.035), 1.0)
	if floor_state == null:
		return
	var drawn_edges := {}
	for room in floor_state.rooms:
		if room == null:
			continue
		for neighbor_id in room.neighbor_ids:
			var edge_key := [room.room_id, neighbor_id]
			edge_key.sort()
			var key := "%s:%s" % edge_key
			if drawn_edges.has(key):
				continue
			drawn_edges[key] = true
			var neighbor := floor_state.get_room(neighbor_id)
			if neighbor == null:
				continue
			var color := Color("#675f51")
			if room.completed and neighbor.completed:
				color = Color("#526656")
			draw_line(_room_center(room), _room_center(neighbor), color, 5.0, true)
			draw_line(_room_center(room), _room_center(neighbor), Color("#b9aa83"), 1.5, true)


func _rebuild_rooms() -> void:
	for child in get_children():
		child.queue_free()
	room_buttons.clear()
	if floor_state == null:
		queue_redraw()
		return
	for room in floor_state.rooms:
		if room == null:
			continue
		var button := Button.new()
		button.name = "Room_%s" % room.room_id
		button.custom_minimum_size = ROOM_SIZE
		button.size = ROOM_SIZE
		button.text = AdventureEnums.room_symbol(room.room_type)
		button.tooltip_text = room.get_display_name()
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_entered.connect(_on_room_hovered.bind(room.room_id))
		button.mouse_exited.connect(_on_room_unhovered)
		button.pressed.connect(_on_room_pressed.bind(room.room_id))
		add_child(button)
		room_buttons[room.room_id] = button
	_layout_rooms()
	_refresh_button_styles()
	queue_redraw()


func _layout_rooms() -> void:
	if floor_state == null:
		return
	for room in floor_state.rooms:
		var button := room_buttons.get(room.room_id) as Button
		if button != null:
			button.position = _room_center(room) - ROOM_SIZE * 0.5
	queue_redraw()


func _room_center(room: AdventureRoomState) -> Vector2:
	var available := Vector2(maxf(1.0, size.x - MAP_PADDING.x * 2.0), maxf(1.0, size.y - MAP_PADDING.y * 2.0))
	var x_ratio := float(room.cell.x) / float(maxi(1, floor_state.grid_size.x - 1))
	var y_ratio := float(room.cell.y) / float(maxi(1, floor_state.grid_size.y - 1))
	return MAP_PADDING + Vector2(x_ratio * available.x, y_ratio * available.y)


func _refresh_button_styles() -> void:
	if floor_state == null:
		return
	var current := floor_state.get_current_room()
	for room in floor_state.rooms:
		var button := room_buttons.get(room.room_id) as Button
		if button == null:
			continue
		var fill := _room_color(room.room_type)
		var border := Color("#39352f")
		var width := 2
		if room.room_id == floor_state.current_room_id:
			fill = Color("#d2bd68")
			border = Color("#3e321f")
			width = 4
		elif room.room_id == selected_room_id:
			border = Color("#f1df9a")
			width = 4
		elif current != null and current.neighbor_ids.has(room.room_id):
			border = Color("#477f68")
			width = 3
		elif room.completed:
			fill = fill.darkened(0.22)
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = fill
		normal_style.border_color = border
		normal_style.set_border_width_all(width)
		normal_style.corner_radius_top_left = 3
		normal_style.corner_radius_top_right = 3
		normal_style.corner_radius_bottom_left = 3
		normal_style.corner_radius_bottom_right = 3
		var hover_style := normal_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = fill.lightened(0.14)
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", hover_style)
		button.add_theme_color_override("font_color", Color("#f4ead2"))
		button.add_theme_font_size_override("font_size", 19)


func _room_color(room_type: int) -> Color:
	match room_type:
		AdventureEnums.RoomType.START:
			return Color("#425b61")
		AdventureEnums.RoomType.NORMAL_BATTLE:
			return Color("#70463f")
		AdventureEnums.RoomType.ELITE_BATTLE:
			return Color("#8b302f")
		AdventureEnums.RoomType.BOSS_BATTLE:
			return Color("#4f2025")
		AdventureEnums.RoomType.SHELTER:
			return Color("#45624d")
		AdventureEnums.RoomType.SHOP:
			return Color("#88713d")
		_:
			return Color("#505d72")


func _on_room_hovered(room_id: String) -> void:
	room_hovered.emit(room_id)


func _on_room_unhovered() -> void:
	room_hovered.emit(selected_room_id)


func _on_room_pressed(room_id: String) -> void:
	set_selected_room(room_id)
	room_selected.emit(room_id)
