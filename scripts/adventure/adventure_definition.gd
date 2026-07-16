extends Resource
class_name AdventureDefinition

@export var floor_count: int = 2
@export var min_rooms: int = 18
@export var max_rooms: int = 24
@export var grid_size: Vector2i = Vector2i(11, 7)
@export var loop_edge_min: int = 2
@export var loop_edge_max: int = 3
@export var economy: AdventureEconomyConfig


func get_economy() -> AdventureEconomyConfig:
	if economy == null:
		economy = AdventureEconomyConfig.new()
	return economy
