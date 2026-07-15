extends StatusEffect
class_name TemporaryCurseReportStatus

var projected_curse: CurseInstance
var expires_after_turn_serial: int = -1


func _init() -> void:
	status_id = "temporary_curse_report"
	display_name = "报之投射"


func on_turn_end(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit == null or unit.turn_serial < expires_after_turn_serial:
		return
	if projected_curse != null:
		unit.curse_zone.erase(projected_curse)
	stacks = 0
