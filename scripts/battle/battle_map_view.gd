extends Control
class_name BattleMapView

const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")
const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

const DRAG_THRESHOLD := 8.0
const FIT_PADDING := 32.0
const LEGAL_FILL := Color(0.52, 1.0, 0.6, 0.22)
const LEGAL_STROKE := Color(0.62, 1.0, 0.68, 0.82)
const INVALID_DIM := Color(0.0, 0.0, 0.0, 0.18)
const PANEL_BG := Color(0.02, 0.025, 0.02, 0.72)

var battle_scene: BattleScene
var controller: BattleController
var view_offset := Vector2.ZERO
var view_zoom := 1.0

var _pointer_down := false
var _is_panning := false
var _user_adjusted_view := false
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _move_preview_cells: Array[Vector2i] = []
var _move_preview_valid := false
var _card_target_preview_units: Array[BattleUnitState] = []
var _card_target_preview_valid := false
var _card_area_preview_cells: Array[Vector2i] = []
var _card_area_preview_valid := false
var _card_landing_preview_cells: Array[Vector2i] = []
var _card_landing_preview_valid := false


func setup(scene: BattleScene, battle_controller: BattleController) -> void:
	battle_scene = scene
	controller = battle_controller
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	call_deferred("_reset_view_to_fit")
	invalidate_preview_cache()
	queue_redraw()


func invalidate_preview_cache() -> void:
	_move_preview_cells.clear()
	_move_preview_valid = false
	_card_target_preview_units.clear()
	_card_target_preview_valid = false
	_card_area_preview_cells.clear()
	_card_area_preview_valid = false
	_card_landing_preview_cells.clear()
	_card_landing_preview_valid = false


func screen_to_map(local_position: Vector2) -> Vector2:
	return (local_position - view_offset) / view_zoom


func map_to_screen(map_position: Vector2) -> Vector2:
	return map_position * view_zoom + view_offset


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if not _user_adjusted_view:
			_reset_view_to_fit()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_start_pointer(event.position)
	else:
		_finish_pointer(event.position)
	accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _pointer_down:
		return

	_update_pointer_drag(event.position, event.relative)
	accept_event()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.index != 0:
		return

	if event.pressed:
		_start_pointer(event.position)
	else:
		_finish_pointer(event.position)
	accept_event()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != 0 or not _pointer_down:
		return

	_update_pointer_drag(event.position, event.relative)
	accept_event()


func _start_pointer(position: Vector2) -> void:
	_pointer_down = true
	_is_panning = false
	_press_position = position
	_last_position = position


func _finish_pointer(position: Vector2) -> void:
	if not _pointer_down:
		return

	var was_click := not _is_panning and position.distance_to(_press_position) < DRAG_THRESHOLD
	_pointer_down = false
	_is_panning = false
	if was_click and battle_scene != null:
		battle_scene.handle_map_click(screen_to_map(position))


func _update_pointer_drag(position: Vector2, relative: Vector2) -> void:
	if not _is_panning and position.distance_to(_press_position) >= DRAG_THRESHOLD:
		_is_panning = true

	if _is_panning:
		var delta := relative
		if delta.length_squared() <= 0.001:
			delta = position - _last_position
		view_offset += delta
		_clamp_view_offset()
		_user_adjusted_view = true
		queue_redraw()

	_last_position = position


func _draw() -> void:
	if controller == null or controller.map_data == null:
		return

	_draw_map_space()
	_draw_screen_space_unit_labels()


func _draw_map_space() -> void:
	draw_set_transform(view_offset, 0.0, Vector2(view_zoom, view_zoom))
	_draw_background()
	_draw_element_surfaces()
	_draw_static_zones()
	_draw_target_preview()
	_draw_units()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_background() -> void:
	var map_rect := Rect2(Vector2.ZERO, controller.map_data.map_size)
	if controller.map_data.background_texture != null:
		draw_texture_rect(controller.map_data.background_texture, map_rect, false)
	else:
		draw_rect(map_rect, Color(0.105, 0.12, 0.12, 1), true)
	draw_rect(map_rect, Color(0.42, 0.48, 0.5, 1), false, 2.0)

	for cell in controller.map_data.get_all_cells():
		var polygon := controller.map_data.get_cell_polygon(cell)
		draw_polyline(polygon + PackedVector2Array([polygon[0]]), Color(0.7, 0.74, 0.7, 0.34), 1.0, true)


