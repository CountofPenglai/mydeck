extends Node

var failures := 0


func _ready() -> void:
	var definition := AdventureDefinition.new()
	definition.min_rooms = 48
	definition.max_rooms = 48
	var floor := AdventureMapGenerator.new().generate(20260921, 0, definition)
	var view := AdventureMapView.new()
	view.size = Vector2(960.0, 540.0)
	add_child(view)
	view.set_floor_state(floor)
	var room := floor.rooms[0]
	var tile := view.room_nodes.get(room.room_id) as AdventureHexTile
	_check(tile != null, "map view must create an independent hex tile for every room")
	view.set_floor_state(floor)
	_check(view.room_nodes.get(room.room_id) == tile, "refresh must retain each room tile node identity")
	_check(view.room_nodes.size() == floor.rooms.size(), "map view must contain one tile per room")
	if tile != null:
		_check(not tile._has_point(Vector2.ZERO), "transparent tile corners must not be clickable")
		_check(tile._has_point(tile.size * 0.5), "hex center must be clickable")
	var hidden_shop := _hidden_shop(floor)
	var hidden_tile := view.room_nodes.get(hidden_shop.room_id) as AdventureHexTile
	_check(hidden_tile != null and int(hidden_tile.presentation.get("back_type", -1)) == AdventureEnums.BackType.MYSTERY, "unrevealed hidden shop must present only as a mystery back")
	_check(hidden_tile != null and not bool(hidden_tile.presentation.get("revealed", true)), "unrevealed hidden shop must not expose a front presentation")
	hidden_shop.high_value_marked = true
	view.set_floor_state(floor)
	_check(bool(hidden_tile.presentation.get("high_value", false)), "earned marker appears on the back")
	hidden_shop.content_revealed = true
	view.set_floor_state(floor)
	_check(not bool(hidden_tile.presentation.get("high_value", false)), "revealing a marked tile removes its back-only overlay")
	_check(hidden_shop.high_value_marked, "revealing does not erase the persisted threshold record")
	_check_hover_exit_restores_selection()
	print("ADVENTURE_HEX_TILE_UI_CHECK: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_hover_exit_restores_selection() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_review_hover_ui")
	session.start_new_demo(20260921)
	var scene := (load("res://scenes/adventure_map_scene.tscn") as PackedScene).instantiate() as AdventureMapScene
	scene.session = session
	add_child(scene)
	var floor := session.current_run.floor_state
	var target := floor.get_adjacent_rooms(floor.current_room_id)[0]
	scene._on_room_selected(target.room_id)
	var selected_body := scene.detail_body.text
	_check(scene.action_list.get_child_count() > 0, "reachable selected tile offers movement")
	var hovered_tile := scene.map_view.room_nodes[floor.current_room_id] as AdventureHexTile
	hovered_tile.mouse_entered.emit()
	_check(scene.detail_body.text != selected_body, "hover previews another tile")
	hovered_tile.mouse_exited.emit()
	_check(scene.detail_body.text == selected_body, "exiting hover restores selected tile details")
	_check(scene.action_list.get_child_count() > 0, "exiting hover restores selected tile actions")
	scene.free()
	session.save_store.delete_save()
	session.free()


func _hidden_shop(floor: AdventureFloorState) -> AdventureRoomState:
	for room in floor.rooms:
		if room.back_type == AdventureEnums.BackType.MYSTERY and room.room_type == AdventureEnums.RoomType.SHOP:
			return room
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("ADVENTURE_HEX_TILE_UI_CHECK: %s" % message)
