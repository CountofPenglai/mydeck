extends Control
class_name BattleMapView

var battle_scene
var controller: BattleController

func setup(scene, battle_controller: BattleController) -> void:
	battle_scene = scene
	controller = battle_controller
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if battle_scene != null and battle_scene.has_method("handle_map_click"):
			battle_scene.handle_map_click(event.position)


func _draw() -> void:
	if controller == null or controller.map_data == null:
		return

	var map_rect := Rect2(Vector2.ZERO, controller.map_data.map_size)
	if controller.map_data.background_texture != null:
		draw_texture_rect(controller.map_data.background_texture, map_rect, false)
	else:
		draw_rect(map_rect, Color(0.105, 0.12, 0.12, 1), true)
	draw_rect(map_rect, Color(0.42, 0.48, 0.5, 1), false, 2.0)
	draw_rect(controller.map_data.player_deployment_rect, Color(0.15, 0.45, 0.8, 0.18), true)
	draw_rect(controller.map_data.player_deployment_rect, Color(0.25, 0.6, 0.95, 0.8), false, 2.0)
	draw_rect(controller.map_data.enemy_spawn_rect, Color(0.85, 0.25, 0.18, 0.14), true)
	draw_rect(controller.map_data.enemy_spawn_rect, Color(0.9, 0.38, 0.25, 0.75), false, 2.0)

	for unit in controller.units:
		if not unit.is_deployed or not unit.is_alive():
			continue

		var color := Color(0.25, 0.55, 0.95, 1)
		if unit.faction == BattleUnitState.Faction.ENEMY:
			color = Color(0.9, 0.28, 0.18, 1)

		if unit == controller.current_unit:
			draw_circle(unit.position, unit.radius + 6.0, Color(1.0, 0.9, 0.35, 0.45))

		var token_rect := Rect2(unit.position - Vector2(unit.radius, unit.radius), Vector2(unit.radius * 2.0, unit.radius * 2.0))
		var battle_texture := unit.get_battle_texture()
		if battle_texture != null:
			draw_texture_rect(battle_texture, token_rect, false)
			draw_arc(unit.position, unit.radius, 0.0, TAU, 48, color, 3.0)
		else:
			draw_circle(unit.position, unit.radius, color)
		draw_arc(unit.position, unit.get_attack_range() + unit.radius, 0.0, TAU, 64, Color(color.r, color.g, color.b, 0.22), 2.0)
		draw_string(get_theme_default_font(), unit.position + Vector2(-unit.radius, -unit.radius - 8.0), unit.get_display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
