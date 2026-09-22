extends StatusEffect
class_name DruidElementChargeStatus

var source_unit_id: int = 0
var expires_on_source_turn: int = -1
var element: int = BattleSurfaceState.Element.NONE


func _init() -> void:
	status_id = "druid_element_charge"
	display_name = "赋灵"


func modify_strike_context(_unit: BattleUnitState, context: Dictionary = {}) -> void:
	context["druid_element"] = element
	stacks = 0
