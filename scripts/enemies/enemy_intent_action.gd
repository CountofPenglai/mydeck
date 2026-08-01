extends RefCounted
class_name EnemyIntentAction

enum Kind {
	CARD,
	BASIC_ATTACK,
	MOVE,
}

var kind: int = Kind.CARD
var label: String = ""
var card: CardData
var targets: Array = []
var cell: Vector2i = BattleHexGrid.INVALID_CELL
var ap_cost: int = 0
var score: float = 0.0
var provided_tags: PackedStringArray = []


func is_valid() -> bool:
	match kind:
		Kind.CARD:
			return card != null
		Kind.BASIC_ATTACK:
			return targets.size() == 1 and targets[0] is BattleUnitState
		Kind.MOVE:
			return cell != BattleHexGrid.INVALID_CELL
	return false
