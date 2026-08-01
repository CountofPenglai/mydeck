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
	_test_repeatable_infusion_ui(map_scene)
	if map_scene.enemy_health_spin_box == null:
		_fail("INVENTORY_UI_DIAG: enemy health test control missing")
	elif int(map_scene.enemy_health_spin_box.value) != map_scene.run_state.enemy_health_percent \
			or int(map_scene.enemy_health_spin_box.min_value) != 1 \
			or int(map_scene.enemy_health_spin_box.max_value) != 1000:
		_fail("INVENTORY_UI_DIAG: enemy health test control is out of sync")
	print("INVENTORY_UI_DIAG: completed")
	get_tree().quit(exit_code)


func _test_repeatable_infusion_ui(map_scene: AdventureMapScene) -> void:
	var shelter: AdventureRoomState
	for room in map_scene.run_state.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.SHELTER:
			shelter = room
			break
	var druid: CharacterState
	var first_target: CharacterState
	var second_target: CharacterState
	for hero in map_scene.run_state.party:
		if hero == null or hero.character_data == null:
			continue
		if hero.character_data.character_class == CardEnums.CardClass.DRUID:
			druid = hero
		elif first_target == null:
			first_target = hero
		else:
			second_target = hero
	if shelter == null or druid == null or first_target == null or second_target == null:
		_fail("INVENTORY_UI_DIAG: infusion UI setup is incomplete")
		return
	map_scene.run_state.floor_state.current_room_id = shelter.room_id
	map_scene.run_state.camp_points = 10
	var first_stack := first_target.deck[0]
	var second_stack := second_target.deck[0]
	map_scene._show_infusion_cards()
	await get_tree().process_frame
	if not map_scene.modal_layer.visible or _find_button(map_scene.modal_body, first_stack.card_data.card_name) == null:
		_fail("INVENTORY_UI_DIAG: first infusion chooser did not expose a valid card")
	map_scene._apply_infusion(
		druid.adventure_character_id,
		first_target.adventure_character_id,
		first_stack.stack_id,
		BattleSurfaceState.Element.FIRE
	)
	await get_tree().process_frame
	map_scene._show_infusion_cards()
	await get_tree().process_frame
	if not map_scene.modal_layer.visible or _find_button(map_scene.modal_body, second_stack.card_data.card_name) == null:
		_fail("INVENTORY_UI_DIAG: infusion chooser became unusable after a successful infusion")
	map_scene._hide_modal()


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
