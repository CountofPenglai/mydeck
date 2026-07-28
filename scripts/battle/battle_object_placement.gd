extends Resource
class_name BattleObjectPlacement

@export var cell: Vector2i = Vector2i.ZERO
@export_enum(
	"Explosive Barrel",
	"Water Cistern",
	"Wind Totem",
	"Unstable Pillar",
	"Rubble"
) var object_kind: int = BattleObjectDefinition.Kind.EXPLOSIVE_BARREL
@export var fall_direction: Vector2i = Vector2i(1, 0)
