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
	var detail_button := _find_button(map_scene.modal_body, "详情")
	if detail_button == null:
		_fail("INVENTORY_UI_DIAG: equipment detail button missing")
	else:
		detail_button.pressed.emit()
		await get_tree().process_frame
		if map_scene.modal_title.text != hero.weapon_equipment.item_name \
				or not _labels_contain(map_scene.modal_body, "基础伤害"):
			_fail("INVENTORY_UI_DIAG: equipment detail view omitted combat fields")
	if not map_scene._camp_activity_description("ranger_dig").contains("第三次"):
		_fail("INVENTORY_UI_DIAG: camp activity description is incomplete")
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


func _find_button(root: Node, fragment: String) -> Button:
	if root is Button and (root as Button).text.contains(fragment):
		return root as Button
	for child in root.get_children():
		var result := _find_button(child, fragment)
		if result != null:
			return result
	return null


func _labels_contain(root: Node, fragment: String) -> bool:
	if root is Label and (root as Label).text.contains(fragment):
		return true
	for child in root.get_children():
		if _labels_contain(child, fragment):
			return true
	return false