func _draw_static_zones() -> void:
	for cell in controller.map_data.get_all_cells():
		if controller.map_data.is_player_deployment_cell(cell):
			_draw_hex_cell(cell, Color(0.15, 0.45, 0.8, 0.18), Color(0.25, 0.6, 0.95, 0.55))
		elif controller.map_data.is_enemy_spawn_cell(cell):
			_draw_hex_cell(cell, Color(0.85, 0.25, 0.18, 0.14), Color(0.9, 0.38, 0.25, 0.48))


func _draw_element_surfaces() -> void:
	if controller == null or controller.surface_state == null:
		return
	for cell in controller.map_data.get_all_cells():
		var element: int = controller.surface_state.get_element(cell)
		if element == BattleSurfaceState.Element.NONE:
			continue
		var fill: Color = BattleSurfaceState.color(element)
		_draw_hex_cell(cell, fill, fill.lightened(0.24))


func _draw_target_preview() -> void:
	if battle_scene == null:
		return

	var preview := battle_scene.get_map_preview_context()
	var input_mode := int(preview.get("input_mode", BattleScene.InputMode.NONE))
	match input_mode:
		BattleScene.InputMode.MOVE:
			_draw_move_preview()
		BattleScene.InputMode.BASIC_ATTACK_TARGET:
			_draw_basic_attack_preview()
		BattleScene.InputMode.CARD_TARGET:
			_draw_card_target_preview(preview)
		BattleScene.InputMode.CARD_LANDING:
			_draw_card_landing_preview(preview)


func _draw_move_preview() -> void:
	var unit := controller.current_unit
	if unit == null:
		return

	if not _move_preview_valid:
		_move_preview_cells = controller.get_reachable_cells(unit)
		_move_preview_valid = true
	for cell in _move_preview_cells:
		if cell != unit.cell:
			_draw_hex_cell(cell, LEGAL_FILL, LEGAL_STROKE)


func _draw_basic_attack_preview() -> void:
	var unit := controller.current_unit
	if unit == null:
		return

	var equipment_slot := str(battle_scene.pending_equipment_slot)
	for cell in controller.map_data.get_all_cells():
		var attack_range := controller.get_effective_attack_range_at_cell(unit, cell, equipment_slot)
		if BattleHexGrid.distance(unit.cell, cell) <= attack_range:
			_draw_hex_cell(cell, LEGAL_FILL, LEGAL_STROKE)
	for target in controller.get_opposing_units(unit):
		if unit.cell_distance_to(target) <= controller.get_effective_attack_range_against(unit, target, equipment_slot):
			_draw_target_marker(target)


func _draw_card_target_preview(preview: Dictionary) -> void:
	var unit := controller.current_unit
	var card: CardData = preview.get("pending_card") as CardData
	if unit == null or card == null:
		return

	var play_mode := int(preview.get("pending_play_mode", CardEnums.CardPlayMode.NORMAL))
	var equipment_slot := str(preview.get("pending_equipment_slot", ""))
	var target_type := int(preview.get("pending_target_type", CardEnums.TargetType.NONE))
	var raw_extra_context: Variant = preview.get("pending_extra_context", {})
	var extra_context: Dictionary = raw_extra_context if raw_extra_context is Dictionary else {}

	if target_type == CardEnums.TargetType.SINGLE:
		var card_range := card.get_effective_range(unit, equipment_slot)
		if card.effect != null and card.effect.uses_strike:
			var profile := unit.build_strike_profile_object(equipment_slot)
			var targetless_weapon_range := unit.get_attack_range(equipment_slot, {"controller": controller})
			for cell in controller.map_data.get_all_cells():
				var effective_range := card_range + controller.get_effective_attack_range_at_cell(unit, cell, equipment_slot) - targetless_weapon_range
				if card.effect is RangerHuntMomentCardEffect and profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED:
					effective_range = controller.get_effective_attack_range_at_cell(unit, cell, equipment_slot) + 2
				if BattleHexGrid.distance(unit.cell, cell) <= effective_range:
					_draw_hex_cell(cell, LEGAL_FILL, LEGAL_STROKE)
		else:
			_draw_range_cells(unit.cell, card_range, false)
		if not _card_target_preview_valid:
			for target in controller.get_units_by_filter(unit, BattleController.UnitFilter.ALL):
				if controller.can_preview_card_targets(unit, card, [target], equipment_slot, play_mode, extra_context):
					_card_target_preview_units.append(target)
			_card_target_preview_valid = true
		for target in _card_target_preview_units:
			_draw_target_marker(target)
	elif target_type == CardEnums.TargetType.AREA:
		_draw_area_card_preview(unit, card, equipment_slot, play_mode, extra_context)


