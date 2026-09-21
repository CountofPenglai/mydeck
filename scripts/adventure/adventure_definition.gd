extends Resource
class_name AdventureDefinition

@export var floor_count: int = 2
@export var min_rooms: int = 48
@export var max_rooms: int = 48
@export var grid_size: Vector2i = Vector2i(8, 6)
@export var economy: AdventureEconomyConfig


func get_economy() -> AdventureEconomyConfig:
	if economy == null:
		economy = AdventureEconomyConfig.new()
	return economy
