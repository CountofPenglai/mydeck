extends Resource
class_name BattleEnemyConfig

@export var enemy_state: EnemyState
@export_range(1, 20, 1) var count: int = 1

func create_enemy_states() -> Array[EnemyState]:
	var result: Array[EnemyState] = []
	if enemy_state == null:
		return result

	for _i in range(count):
		var duplicated_state := enemy_state.duplicate(true) as EnemyState
		if duplicated_state != null:
			result.append(duplicated_state)

	return result