func _draw_area_card_preview(unit: BattleUnitState, card: CardData, equipment_slot: String, play_mode: int, extra_context: Dictionary) -> void:
	if not _card_area_preview_valid:
		var context := _build_effect_preview_context(unit, card, equipment_slot, play_mode, extra_context)
		if card.effect != null and card.effect.provides_area_target_cells():
			_card_area_preview_cells = card.effect.get_area_target_cells(context)
		else:
			for cell in controller.map_data.get_all_cells():
				if controller.can_preview_card_targets(unit, card, [cell], equipment_slot, play_mode, extra_context):
					_card_area_preview_cells.append(cell)
		_card_area_preview_valid = true
	for cell in _card_area_preview_cells:
		_draw_hex_cell(cell, LEGAL_FILL, LEGAL_STROKE)


func _draw_card_landing_preview(preview: Dictionary) -> void:
	var unit := controller.current_unit
	var card: CardData = preview.get("pending_card") as CardData
	var target: BattleUnitState = preview.get("pending_unit_target") as BattleUnitState
	if unit == null or card == null or target == null:
		return
	var equipment_slot := str(preview.get("pending_equipment_slot", ""))
	var play_mode := int(preview.get("pending_play_mode", CardEnums.CardPlayMode.NORMAL))
	var raw_context: Variant = preview.get("pending_extra_context", {})
	var extra_context: Dictionary = (raw_context as Dictionary).duplicate() if raw_context is Dictionary else {}
	if not _card_landing_preview_valid:
		var context := _build_effect_preview_context(unit, card, equipment_slot, play_mode, extra_context)
		if card.effect != null and card.effect.provides_landing_target_cells():
			_card_landing_preview_cells = card.effect.get_landing_target_cells(context, [target])
		else:
			for cell in controller.map_data.get_all_cells():
				extra_context["landing_cell"] = cell
				if controller.can_preview_card_targets(unit, card, [target], equipment_slot, play_mode, extra_context):
					_card_landing_preview_cells.append(cell)
		_card_landing_preview_valid = true
	for cell in _card_landing_preview_cells:
		_draw_hex_cell(cell, LEGAL_FILL, LEGAL_STROKE)


func _build_effect_preview_context(unit: BattleUnitState, card: CardData, equipment_slot: String, play_mode: int, extra_context: Dictionary) -> Dictionary:
	var context := extra_context.duplicate()
	context["controller"] = controller
	context["user"] = unit
	context["card"] = card
	context["equipment_slot"] = equipment_slot
	context["play_mode"] = play_mode
	return context


func _draw_target_marker(unit: BattleUnitState) -> void:
	draw_circle(unit.position, unit.token_radius + 8.0, LEGAL_FILL)
	draw_arc(unit.position, unit.token_radius + 8.0, 0.0, TAU, 48, LEGAL_STROKE, 3.0)


func _draw_units() -> void:
	for unit in controller.units:
		if not unit.is_deployed or not unit.is_alive():
			continue

		var color := Color(0.25, 0.55, 0.95, 1)
		if unit.faction == BattleUnitState.Faction.ENEMY:
			color = Color(0.9, 0.28, 0.18, 1)

		for occupied_cell in unit.get_occupied_cells():
			var token_position := controller.map_data.cell_to_map(occupied_cell)
			if unit == controller.current_unit:
				draw_circle(token_position, unit.token_radius + 6.0, Color(1.0, 0.9, 0.35, 0.45))

			var token_rect := Rect2(token_position - Vector2(unit.token_radius, unit.token_radius), Vector2(unit.token_radius * 2.0, unit.token_radius * 2.0))
			var battle_texture := unit.get_battle_texture()
			if battle_texture != null:
				draw_texture_rect(battle_texture, token_rect, false)
				draw_arc(token_position, unit.token_radius, 0.0, TAU, 48, color, 3.0)
			else:
				draw_circle(token_position, unit.token_radius, color)

		if unit == controller.current_unit:
			_draw_range_cells(unit.cell, unit.get_attack_range(), false, Color(color.r, color.g, color.b, 0.24))
			for origin in unit.get_alternate_range_origins({"controller": controller}):
				_draw_range_cells(origin, unit.get_attack_range(), false, Color(color.r, color.g, color.b, 0.18))


