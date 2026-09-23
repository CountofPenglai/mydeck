extends RefCounted
class_name BattleUnitTargetChoiceState

var owner: BattleUnitState
var source_card: CardData
var prompt := ""
var continuation: Callable
var candidates: Array = []
var target_filter: Callable

func get_live_targets() -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	for target in candidates:
		if target == null or not target.is_alive() or not target.is_deployed:
			continue
		if target_filter.is_valid() and not target_filter.call(target):
			continue
		result.append(target)
	return result
