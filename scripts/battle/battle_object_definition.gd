extends Resource
class_name BattleObjectDefinition

enum Kind {
	EXPLOSIVE_BARREL,
	WATER_CISTERN,
	WIND_TOTEM,
	UNSTABLE_PILLAR,
	RUBBLE,
	ELEMENTAL_TRAP,
}

@export var kind: int = Kind.EXPLOSIVE_BARREL
@export var display_name: String = ""
@export_multiline var description: String = ""
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
			definition.description = "被摧毁或受到火元素时爆炸，对本格及距离 1 内所有单位和可破坏对象造成 4 点环境伤害，并向这些格施加火元素。"
			definition.max_health = 4
			definition.blocks_line_of_sight = false
			definition.map_color = Color(0.72, 0.18, 0.08)
		Kind.WATER_CISTERN:
			definition.display_name = "\u50a8\u6c34\u7f50"
			definition.description = "被摧毁时，向本格及距离 1 内所有格施加水元素。"
			definition.max_health = 5
			definition.blocks_line_of_sight = false
			definition.map_color = Color(0.08, 0.44, 0.68)
		Kind.WIND_TOTEM:
			definition.display_name = "\u98ce\u8680\u56fe\u817e"
			definition.description = "存活时在本格提供永久气元素源。被摧毁时，尝试将每名相邻单位沿远离图腾的方向强制移动 1 格，并向本格及相邻格施加气元素；没有合法落点的单位留在原格。"
			definition.max_health = 5
			definition.blocks_line_of_sight = false
			definition.persistent_element = BattleSurfaceState.Element.AIR
			definition.map_color = Color(0.55, 0.78, 0.82)
		Kind.UNSTABLE_PILLAR:
			definition.display_name = "\u4e0d\u7a33\u5899\u67f1"
			definition.description = "被摧毁时，沿伤害来源指向墙柱的方向最多倒塌 2 格。每个倒塌格中的单位和对象受到 4 点环境伤害；存活单位随后尝试远离墙柱强制移动 1 格。结算后，在每个没有单位或对象的倒塌格生成建筑残骸。"
			definition.max_health = 8
			definition.blocks_line_of_sight = true
			definition.map_color = Color(0.48, 0.45, 0.41)
		Kind.RUBBLE:
			definition.display_name = "\u5efa\u7b51\u6b8b\u9ab8"
			definition.description = "存活时在本格提供永久土元素源；被摧毁时移除该元素源。"
			definition.max_health = 5
			definition.blocks_line_of_sight = true
			definition.persistent_element = BattleSurfaceState.Element.EARTH
			definition.map_color = Color(0.38, 0.36, 0.31)
		Kind.ELEMENTAL_TRAP:
			definition.display_name = "元素陷阱"
			definition.description = "受到攻击后，在该攻击完整结算后爆炸，将当前元素地表扩散至相邻合法格。"
			definition.max_health = 1
			definition.blocks_movement = false
			definition.blocks_line_of_sight = false
			definition.map_color = Color(0.88, 0.68, 0.20)
		_:
			definition.display_name = "\u6218\u573a\u5bf9\u8c61"
	return definition
