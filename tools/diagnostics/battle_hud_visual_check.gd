extends Node


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	var battle_scene := packed.instantiate() as BattleScene
	add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var controller := battle_scene.controller
	for unit in controller.player_units:
		unit.is_deployed = true
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.turn_order.clear()
	controller.turn_order.append_array(controller.player_units)
	controller.turn_order.append_array(controller.enemy_units)
	controller.current_turn_index = 0
	controller.current_unit = controller.player_units[0]
	controller.current_unit.hand.clear()
	for card_path in [
		"res://resources/cards/battle_slam.tres",
		"res://resources/cards/battle_charge.tres",
		"res://resources/cards/defensive_stance.tres",
		"res://resources/cards/gather_momentum_whirlwind.tres",
		"res://resources/cards/breaching_strike.tres",
	]:
		var card := load(card_path) as CardData
		if card != null:
			controller.current_unit.hand.append(card)
	battle_scene._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var hud_root := battle_scene.get_node("%BattleHudRoot") as Control
	var bottom_hud := hud_root.get_node("%BattleBottomHud") as Control
	for node_name in ["BottomArtwork", "StatusRow", "HandFrame"]:
		var control := bottom_hud.get_node("%%%s" % node_name) as Control
		print("BATTLE_HUD_VISUAL_NODE: %s visible=%s rect=%s clip=%s" % [
			node_name,
			control.is_visible_in_tree(),
			control.get_global_rect(),
			control.clip_contents,
		])
	var hand_list := bottom_hud.get_node("%HandList") as Control
	print("BATTLE_HUD_VISUAL_CONTENT: hand=%s children=%d" % [hand_list.get_global_rect(), hand_list.get_child_count()])
	for node_name in [
		"CurseRegion",
		"EnchantRegion",
		"EquipmentRegion",
		"VitalsRegion",
		"CommandRegion",
		"CharacterResourceRegion",
		"StatusRegion",
	]:
		var region := bottom_hud.find_child(node_name, true, false) as Control
		print("BATTLE_HUD_VISUAL_REGION: %s visible=%s rect=%s z=%d" % [
			node_name,
			region.is_visible_in_tree(),
			region.get_global_rect(),
			region.z_index,
		])
	var status_label := bottom_hud.get_node("%StatusLabel") as Label
	print("BATTLE_HUD_VISUAL_STATUS: visible=%s rect=%s text=%s color=%s" % [
		status_label.is_visible_in_tree(),
		status_label.get_global_rect(),
		status_label.text.replace("\n", "/"),
		status_label.get_theme_color("font_color"),
	])
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("BATTLE_HUD_VISUAL_CHECK: SKIP screenshot under headless display driver")
		get_tree().quit(0)
		return

	var image := get_viewport().get_texture().get_image()
	var output_path := ProjectSettings.globalize_path("res://.godot_user/compact_hud_preview.png")
	var error := image.save_png(output_path)
	if error != OK:
		push_error("BATTLE_HUD_VISUAL_CHECK: screenshot failed: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("BATTLE_HUD_VISUAL_CHECK: %s" % output_path)
	get_tree().quit(0)