func _draw_range_cells(origin_cell: Vector2i, cell_range: int, require_clear: bool, stroke: Color = LEGAL_STROKE) -> void:
	for cell in controller.map_data.get_cells_in_range(origin_cell, cell_range):
		if cell == origin_cell:
			continue
		if require_clear and not controller.targeting.is_unit_cell_clear(controller.current_unit, cell, false):
			continue
		_draw_hex_cell(cell, LEGAL_FILL, stroke)


func _draw_hex_cell(cell: Vector2i, fill: Color, stroke: Color) -> void:
	var polygon := controller.map_data.get_cell_polygon(cell)
	draw_colored_polygon(polygon, fill)
	draw_polyline(polygon + PackedVector2Array([polygon[0]]), stroke, 1.5, true)


func _draw_screen_space_unit_labels() -> void:
	var font := get_theme_default_font()
	if font == null:
		return

	for unit in controller.units:
		if not unit.is_deployed or not unit.is_alive():
			continue
		_draw_unit_label(unit, font)


func _draw_unit_label(unit: BattleUnitState, font: Font) -> void:
	var screen_position := map_to_screen(unit.position)
	var label_position := screen_position + Vector2(0.0, unit.token_radius * view_zoom + 8.0)
	var hand_count := unit.hand.size()
	var text := "%d/%d  手牌 %d" % [unit.get_current_health(), unit.get_max_health(), hand_count]
	var font_size := 13
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
	var panel_size := text_size + Vector2(14.0, 8.0)
	var panel_rect := Rect2(label_position - Vector2(panel_size.x * 0.5, 0.0), panel_size)
	var hp_ratio := 0.0
	if unit.get_max_health() > 0:
		hp_ratio = clampf(float(unit.get_current_health()) / float(unit.get_max_health()), 0.0, 1.0)

	draw_rect(panel_rect, PANEL_BG, true)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_size.x * hp_ratio, 3.0)), Color(0.35, 0.95, 0.45, 0.95), true)
	draw_rect(panel_rect, Color(0.08, 0.1, 0.08, 0.95), false, 1.0)
	draw_string(font, panel_rect.position + Vector2(7.0, panel_size.y - 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.95, 0.96, 0.86, 1.0))


func _reset_view_to_fit() -> void:
	if controller == null or controller.map_data == null or size.x <= 0.0 or size.y <= 0.0:
		return

	var available := Vector2(maxf(1.0, size.x - FIT_PADDING * 2.0), maxf(1.0, size.y - FIT_PADDING * 2.0))
	var map_size := controller.map_data.map_size
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return

	view_zoom = minf(available.x / map_size.x, available.y / map_size.y)
	view_zoom = clampf(view_zoom, 0.35, 1.5)
	view_offset = (size - map_size * view_zoom) * 0.5
	_clamp_view_offset()
	queue_redraw()


func _clamp_view_offset() -> void:
	if controller == null or controller.map_data == null:
		return

	var map_screen_size := controller.map_data.map_size * view_zoom
	var keep_visible_margin := minf(120.0, minf(size.x, size.y) * 0.25)
	if map_screen_size.x <= size.x:
		var center_x := (size.x - map_screen_size.x) * 0.5
		view_offset.x = clampf(view_offset.x, center_x - keep_visible_margin, center_x + keep_visible_margin)
	else:
		view_offset.x = clampf(view_offset.x, size.x - map_screen_size.x - keep_visible_margin, keep_visible_margin)

	if map_screen_size.y <= size.y:
		var center_y := (size.y - map_screen_size.y) * 0.5
		view_offset.y = clampf(view_offset.y, center_y - keep_visible_margin, center_y + keep_visible_margin)
	else:
		view_offset.y = clampf(view_offset.y, size.y - map_screen_size.y - keep_visible_margin, keep_visible_margin)
