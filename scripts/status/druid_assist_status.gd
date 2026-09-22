extends StatusEffect
class_name DruidAssistStatus

var source_unit_id: int = 0
var expires_on_source_turn: int = -1
var last_used_active_turn_serial: int = -1


func _init() -> void:
	status_id = "druid_assist"
	display_name = "协猎"
