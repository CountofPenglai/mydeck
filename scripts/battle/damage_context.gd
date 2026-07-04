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


func reduce_amount(value: int) -> int:
	var reduction := mini(amount, maxi(0, value))
	amount = maxi(0, amount - reduction)
	if amount <= 0:
		prevented = true
	return reduction
