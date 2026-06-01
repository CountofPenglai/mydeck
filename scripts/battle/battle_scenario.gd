extends Resource
class_name BattleScenario

@export var battle_config: BattleConfig
@export var map_data: BattleMapData
@export var seed: int = 1001
@export var players: Array[CharacterState] = []
@export var enemies: Array[EnemyState] = []
