extends Node

const TARGET_SIZES := [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
]

var _exit_code := 0


func _ready() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: battle scene failed to load")
		get_tree().quit(_exit_code)
		return

	for target_size in TARGET_SIZES:
		await _check_size(packed, target_size)
		if _exit_code != 0:
			break

	if _exit_code == 0:
		print("BATTLE_HUD_LAYOUT_CHECK: PASS")
	get_tree().quit(_exit_code)


func _check_size(packed: PackedScene, target_size: Vector2i) -> void:
	get_window().size = target_size
	var host := Control.new()
	host.size = Vector2(target_size)
	add_child(host)
	var battle_scene := packed.instantiate() as Control
	host.add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	for legacy_path in [
		"TopOverlay",
		"CurrentUnitPanel",
		"BottomHud",
		"DiscardButton",
		"CurseButton",
		"MenuButton",
	]:
		if battle_scene.get_node_or_null(legacy_path) != null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: legacy HUD node remains: %s at %s" % [legacy_path, target_size])

	var hud_root := battle_scene.get_node_or_null("%BattleHudRoot") as Control
	if hud_root == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: BattleHudRoot missing at %s" % target_size)
		host.queue_free()
		await get_tree().process_frame
		return
	if hud_root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("BATTLE_HUD_LAYOUT_CHECK: full-screen HUD root blocks map input at %s" % target_size)

	for node_name in ["TurnOrderBar", "DeploymentPanel", "BattleDetailPanel", "BattleBottomHud", "MenuButton"]:
		if hud_root.get_node_or_null("%%%s" % node_name) == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s missing at %s" % [node_name, target_size])
			break
	if hud_root.get_node_or_null("BottomHud") != null or hud_root.get_node_or_null("DetailPanel") != null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: hidden HUD placeholder remains at %s" % target_size)
	var message_label := hud_root.get_node_or_null("%BattleMessageLabel") as Label
	if message_label == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: battle message label missing at %s" % target_size)
	else:
		battle_scene.call("_append_log", "HUD diagnostic message")
		if "HUD diagnostic message" not in message_label.text:
			_fail("BATTLE_HUD_LAYOUT_CHECK: battle log is not routed to the new HUD at %s" % target_size)
	for artwork_name in [
		"BottomArtwork",
		"TurnRailArtwork",
		"DetailArtwork",
		"CurrentUnitRing",
		"EnchantFrameArtwork",
		"EquipmentFrameArtwork",
		"VitalsFrameArtwork",
		"CommandFrameArtwork",
		"CharacterResourceFrameArtwork",
		"StatusFrameArtwork",
		"CurseFrameArtwork",
	]:
		var artwork_node := hud_root.find_child(artwork_name, true, false) as Control
		if artwork_node == null or artwork_node.get("texture") == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s texture is not bound at %s" % [artwork_name, target_size])
			break
	var detail_artwork := hud_root.find_child("DetailArtwork", true, false) as NinePatchRect
	if detail_artwork == null or detail_artwork.patch_margin_left > 32 \
			or detail_artwork.patch_margin_top > 32 \
			or detail_artwork.patch_margin_right > 32 \
			or detail_artwork.patch_margin_bottom > 32:
		_fail("BATTLE_HUD_LAYOUT_CHECK: detail artwork still uses a heavy frame at %s" % target_size)
	if hud_root.find_child("HudAttackButton", true, false) != null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: basic attack button remains in HUD at %s" % target_size)
	for command_name in ["HudMoveButton", "HudEndTurnButton"]:
		var command_button := hud_root.find_child(command_name, true, false) as Button
		if command_button == null or command_button.icon == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s icon is not bound at %s" % [command_name, target_size])
			break

	var bottom_hud := hud_root.get_node_or_null("%BattleBottomHud") as Control
	if bottom_hud != null:
		var height := bottom_hud.size.y
		if height < 175.0 or height > 196.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: compact bottom HUD height %.1f at %s" % [height, target_size])
		if bottom_hud.get_global_rect().end.y > float(target_size.y) + 1.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD leaves viewport at %s" % target_size)
		var status_row := bottom_hud.get_node_or_null("%StatusRow") as Control
		var hand_frame := bottom_hud.get_node_or_null("%HandFrame") as Control
		if status_row == null or hand_frame == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD geometry nodes missing at %s" % target_size)
		elif status_row.get_global_rect().intersects(hand_frame.get_global_rect()):
			for region in status_row.get_children():
				if region is Control:
					print("BATTLE_HUD_REGION_MIN: %s=%s" % [region.name, (region as Control).get_combined_minimum_size()])
			_fail("BATTLE_HUD_LAYOUT_CHECK: status row %s occludes hand area %s at %s" % [
				status_row.get_global_rect(),
				hand_frame.get_global_rect(),
				target_size,
			])

	var equipment_region := bottom_hud.get_node_or_null("%EquipmentRegion") if bottom_hud != null else null
	if equipment_region == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: EquipmentRegion missing at %s" % target_size)
	elif _contains_scroll_container(equipment_region):
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment region contains scrolling at %s" % target_size)
	else:
		var equipment_button := bottom_hud.get_node_or_null("%EquipmentButton") as Button
		var equipment_label := bottom_hud.get_node_or_null("%EquipmentLabel") as Label
		var presentation_controller = battle_scene.get("controller")
		if presentation_controller is BattleController:
			for presentation_unit in presentation_controller.player_units:
				if presentation_unit != null \
						and presentation_unit.get_character_class() != CardEnums.CardClass.WARRIOR:
					bottom_hud.call("bind_unit", presentation_unit, presentation_controller, false)
					break
		bottom_hud.call("set_equipment_actions", 1, "启动：本回合伤害加值 +2、范围 +1", true)
		if equipment_button == null or equipment_label == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment action text nodes are missing at %s" % target_size)
		elif not equipment_button.text.is_empty():
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment button text overlaps its summary label at %s" % target_size)
		elif equipment_label.text != "启动：\n本回合伤害加值 +2、范围 +1":
			_fail("BATTLE_HUD_LAYOUT_CHECK: single equipment action is not split into brief lines at %s" % target_size)
		elif equipment_label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment action summary cannot wrap at %s" % target_size)
		bottom_hud.call("set_equipment_actions", 3)
		if equipment_button != null and not equipment_button.text.is_empty():
			_fail("BATTLE_HUD_LAYOUT_CHECK: multi-action equipment button draws overlapping text at %s" % target_size)
		elif equipment_label != null and equipment_label.text != "装备动作 3 项\n点击展开":
			_fail("BATTLE_HUD_LAYOUT_CHECK: multi-action equipment summary is not split into lines at %s" % target_size)
	for region_limit in [
		{"name": "EquipmentRegion", "max_width": 140.0},
		{"name": "VitalsRegion", "max_width": 300.0},
		{"name": "CharacterResourceRegion", "max_width": 160.0},
		{"name": "StatusRegion", "max_width": 160.0},
	]:
		var region := bottom_hud.find_child(str(region_limit.name), true, false) as Control
		if region == null or region.size.x > float(region_limit.max_width) + 1.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s is oversized at %s" % [region_limit.name, target_size])
			break
	for readable_zone_name in ["EnchantRegion", "CurseRegion"]:
		var readable_zone := bottom_hud.find_child(readable_zone_name, true, false) as Control
		if readable_zone == null or readable_zone.size.x < 104.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: %s cannot display card names at %s" % [readable_zone_name, target_size])
			break
	var vitals_region := bottom_hud.get_node_or_null("%VitalsRegion") as Control if bottom_hud != null else null
	var health_bar := bottom_hud.get_node_or_null("%HealthBar") as ProgressBar if bottom_hud != null else null
	var portrait_holder := bottom_hud.find_child("PortraitHolder", true, false) as Control if bottom_hud != null else null
	var ap_orb_layer := bottom_hud.get_node_or_null("%APOrbLayer") as Control if bottom_hud != null else null
	var left_status_group := bottom_hud.get_node_or_null("%LeftStatusGroup") as Control if bottom_hud != null else null
	var right_status_group := bottom_hud.get_node_or_null("%RightStatusGroup") as Control if bottom_hud != null else null
	var command_region := bottom_hud.get_node_or_null("%CommandRegion") as Control if bottom_hud != null else null
	var character_resource_region := bottom_hud.get_node_or_null("%CharacterResourceRegion") as Control if bottom_hud != null else null
	var status_region := bottom_hud.get_node_or_null("%StatusRegion") as Control if bottom_hud != null else null
	var status_label := bottom_hud.get_node_or_null("%StatusLabel") as Label if bottom_hud != null else null
	var move_button := bottom_hud.get_node_or_null("%HudMoveButton") as Button if bottom_hud != null else null
	var end_turn_button := bottom_hud.get_node_or_null("%HudEndTurnButton") as Button if bottom_hud != null else null
	if vitals_region == null or health_bar == null or portrait_holder == null or ap_orb_layer == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: centered vitals or health bar missing at %s" % target_size)
	else:
		_assert_close(
			vitals_region.get_global_rect().get_center().x,
			bottom_hud.get_global_rect().get_center().x,
			1.0,
			"vitals center",
			target_size
		)
		if vitals_region.size.x < 270.0 or vitals_region.size.y < 88.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: acting-unit frame is not enlarged at %s" % target_size)
		if health_bar.size.x < 238.0 or health_bar.size.y < 18.0 or health_bar.size.y > 22.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: health bar did not retain its compact height at %s" % target_size)
		if ap_orb_layer.size.x < 190.0 or ap_orb_layer.size.y < 29.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: AP banks are not enlarged at %s" % target_size)
		_assert_close(
			portrait_holder.get_global_rect().get_center().x,
			vitals_region.get_global_rect().get_center().x,
			1.0,
			"portrait center",
			target_size
		)
		if portrait_holder.size.x < 46.0 or portrait_holder.size.y < 46.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: acting portrait is not enlarged at %s" % target_size)
		if portrait_holder.get_global_rect().position.y >= vitals_region.get_global_rect().position.y - 20.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: acting portrait does not protrude above its frame at %s" % target_size)
		if portrait_holder.get_global_rect().end.y > health_bar.get_global_rect().position.y + 1.0:
			_fail("BATTLE_HUD_LAYOUT_CHECK: portrait is not above the health bar at %s" % target_size)
		var hand_frame := bottom_hud.get_node_or_null("%HandFrame") as Control
		if hand_frame != null and vitals_region.get_global_rect().intersects(hand_frame.get_global_rect()):
			_fail("BATTLE_HUD_LAYOUT_CHECK: enlarged vitals overlaps hand at %s" % target_size)
		for left_region_name in ["CurseRegion", "EnchantRegion", "EquipmentRegion"]:
			var left_region := bottom_hud.find_child(left_region_name, true, false) as Control
			if left_region == null or left_region.size.y < 74.0 or left_region.size.y > 78.0:
				_fail("BATTLE_HUD_LAYOUT_CHECK: %s does not match the tall status band at %s" % [left_region_name, target_size])
				break
		if left_status_group == null or right_status_group == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: status side groups are missing at %s" % target_size)
		else:
			_assert_close(
				left_status_group.get_global_rect().end.x,
				vitals_region.get_global_rect().position.x - 4.0,
				1.5,
				"left group tight edge",
				target_size
			)
			_assert_close(
				right_status_group.get_global_rect().position.x,
				vitals_region.get_global_rect().end.x + 4.0,
				1.5,
				"right group tight edge",
				target_size
			)
		if command_region == null or character_resource_region == null or status_region == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: command/resource/status regions are incomplete at %s" % target_size)
		else:
			if command_region.position.x >= character_resource_region.position.x \
					or character_resource_region.position.x >= status_region.position.x:
				_fail("BATTLE_HUD_LAYOUT_CHECK: right-side region order is incorrect at %s" % target_size)
			_assert_close(
				character_resource_region.size.x,
				status_region.size.x,
				1.0,
				"resource/status width",
				target_size
			)
			_assert_close(
				character_resource_region.size.y,
				status_region.size.y,
				1.0,
				"resource/status height",
				target_size
			)
			for left_region_name in ["CurseRegion", "EnchantRegion", "EquipmentRegion"]:
				var left_region := bottom_hud.find_child(left_region_name, true, false) as Control
				if left_region != null:
					_assert_close(
						left_region.size.y,
						status_region.size.y,
						1.0,
						"%s/status height" % left_region_name,
						target_size
					)
			if status_label == null or status_label.size.y < status_region.size.y - 4.0:
				_fail("BATTLE_HUD_LAYOUT_CHECK: status label does not fill its region at %s" % target_size)
		if move_button == null or end_turn_button == null:
			_fail("BATTLE_HUD_LAYOUT_CHECK: vertical command buttons are missing at %s" % target_size)
		else:
			_assert_close(move_button.size.x, 34.0, 1.0, "move button width", target_size)
			_assert_close(move_button.size.y, 34.0, 1.0, "move button height", target_size)
			_assert_close(end_turn_button.size.x, 34.0, 1.0, "end button width", target_size)
			_assert_close(end_turn_button.size.y, 34.0, 1.0, "end button height", target_size)
			_assert_close(
				move_button.get_global_rect().get_center().x,
				end_turn_button.get_global_rect().get_center().x,
				1.0,
				"vertical command alignment",
				target_size
			)
			if move_button.get_global_rect().end.y > end_turn_button.get_global_rect().position.y + 1.0:
				_fail("BATTLE_HUD_LAYOUT_CHECK: move/end buttons are not stacked at %s" % target_size)
		var message_panel := hud_root.get_node_or_null("%BattleMessagePanel") as Control
		if message_panel != null and message_panel.get_global_rect().intersects(portrait_holder.get_global_rect()):
			_fail("BATTLE_HUD_LAYOUT_CHECK: battle message overlaps protruding portrait at %s" % target_size)
	var resource_actions := bottom_hud.get_node_or_null("%ResourceActionList") if bottom_hud != null else null
	if resource_actions == null or not bottom_hud.has_method("get_class_action_count"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: class resource action API missing at %s" % target_size)
	elif _contains_scroll_container(resource_actions):
		_fail("BATTLE_HUD_LAYOUT_CHECK: class resource actions contain scrolling at %s" % target_size)
	var equipment_popup := hud_root.get_node_or_null("%EquipmentActionsPopup")
	if equipment_popup == null or not equipment_popup.has_method("set_actions"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment action popup API missing at %s" % target_size)
	else:
		equipment_popup.call("set_actions", null, [
			{"label": "动作一", "action_id": "one"},
			{"label": "动作二", "action_id": "two"},
			{"label": "动作三", "action_id": "three"},
		], Callable(), target_size.x < 1100)
		if int(equipment_popup.call("get_action_count")) != 3:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup lost actions at %s" % target_size)
		var expected_popup_columns := 1 if target_size.x < 1100 else 2
		if int(equipment_popup.call("get_column_count")) != expected_popup_columns:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup columns mismatch at %s" % target_size)
		if _contains_scroll_container(equipment_popup):
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment popup contains scrolling at %s" % target_size)

	if hud_root.has_method("get_equipment_column_count"):
		var expected_columns := 1 if target_size.x < 1100 else 2
		if int(hud_root.call("get_equipment_column_count")) != expected_columns:
			_fail("BATTLE_HUD_LAYOUT_CHECK: equipment columns mismatch at %s" % target_size)
	else:
		_fail("BATTLE_HUD_LAYOUT_CHECK: equipment column API missing")

	if hud_root.has_method("is_compact_mode"):
		if bool(hud_root.call("is_compact_mode")) != (target_size.x < 1100):
			_fail("BATTLE_HUD_LAYOUT_CHECK: compact mode mismatch at %s" % target_size)
	else:
		_fail("BATTLE_HUD_LAYOUT_CHECK: compact mode API missing")

	var state_controller = battle_scene.get("controller")
	var deploy_list := hud_root.get_node_or_null("%DeployList") as Container
	if state_controller is BattleController and deploy_list != null:
		hud_root.call("refresh_view")
		if deploy_list.get_child_count() != state_controller.player_units.size():
			_fail("BATTLE_HUD_LAYOUT_CHECK: deployment rows do not match player units at %s" % target_size)
		state_controller.call("_rebuild_turn_order")
		state_controller.current_turn_index = mini(1, state_controller.turn_order.size() - 1)
		if state_controller.current_turn_index >= 0:
			state_controller.current_unit = state_controller.turn_order[state_controller.current_turn_index]
		hud_root.call("refresh_view")
		var order_list := hud_root.get_node_or_null("%OrderList") as Container
		if order_list == null or order_list.get_child_count() != state_controller.turn_order.size():
			_fail("BATTLE_HUD_LAYOUT_CHECK: turn order does not match locked round at %s" % target_size)
		elif not state_controller.turn_order.is_empty():
			var first_entry := order_list.get_child(0)
			if not first_entry.has_meta("faction") or not first_entry.has_meta("acted") or not first_entry.has_meta("current"):
				_fail("BATTLE_HUD_LAYOUT_CHECK: turn order metadata missing at %s" % target_size)
			elif not first_entry.has_meta("frame_texture_bound") or not bool(first_entry.get_meta("frame_texture_bound")):
				_fail("BATTLE_HUD_LAYOUT_CHECK: turn order art frame missing at %s" % target_size)
		var bottom_module := hud_root.get_node_or_null("%BattleBottomHud")
		if bottom_module == null or not bottom_module.has_method("get_bound_unit"):
			_fail("BATTLE_HUD_LAYOUT_CHECK: bottom HUD binding API missing at %s" % target_size)
		else:
			var selected_unit = battle_scene.get("selected_deploy_unit")
			if bottom_module.call("get_bound_unit") != selected_unit:
				_fail("BATTLE_HUD_LAYOUT_CHECK: deployment HUD is not bound to selected unit at %s" % target_size)
			if state_controller.current_turn_index >= 0:
				state_controller.phase = BattleController.Phase.BATTLE
				state_controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
				state_controller.current_unit = state_controller.player_units[0]
				hud_root.call("refresh_view")
				if bottom_module.call("get_bound_unit") != state_controller.current_unit:
					_fail("BATTLE_HUD_LAYOUT_CHECK: battle HUD is not bound to acting unit at %s" % target_size)
				var ap_slots := bottom_module.get_node_or_null("%APOrbLayer") as Control
				var state_slot_count := 0
				var bank_count := 0
				if ap_slots != null:
					for child in ap_slots.get_children():
						if child.has_meta("ap_state"):
							state_slot_count += 1
						if child.has_meta("ap_bank"):
							bank_count += 1
				if ap_slots == null or state_slot_count != 8 or bank_count != 2:
					_fail("BATTLE_HUD_LAYOUT_CHECK: AP display must contain two four-slot banks and 8 states at %s" % target_size)
				if health_bar != null:
					_assert_close(
						health_bar.max_value,
						float(state_controller.current_unit.get_max_health()),
						0.1,
						"health bar maximum",
						target_size
					)
					_assert_close(
						health_bar.value,
						float(state_controller.current_unit.get_current_health()),
						0.1,
						"health bar value",
						target_size
					)
				var hand_list := bottom_module.get_node_or_null("%HandList") as Container
				if state_controller.current_unit.faction == BattleUnitState.Faction.PLAYER \
						and not state_controller.current_unit.hand.is_empty() \
					and (hand_list == null or hand_list.get_child_count() != state_controller.current_unit.hand.size()):
					_fail("BATTLE_HUD_LAYOUT_CHECK: hand cards do not match acting unit at %s" % target_size)
				var hand_frame := bottom_module.get_node_or_null("%HandFrame") as Control
				if hand_list != null and hand_frame != null:
					for child in hand_list.get_children():
						if child is TextureButton and not hand_frame.get_global_rect().encloses((child as Control).get_global_rect()):
							_fail("BATTLE_HUD_LAYOUT_CHECK: hand card is clipped at %s" % target_size)
							break
	if state_controller is BattleController and bottom_hud != null:
		await _test_warrior_equipment_summary(state_controller, hud_root, bottom_hud, target_size)

	var map_view := battle_scene.get_node_or_null("%MapView") as Control
	if map_view == null or not map_view.has_method("set_fit_safe_rect"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: map safe-area API missing at %s" % target_size)
	elif hud_root.has_method("get_battle_safe_rect"):
		var deployment_panel := hud_root.get_node_or_null("%DeploymentPanel") as Control
		var detail_overlay := hud_root.get_node_or_null("%BattleDetailPanel") as Control
		deployment_panel.visible = false
		detail_overlay.visible = false
		hud_root.call("_apply_responsive_layout")
		var unobstructed_safe: Rect2 = hud_root.call("get_battle_safe_rect")
		deployment_panel.visible = true
		detail_overlay.visible = true
		hud_root.call("_apply_responsive_layout")
		var overlay_safe: Rect2 = hud_root.call("get_battle_safe_rect")
		if absf(unobstructed_safe.position.x - overlay_safe.position.x) > 0.1 \
				or absf(unobstructed_safe.end.x - overlay_safe.end.x) > 0.1:
			_fail("BATTLE_HUD_LAYOUT_CHECK: overlay panels shrink horizontal map fit at %s" % target_size)
		if overlay_safe.size.y < float(target_size.y) * 0.55:
			_fail("BATTLE_HUD_LAYOUT_CHECK: battlefield safe height is below 55%% at %s" % target_size)
		var safe_rect: Rect2 = hud_root.call("get_battle_safe_rect")
		map_view.call("set_fit_safe_rect", safe_rect)
		map_view.call("_reset_view_to_fit")
		var controller = battle_scene.get("controller")
		if controller is BattleController and controller.map_data != null:
			var top_left: Vector2 = map_view.call("map_to_screen", Vector2.ZERO)
			var bottom_right: Vector2 = map_view.call("map_to_screen", controller.map_data.map_size)
			if top_left.x < safe_rect.position.x - 1.0 or top_left.y < safe_rect.position.y - 1.0 \
					or bottom_right.x > safe_rect.end.x + 1.0 or bottom_right.y > safe_rect.end.y + 1.0:
				_fail("BATTLE_HUD_LAYOUT_CHECK: map does not fit HUD safe area at %s" % target_size)

	var detail_panel := hud_root.get_node_or_null("%BattleDetailPanel") as Control
	if detail_panel == null or not detail_panel.has_method("preview_card"):
		_fail("BATTLE_HUD_LAYOUT_CHECK: unified detail API missing at %s" % target_size)
	elif state_controller is BattleController and not state_controller.player_units.is_empty():
		var detail_card: CardData = null
		var detail_unit: BattleUnitState = state_controller.player_units[0]
		if not detail_unit.hand.is_empty():
			detail_card = detail_unit.hand[0]
		elif not detail_unit.draw_pile.is_empty():
			detail_card = detail_unit.draw_pile[0]
		if detail_card != null:
			detail_panel.call("preview_card", detail_card, {"user": detail_unit})
			detail_panel.call("lock_current")
			detail_panel.call("preview_unit", state_controller.enemy_units[0] if not state_controller.enemy_units.is_empty() else detail_unit)
			detail_panel.call("clear_preview")
			if str(detail_panel.call("get_display_title")) != detail_card.card_name:
				_fail("BATTLE_HUD_LAYOUT_CHECK: detail hover did not restore locked card at %s" % target_size)
			detail_panel.call("clear_lock")
			if detail_panel.visible:
				_fail("BATTLE_HUD_LAYOUT_CHECK: clearing detail lock did not hide panel at %s" % target_size)
		if not battle_scene.has_method("handle_map_hover"):
			_fail("BATTLE_HUD_LAYOUT_CHECK: map hover detail bridge missing at %s" % target_size)
		elif not state_controller.enemy_units.is_empty():
			var hover_enemy: BattleUnitState = state_controller.enemy_units[0]
			battle_scene.call("handle_map_hover", hover_enemy.position)
			if str(detail_panel.call("get_display_title")) != hover_enemy.get_display_name():
				_fail("BATTLE_HUD_LAYOUT_CHECK: map hover did not preview enemy at %s" % target_size)
	var battle_controller = battle_scene.get("controller")
	if detail_panel != null and battle_controller is BattleController and not battle_controller.player_units.is_empty():
		detail_panel.visible = true
		battle_controller.phase = BattleController.Phase.BATTLE
		battle_controller.current_unit = battle_controller.player_units[0]
		battle_controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
		var empty_cell := _find_empty_cell(battle_controller)
		if empty_cell.x >= 0:
			battle_scene.call("handle_map_click", battle_controller.map_data.cell_to_map(empty_cell))
			if detail_panel.visible:
				_fail("BATTLE_HUD_LAYOUT_CHECK: blank map click did not close detail at %s" % target_size)

	host.queue_free()
	await get_tree().process_frame


func _test_warrior_equipment_summary(
	controller: BattleController,
	hud_root: Control,
	bottom_hud: Control,
	target_size: Vector2i
) -> void:
	var warrior: BattleUnitState
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			warrior = unit
			break
	if warrior == null or warrior.character_state == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior equipment fixture missing at %s" % target_size)
		return

	var active_weapon := load("res://resources/items/mountain_cleaver.tres") as EquipmentData
	var reserve_weapon := load("res://resources/items/lion_greatsword.tres") as EquipmentData
	if active_weapon == null or reserve_weapon == null:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior weapon resources missing at %s" % target_size)
		return
	warrior.character_state.weapon_equipment = active_weapon
	warrior.character_state.weapon_face = 0
	warrior.character_state.reserve_weapon_equipment = reserve_weapon
	warrior.character_state.reserve_weapon_face = 1
	warrior.equipment_runtime_states.clear()
	var action_context := {"controller": controller, "unit": warrior, "phase": "battle"}
	var current_actions := warrior.get_equipment_actions(action_context)

	warrior.character_state.weapon_equipment = reserve_weapon
	warrior.character_state.weapon_face = warrior.character_state.reserve_weapon_face
	warrior.equipment_runtime_states.clear()
	var reserve_actions := warrior.get_equipment_actions(action_context)
	warrior.character_state.weapon_equipment = active_weapon
	warrior.character_state.weapon_face = 0
	warrior.equipment_runtime_states.clear()
	if current_actions.is_empty() or reserve_actions.is_empty():
		_fail("BATTLE_HUD_LAYOUT_CHECK: action-isolation fixtures have no activated actions at %s" % target_size)
		return

	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = warrior
	hud_root.call("refresh_view")
	await get_tree().process_frame
	var equipment_label := bottom_hud.get_node_or_null("%EquipmentLabel") as Label
	var expected_summary := "当前：%s\n备战：%s" % [active_weapon.item_name, reserve_weapon.get_face(1).item_name]
	if equipment_label == null or equipment_label.text != expected_summary:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior current/reserve summary mismatch at %s" % target_size)
	elif equipment_label.text.split("\n").size() != 2:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior equipment summary is not exactly two lines at %s" % target_size)
	elif equipment_label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior equipment summary cannot wrap at %s" % target_size)
	var hud_actions: Array = hud_root.get("_equipment_actions")
	if hud_actions.size() != current_actions.size():
		_fail("BATTLE_HUD_LAYOUT_CHECK: HUD equipment actions do not match the current weapon at %s" % target_size)
	elif hud_actions.size() >= current_actions.size() + reserve_actions.size():
		_fail("BATTLE_HUD_LAYOUT_CHECK: reserve weapon activated actions leaked into HUD at %s" % target_size)
	bottom_hud.get_node("%EquipmentButton").pressed.emit()
	await get_tree().process_frame
	var equipment_popup := hud_root.get_node_or_null("%EquipmentActionsPopup")
	if equipment_popup == null \
			or not bool(equipment_popup.call("is_open")) \
			or int(equipment_popup.call("get_detail_entry_count")) != 2:
		_fail("BATTLE_HUD_LAYOUT_CHECK: warrior current/reserve detail commands are missing at %s" % target_size)
	elif int(equipment_popup.call("get_action_count")) != current_actions.size():
		_fail("BATTLE_HUD_LAYOUT_CHECK: opening weapon details changed the current action list at %s" % target_size)
	equipment_popup.call("close")


func _contains_scroll_container(root: Node) -> bool:
	for child in root.get_children():
		if child is ScrollContainer or _contains_scroll_container(child):
			return true
	return false


func _find_empty_cell(controller: BattleController) -> Vector2i:
	for cell in controller.map_data.get_all_cells():
		if controller.get_unit_at_cell(cell) == null and controller.get_battle_object_at_cell(cell) == null:
			return cell
	return Vector2i(-1, -1)


func _assert_close(actual: float, expected: float, tolerance: float, label: String, target_size: Vector2i) -> void:
	if absf(actual - expected) > tolerance:
		_fail("BATTLE_HUD_LAYOUT_CHECK: %s %.1f expected %.1f at %s" % [label, actual, expected, target_size])


func _fail(message: String) -> void:
	if _exit_code == 0:
		push_error(message)
		print("ERROR: " + message)
	_exit_code = 1
