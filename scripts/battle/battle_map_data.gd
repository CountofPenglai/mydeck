extends Resource
class_name BattleMapData

@export var map_size: Vector2 = Vector2(900, 600)
@export var background_texture: Texture2D
@export var player_deployment_rect: Rect2 = Rect2(Vector2(40, 160), Vector2(220, 280))
@export var enemy_spawn_rect: Rect2 = Rect2(Vector2(640, 120), Vector2(220, 360))

func contains_map_position(position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, map_size).has_point(position)


func contains_deployment_position(position: Vector2) -> bool:
	return player_deployment_rect.has_point(position)


func random_enemy_spawn_position(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(enemy_spawn_rect.position.x, enemy_spawn_rect.end.x),
		rng.randf_range(enemy_spawn_rect.position.y, enemy_spawn_rect.end.y)
	)
