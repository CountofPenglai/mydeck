extends Resource
class_name BattleScenario

@export var battle_config: BattleConfig
@export var scene_prototype: Resource
@export var map_data: BattleMapData
@export var seed: int = 1001
@export var players: Array[CharacterState] = []
@export var enemies: Array[EnemyState] = []

func get_map_data() -> BattleMapData:
	if scene_prototype != null and scene_prototype.map_data != null:
		return scene_prototype.map_data

	return map_data


func get_enemy_states() -> Array[EnemyState]:
	if scene_prototype != null:
		return scene_prototype.create_enemy_states()

	return enemies
