extends RefCounted
class_name EquipmentActionPayment

var unit: BattleUnitState
var ap_cost: int = 0
var resource_name: String = ""
var resource_cost: int = 0
var ap_before: int = 0
var resource_before: int = 0
var active: bool = false


func reserve(
	target: BattleUnitState,
	requested_ap_cost: int,
	requested_resource_name: String,
	requested_resource_cost: int
) -> bool:
	if target == null:
		return false
	unit = target
	ap_cost = maxi(0, requested_ap_cost)
	resource_name = requested_resource_name
	resource_cost = maxi(0, requested_resource_cost)
	ap_before = target.current_ap
	resource_before = target.get_class_resource_value(requested_resource_name)
	if ap_before < ap_cost or resource_before < resource_cost:
		return false

	target.current_ap -= ap_cost
	if resource_cost > 0 and not target.consume_class_resource(resource_name, resource_cost):
		target.current_ap = ap_before
		return false
	active = true
	return true


func commit() -> void:
	active = false


func rollback() -> void:
	if not active or unit == null:
		return
	unit.current_ap = ap_before
	if resource_cost > 0:
		var resource := unit.get_class_resource(resource_name)
		if resource != null:
			resource.current_value = clampi(resource_before, 0, resource.get_max_value())
	active = false
