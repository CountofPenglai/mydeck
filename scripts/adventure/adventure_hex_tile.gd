extends Control
class_name AdventureHexTile

signal selected(room_id: String)
signal hovered(room_id: String)

const BASE_TEXTURE := preload("res://assets/art/adventure/hex_tiles/parchment_base.png")
const FRONT_TEXTURE := preload("res://assets/art/adventure/hex_tiles/front_placeholder.svg")
const BORDER_TEXTURE := preload("res://assets/art/adventure/hex_tiles/brush_border.png")
const HIGH_VALUE_TEXTURE := preload("res://assets/art/adventure/hex_tiles/symbols/high_value.svg")
const HEX_HEIGHT_RATIO := 0.92
const HEX_WIDTH_RATIO := 0.7967

var room: AdventureRoomState
var presentation: Dictionary = {}
var symbol_texture: Texture2D


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		if room != null:
			hovered.emit(room.room_id)
	)


func bind(value: AdventureRoomState) -> void:
	room = value
	name = "Hex_%s" % room.room_id if room != null else "Hex"
	queue_redraw()


func refresh(value: Dictionary) -> void:
	presentation = value.duplicate(true)
	symbol_texture = load(str(presentation.get("symbol_path", ""))) as Texture2D
	tooltip_text = str(presentation.get("title", ""))
	queue_redraw()


func _has_point(local_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(local_point, _hex_points())


func _gui_input(event: InputEvent) -> void:
	if room == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _has_point(event.position):
		selected.emit(room.room_id)
		accept_event()


func _draw() -> void:
	var hex := _hex_points()
	var fill := Color("#d8c28e") if not bool(presentation.get("revealed", false)) else Color("#6e7b76")
	if bool(presentation.get("completed", false)):
		fill = fill.darkened(0.18)
	draw_colored_polygon(hex, fill)
	if bool(presentation.get("revealed", false)):
		_draw_hex_texture(FRONT_TEXTURE, Color(1.0, 1.0, 1.0, 0.72))
	else:
		_draw_hex_texture(BASE_TEXTURE, Color.WHITE)
	if symbol_texture != null:
		var symbol_rect := Rect2(size * 0.29, size * 0.42)
		draw_texture_rect(symbol_texture, symbol_rect, false, Color("#241f18"))
	if bool(presentation.get("high_value", false)):
		draw_texture_rect(HIGH_VALUE_TEXTURE, Rect2(size * 0.63, size * 0.12), false, Color("#d7a63b"))
	var border_color := Color("#2f2920")
	var border_width := 2.0
	if bool(presentation.get("current", false)):
		border_color = Color("#e4c55c")
		border_width = 4.0
	elif bool(presentation.get("selected", false)):
		border_color = Color("#f0df9c")
		border_width = 4.0
	elif bool(presentation.get("reachable", false)):
		border_color = Color("#4f8b72")
		border_width = 3.0
	draw_polyline(PackedVector2Array(Array(hex) + [hex[0]]), border_color, border_width, true)
	draw_texture_rect(BORDER_TEXTURE, Rect2(Vector2.ZERO, size), false, Color(0.13, 0.1, 0.07, 0.54))


func _hex_points() -> PackedVector2Array:
	var half_width := size.x * HEX_WIDTH_RATIO * 0.5
	var half_height := size.y * HEX_HEIGHT_RATIO * 0.5
	var center := size * 0.5
	return PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, -half_height * 0.5),
		center + Vector2(half_width, half_height * 0.5),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, half_height * 0.5),
		center + Vector2(-half_width, -half_height * 0.5),
	])


func _draw_hex_texture(texture: Texture2D, tint: Color) -> void:
	var colors := PackedColorArray([tint, tint, tint, tint, tint, tint])
	draw_polygon(_hex_points(), colors, PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(1.0, 0.25), Vector2(1.0, 0.75),
		Vector2(0.5, 1.0), Vector2(0.0, 0.75), Vector2(0.0, 0.25),
	]), texture)
