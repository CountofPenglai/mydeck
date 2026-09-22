extends RefCounted
class_name BattleCurseSuppression


var _suppressed: Dictionary = {}


func suppress(curse: CurseInstance) -> bool:
	if curse == null or not curse.is_active_in_curse_zone() or _suppressed.has(curse):
		return false
	_suppressed[curse] = true
	return true


func is_suppressed(curse: CurseInstance) -> bool:
	return curse != null and _suppressed.has(curse)


func clear() -> void:
	_suppressed.clear()
