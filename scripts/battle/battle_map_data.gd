extends Resource
class_name BattleMapData

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

@export var map_size: Vector2 = Vector2(900, 600)
@export var background_texture: Texture2D
@export_group("Hex Grid")
@export_range(1, 64, 1) var grid_columns: int = 12
@export_range(1, 64, 1) var grid_rows: int = 9
@export_range(8.0, 128.0, 1.0) var hex_size: float = 40.0
@export var grid_origin: Vector2 = Vector2(50, 45)
@export_range(1, 16, 1) var player_deployment_columns: int = 3
@export_range(1, 16, 1) var enemy_spawn_columns: int = 3

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_columns and cell.y >= 0 and cell.y < grid_rows


func is_player_deployment_cell(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and cell.x < mini(player_deployment_columns, grid_columns)


func is_enemy_spawn_cell(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and cell.x >= maxi(0, grid_columns - enemy_spawn_columns)


func map_to_cell(position: Vector2) -> Vector2i:
	return BattleHexGrid.map_to_cell(position, hex_size, grid_origin)


func cell_to_map(cell: Vector2i) -> Vector2:
	return BattleHexGrid.cell_to_map(cell, hex_size, grid_origin)


func get_cell_polygon(cell: Vector2i) -> PackedVector2Array:
	return BattleHexGrid.polygon(cell, hex_size, grid_origin)


func get_distance(a: Vector2i, b: Vector2i) -> int:
	return BattleHexGrid.distance(a, b)


func get_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	return BattleHexGrid.line(a, b)


func get_all_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(grid_rows):
		for column in range(grid_columns):
			result.append(Vector2i(column, row))
	return result


func get_cells_in_range(origin_cell: Vector2i, cell_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in get_all_cells():
		if get_distance(origin_cell, cell) <= maxi(0, cell_range):
			result.append(cell)
	return result


func random_enemy_spawn_cell(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(
		rng.randi_range(maxi(0, grid_columns - enemy_spawn_columns), grid_columns - 1),
		rng.randi_range(0, grid_rows - 1)
	)
