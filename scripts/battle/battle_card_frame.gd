extends RefCounted
class_name BattleCardFrame

var user: BattleUnitState
var card: CardData
var targets: Array = []
var context: CardPlayContext
var discard_after_play: bool = true
var resolved_successfully: bool = false


static func create(new_user: BattleUnitState, new_card: CardData, new_targets: Array, new_context: CardPlayContext, should_discard_after_play: bool = true) -> BattleCardFrame:
	var frame := BattleCardFrame.new()
	frame.user = new_user
	frame.card = new_card
	frame.targets = new_targets.duplicate()
	frame.context = new_context
	frame.discard_after_play = should_discard_after_play
	return frame
