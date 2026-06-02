extends Resource
class_name BattleScenePrototype

@export var scene_id: String = "scene_001"
@export var difficulty: int = 1
@export var scene_texture: Texture2D
@export var map_data: BattleMapData
@export var enemy_configs: Array[Resource] = []
@export var global_effects: Array[Resource] = []

func create_enemy_states() -> Array[EnemyState]:
	var result: Array[EnemyState] = []
	for config in enemy_configs:
		if config == null:
			continue
		result.append_array(config.create_enemy_states())

	return result


func get_display_title() -> String:
	return "%s | 难度 %d" % [scene_id, difficulty]
