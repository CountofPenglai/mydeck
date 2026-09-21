extends Node
var failures := 0
const OUTPUT := "res://docs/superpowers/reports/hex-overworld"

func _ready() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_diagnostic_visual")
	session.start_new_demo(20260921)
	var packed := load("res://scenes/adventure_map_scene.tscn") as PackedScene
	var scene := packed.instantiate() as AdventureMapScene
	scene.session = session
	add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _capture("map_1280.png", Vector2i(1280, 720), scene)
	# Actual independent nodes, including six-corner hit testing.
	_check(scene.map_view.room_nodes.size() == 48, "48 tile nodes rendered")
	var first := session.current_run.floor_state.get_current_room()
	var tile := scene.map_view.room_nodes[first.room_id] as AdventureHexTile
	_check(not tile._has_point(Vector2.ZERO), "transparent corner rejects mouse")
	_check(tile._has_point(tile.size * 0.5), "tile center accepts mouse")
	var hidden: AdventureRoomState
	for room in session.current_run.floor_state.rooms:
		if room.back_type == AdventureEnums.BackType.MYSTERY and room.room_type == AdventureEnums.RoomType.SHOP:
			hidden = room
			break
	scene.selected_room_id = hidden.room_id
	scene._refresh()
	_check(not scene.detail_body.text.contains("商店") and not scene.detail_title.text.contains("商店"), "hidden shop detail cannot leak actual type")
	await _capture("map_narrow.png", Vector2i(900, 720), scene)
	session.current_run.floor_index = 1
	session.current_run.floor_state = AdventureMapGenerator.new().generate(777, 1)
	AdventureShopService.initialize_map(session.current_run)
	var floor := session.current_run.floor_state
	floor.danger = 17
	for room in floor.rooms:
		if room.room_type == AdventureEnums.RoomType.EVENT and room.content_id == "hermit_house":
			room.content_revealed = true
			scene.selected_room_id = room.room_id
			break
	scene._refresh()
	_check(scene.detail_body.text.contains("预计进入时危险 18") and scene.detail_body.text.contains("HP"), "scouted danger18 event exposes its battle forecast")
	await _capture("map_chapter2_scout.png", Vector2i(1280, 720), scene)
	floor.danger = 11
	for room in floor.rooms:
		if room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
			room.content_revealed = true
			scene.selected_room_id = room.room_id
			break
	scene._refresh()
	_check(scene.detail_body.text.contains("HP") and scene.detail_body.text.contains("20%"), "scouted combat shows health and danger damage")
	await _capture("map_danger_preview.png", Vector2i(1280, 720), scene)
	scene.free()
	session.save_store.delete_save()
	session.free()
	print("HEX_VISUAL: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String, window_size: Vector2i, scene: Control) -> void:
	get_window().size = window_size
	get_window().content_scale_size = window_size
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT.path_join(filename))
	_check(error == OK, "screenshot saved: " + filename)
	_check(scene.map_view.size.x > 0 and scene.map_view.size.y > 0, "map retains usable region")
	_check(scene.detail_body.get_global_rect().end.x <= float(window_size.x), "detail pane fits window")
	_check(scene.enemy_health_spin_box.get_global_rect().end.y <= float(window_size.y), "footer remains fully visible")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("HEX_VISUAL: " + label)
