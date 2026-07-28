extends Resource
class_name BattleScenario

@export var battle_config: BattleConfig
@export var scene_prototype: Resource
@export var map_data: BattleMapData
@export var seed: int = 1001
@export var players: Array[Resource] = []
@export var enemies: Array[Resource] = []
@export_group("Battlefield Features")
@export var generate_battlefield_features: bool = false
@export_range(1, 8, 1) var feature_chapter: int = 1
@export var feature_encounter_tier: int = 0
@export var feature_seed: int = 0
@export var force_abyss_features: bool = false

func get_map_data() -> BattleMapData:
	if scene_prototype != null and scene_prototype.map_data != null:
		return scene_prototype.map_data

	return map_data


func get_enemy_states() -> Array[EnemyState]:
	var result: Array[EnemyState] = []
	for enemy in enemies:
		if enemy is EnemyState:
			result.append(enemy)
	if not result.is_empty():
		return result
	if scene_prototype != null:
		return scene_prototype.create_enemy_states()

	return result


func get_player_states() -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for player in players:
		if player is CharacterState:
			result.append(player)

	return result
