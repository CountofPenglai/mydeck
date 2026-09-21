extends RefCounted
class_name AdventureHexGeometry


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	return BattleHexGrid.neighbors(cell)


static func distance(first: Vector2i, second: Vector2i) -> int:
	return BattleHexGrid.distance(first, second)
