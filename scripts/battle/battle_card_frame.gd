extends RefCounted
class_name BattleCardFrame

var user: BattleUnitState
var card: CardData
var targets: Array = []
var context: CardPlayContext


static func create(new_user: BattleUnitState, new_card: CardData, new_targets: Array, new_context: CardPlayContext) -> BattleCardFrame:
	var frame := BattleCardFrame.new()
	frame.user = new_user
	frame.card = new_card
	frame.targets = new_targets.duplicate()
	frame.context = new_context
	return frame

