extends StatusEffect
class_name DruidRootOathStatus


var source_unit_id: int = 0
var expires_on_source_turn: int = -1


func _init() -> void:
	status_id = "druid_root_oath"
	display_name = "群根盟誓"
	stacks = 2


func get_damage_bonus(_unit: BattleUnitState, context: Dictionary = {}) -> int:
	return stacks if bool(context.get("strike", false)) and context.get("equipment") != null else 0
