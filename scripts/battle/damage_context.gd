extends RefCounted
class_name DamageContext

var controller: BattleController
var source: BattleUnitState
var target: BattleUnitState
var amount: int = 0
var label: String = "伤害"
var prevented: bool = false
var prevented_by = null


static func create(new_controller: BattleController, new_source: BattleUnitState, new_target: BattleUnitState, new_amount: int, new_label: String = "伤害") -> DamageContext:
	var context := DamageContext.new()
	context.controller = new_controller
	context.source = new_source
	context.target = new_target
	context.amount = maxi(0, new_amount)
	context.label = new_label
	return context


func prevent(by_effect = null) -> void:
	prevented = true
	prevented_by = by_effect


func to_dict() -> Dictionary:
	return {
		"controller": controller,
		"source": source,
		"target": target,
		"amount": amount,
		"label": label,
		"prevented": prevented,
		"prevented_by": prevented_by,
		"damage_context": self,
	}


func apply_dict(values: Dictionary) -> void:
	amount = int(values.get("amount", amount))
	prevented = bool(values.get("prevented", prevented))
	prevented_by = values.get("prevented_by", prevented_by)

