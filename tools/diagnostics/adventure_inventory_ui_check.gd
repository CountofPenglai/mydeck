extends Node

var exit_code := 0


func _ready() -> void:
	var scene := load("res://scenes/adventure_map_scene.tscn") as PackedScene
	if scene == null:
		_fail("INVENTORY_UI_DIAG: adventure map scene missing")
		get_tree().quit(exit_code)
		return
	var map_scene := scene.instantiate() as AdventureMapScene
	add_child(map_scene)
	await get_tree().process_frame
	if map_scene.run_state == null or map_scene.run_state.party.is_empty():
		_fail("INVENTORY_UI_DIAG: adventure party missing")
		get_tree().quit(exit_code)
		return
	var hero := map_scene.run_state.party[0]
	map_scene._show_inventory(hero.adventure_character_id)
	await get_tree().process_frame
	if not map_scene.modal_layer.visible:
		_fail("INVENTORY_UI_DIAG: inventory modal did not open")
	if map_scene.modal_title.text.find("装备与背包") < 0:
		_fail("INVENTORY_UI_DIAG: inventory modal title missing")
	if map_scene.modal_body.get_child_count() < 8:
		_fail("INVENTORY_UI_DIAG: inventory modal content incomplete")
	if map_scene.enemy_health_spin_box == null:
		_fail("INVENTORY_UI_DIAG: enemy health test control missing")
	elif int(map_scene.enemy_health_spin_box.value) != map_scene.run_state.enemy_health_percent \
			or int(map_scene.enemy_health_spin_box.min_value) != 1 \
			or int(map_scene.enemy_health_spin_box.max_value) != 1000:
		_fail("INVENTORY_UI_DIAG: enemy health test control is out of sync")
	print("INVENTORY_UI_DIAG: completed")
	get_tree().quit(exit_code)


func _fail(message: String) -> void:
	exit_code = 1
	push_error(message)
	print("ERROR: " + message)
