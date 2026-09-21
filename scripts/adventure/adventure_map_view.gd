extends Control
class_name AdventureMapView

signal room_selected(room_id: String)
signal room_hovered(room_id: String)

const TILE_SCENE := preload("res://scenes/adventure/adventure_hex_tile.tscn")
const MAP_PADDING := 24.0

var floor_state: AdventureFloorState
var selected_room_id: String = ""
var room_nodes: Dictionary = {}


func _ready() -> void:
	resized.connect(_layout_rooms)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_floor_state(value: AdventureFloorState) -> void:
	floor_state = value
	if floor_state == null:
		_clear_stale_nodes({})
		return
	if selected_room_id.is_empty() or floor_state.get_room(selected_room_id) == null:
		selected_room_id = floor_state.current_room_id
	_sync_room_nodes()


func set_selected_room(room_id: String) -> void:
	selected_room_id = room_id
	_refresh_presentations()


func _sync_room_nodes() -> void:
	var active := {}
	for room in floor_state.rooms:
		if room == null:
			continue
		active[room.room_id] = true
		var tile := room_nodes.get(room.room_id) as AdventureHexTile
		if tile == null:
			tile = TILE_SCENE.instantiate() as AdventureHexTile
			tile.bind(room)
			tile.selected.connect(_on_tile_selected)
			tile.hovered.connect(func(room_id: String) -> void: room_hovered.emit(room_id))
			tile.mouse_exited.connect(func() -> void: room_hovered.emit(""))
			add_child(tile)
			room_nodes[room.room_id] = tile
		else:
			tile.bind(room)
	_clear_stale_nodes(active)
	_layout_rooms()
	_refresh_presentations()


func _clear_stale_nodes(active: Dictionary) -> void:
	for room_id in room_nodes.keys():
		if active.has(room_id):
			continue
		var node := room_nodes[room_id] as Node
		if node != null:
			node.queue_free()
		room_nodes.erase(room_id)


func _layout_rooms() -> void:
	if floor_state == null or floor_state.grid_size.x <= 0 or floor_state.grid_size.y <= 0:
		return
	var side := _tile_side()
	var hex_width := side * AdventureHexTile.HEX_WIDTH_RATIO
	var hex_height := side * AdventureHexTile.HEX_HEIGHT_RATIO
	for room in floor_state.rooms:
		var tile := room_nodes.get(room.room_id) as AdventureHexTile
		if tile == null:
			continue
		tile.size = Vector2(side, side)
		var center := Vector2(
			MAP_PADDING + hex_width * (float(room.cell.x) + 0.5 * float(room.cell.y & 1)) + side * 0.5,
			MAP_PADDING + hex_height * 0.75 * float(room.cell.y) + side * 0.5
		)
		tile.position = center - tile.size * 0.5


func _tile_side() -> float:
	var columns := float(maxi(1, floor_state.grid_size.x))
	var rows := float(maxi(1, floor_state.grid_size.y))
	var horizontal := maxf(36.0, (size.x - MAP_PADDING * 2.0) / (columns * AdventureHexTile.HEX_WIDTH_RATIO + 0.5))
	var vertical := maxf(36.0, (size.y - MAP_PADDING * 2.0) / (maxf(1.0, (rows - 1.0) * AdventureHexTile.HEX_HEIGHT_RATIO * 0.75 + 1.0)))
	return minf(horizontal, vertical)


func _refresh_presentations() -> void:
	if floor_state == null:
		return
	for room in floor_state.rooms:
		var tile := room_nodes.get(room.room_id) as AdventureHexTile
		if tile != null:
			tile.refresh(AdventureMapPresentation.for_room(floor_state, room, selected_room_id))


func _on_tile_selected(room_id: String) -> void:
	set_selected_room(room_id)
	room_selected.emit(room_id)
