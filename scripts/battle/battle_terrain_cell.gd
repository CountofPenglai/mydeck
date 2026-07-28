extends Resource
class_name BattleTerrainCell

@export var cell: Vector2i = Vector2i.ZERO
@export_enum("None", "Shallow Water", "Magma Fissure", "Abyss") var terrain: int = 0
