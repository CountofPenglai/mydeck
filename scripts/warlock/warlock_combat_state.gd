extends RefCounted
class_name WarlockCombatState

var mana: int = 0
var preparation_resolved: bool = false
var _face_down_curses: Dictionary = {}
var _curse_counters: Dictionary = {}


func reset_for_battle() -> void:
	mana = 0
	preparation_resolved = false
	_face_down_curses.clear()
	_curse_counters.clear()


func start_turn() -> void:
	preparation_resolved = false


func get_mana() -> int:
	return maxi(0, mana)


func gain_mana(amount: int) -> int:
	var actual := maxi(0, amount)
	mana += actual
	return actual


func can_pay_mana(amount: int) -> bool:
	return get_mana() >= maxi(0, amount)


func pay_mana(amount: int) -> bool:
	var cost := maxi(0, amount)
	if not can_pay_mana(cost):
		return false
	mana -= cost
	return true


func is_face_down(curse: CurseInstance) -> bool:
	return curse != null and bool(_face_down_curses.get(curse, false))


func set_face_down(curse: CurseInstance, face_down: bool) -> bool:
	if curse == null or is_face_down(curse) == face_down:
		return false
	if face_down:
		_face_down_curses[curse] = true
		gain_mana(1)
	else:
		_face_down_curses.erase(curse)
		clear_curse_counters(curse)
	return true


func remove_curse(curse: CurseInstance) -> void:
	if curse == null:
		return
	_face_down_curses.erase(curse)
	_curse_counters.erase(curse)


func get_face_down_curses(curses: Array[CurseInstance]) -> Array[CurseInstance]:
	var result: Array[CurseInstance] = []
	for curse in curses:
		if is_face_down(curse):
			result.append(curse)
	return result


func get_face_down_count(curses: Array[CurseInstance]) -> int:
	return get_face_down_curses(curses).size()


func has_face_down_keyword(curses: Array[CurseInstance], keyword: String) -> bool:
	if keyword.is_empty():
		return true
	for curse in get_face_down_curses(curses):
		if curse.definition != null and curse.definition.hex_keywords.has(keyword):
			return true
	return false


func meets_hex_conditions(curses: Array[CurseInstance], minimum_count: int, required_keywords: PackedStringArray) -> bool:
	if get_face_down_count(curses) < maxi(0, minimum_count):
		return false
	for keyword in required_keywords:
		if not has_face_down_keyword(curses, keyword):
			return false
	return true


func get_curse_counters(curse: CurseInstance) -> Dictionary:
	if curse == null:
		return {}
	if not _curse_counters.has(curse):
		_curse_counters[curse] = {}
	return _curse_counters[curse] as Dictionary


func add_curse_counter(curse: CurseInstance, counter_id: String, amount: int = 1) -> int:
	if curse == null or counter_id.is_empty() or amount <= 0:
		return 0
	var counters := get_curse_counters(curse)
	counters[counter_id] = maxi(0, int(counters.get(counter_id, 0)) + amount)
	return amount


func corrupt_face_down_curse_counters(curses: Array[CurseInstance], amount: int = 1) -> int:
	var changed_types := 0
	for curse in get_face_down_curses(curses):
		var counters := get_curse_counters(curse)
		for counter_value in counters.keys():
			var counter_id := str(counter_value)
			if int(counters.get(counter_id, 0)) <= 0:
				continue
			counters[counter_id] = int(counters[counter_id]) + maxi(0, amount)
			changed_types += 1
	return changed_types


func clear_curse_counters(curse: CurseInstance) -> void:
	if curse != null:
		_curse_counters.erase(curse)


func snapshot() -> Dictionary:
	return {
		"mana": mana,
		"preparation_resolved": preparation_resolved,
		"face_down_curses": _face_down_curses.duplicate(true),
		"curse_counters": _curse_counters.duplicate(true),
	}


func restore(snapshot_data: Dictionary) -> void:
	mana = maxi(0, int(snapshot_data.get("mana", 0)))
	preparation_resolved = bool(snapshot_data.get("preparation_resolved", false))
	_face_down_curses = (snapshot_data.get("face_down_curses", {}) as Dictionary).duplicate(true)
	_curse_counters = (snapshot_data.get("curse_counters", {}) as Dictionary).duplicate(true)
