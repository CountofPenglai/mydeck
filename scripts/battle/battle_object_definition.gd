extends Resource
class_name BattleObjectDefinition

enum Kind {
	EXPLOSIVE_BARREL,
	WATER_CISTERN,
	WIND_TOTEM,
	UNSTABLE_PILLAR,
	RUBBLE,
}

@export var kind: int = Kind.EXPLOSIVE_BARREL
@export var display_name: String = ""
@export_range(1, 999, 1) var max_health: int = 1
@export var blocks_movement: bool = true
@export var blocks_line_of_sight: bool = false
@export var targetable: bool = true
@export var destructible: bool = true
@export var persistent_element: int = BattleSurfaceState.Element.NONE
@export var map_color: Color = Color(0.7, 0.7, 0.7)


static func create_builtin(object_kind: int) -> BattleObjectDefinition:
	var definition := BattleObjectDefinition.new()
	definition.kind = object_kind
	match object_kind:
		Kind.EXPLOSIVE_BARREL:
			definition.display_name = "\u70b8\u836f\u6876"
			definition.max_health = 4
			definition.blocks_line_of_sight = false
			definition.map_color = Color(0.72, 0.18, 0.08)
		Kind.WATER_CISTERN:
			definition.display_name = "\u50a8\u6c34\u7f50"
			definition.max_health = 5
			definition.blocks_line_of_sight = false
			definition.map_color = Color(0.08, 0.44, 0.68)
		Kind.WIND_TOTEM:
			definition.display_name = "\u98ce\u8680\u56fe\u817e"
			definition.max_health = 5
			definition.blocks_line_of_sight = false
			definition.persistent_element = BattleSurfaceState.Element.AIR
			definition.map_color = Color(0.55, 0.78, 0.82)
		Kind.UNSTABLE_PILLAR:
			definition.display_name = "\u4e0d\u7a33\u5899\u67f1"
			definition.max_health = 8
			definition.blocks_line_of_sight = true
			definition.map_color = Color(0.48, 0.45, 0.41)
		Kind.RUBBLE:
			definition.display_name = "\u5efa\u7b51\u6b8b\u9ab8"
			definition.max_health = 5
			definition.blocks_line_of_sight = true
			definition.persistent_element = BattleSurfaceState.Element.EARTH
			definition.map_color = Color(0.38, 0.36, 0.31)
		_:
			definition.display_name = "\u6218\u573a\u5bf9\u8c61"
	return definition
