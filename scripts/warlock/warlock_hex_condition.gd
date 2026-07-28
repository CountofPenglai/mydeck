extends Resource
class_name WarlockHexCondition

@export_range(0, 12, 1) var minimum_face_down_curses: int = 0
@export var required_keywords: PackedStringArray = []


func is_satisfied(caster: BattleUnitState) -> bool:
	return caster != null and caster.meets_warlock_hex_conditions(
		minimum_face_down_curses,
		required_keywords
	)
