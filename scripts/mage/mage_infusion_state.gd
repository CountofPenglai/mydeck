extends RefCounted
class_name MageInfusionState

const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")
const ALL_ELEMENT_MASK := 0b1111

var _stones_by_faction: Dictionary = {}
var _formation_turn_by_faction: Dictionary = {}


func reset() -> void:
	_stones_by_faction.clear()
	_formation_turn_by_faction.clear()


func place_stone(faction: int, cell: Vector2i, element: int, current_turn_serial: int = -1) -> bool:
	var bit := _element_bit(element)
	if bit == 0:
		return false
	var stones := _get_faction_cells(faction, true)
	var previous_mask := int(stones.get(cell, 0))
	if (previous_mask & bit) != 0:
		return false
	var next_mask := previous_mask | bit
	stones[cell] = next_mask
	if previous_mask != ALL_ELEMENT_MASK and next_mask == ALL_ELEMENT_MASK:
		_get_formation_turns(faction, true)[cell] = current_turn_serial
	return true


func has_stone(faction: int, cell: Vector2i, element: int) -> bool:
	var bit := _element_bit(element)
	return bit != 0 and (get_stone_mask(faction, cell) & bit) != 0


func remove_stone(faction: int, cell: Vector2i, element: int) -> bool:
	var bit := _element_bit(element)
	if bit == 0:
		return false
	var stones := _get_faction_cells(faction, false)
	var previous_mask := int(stones.get(cell, 0))
	if (previous_mask & bit) == 0:
		return false
	var next_mask := previous_mask & ~bit
	if next_mask == 0:
		stones.erase(cell)
	else:
		stones[cell] = next_mask
	_get_formation_turns(faction, false).erase(cell)
	return true


func get_stone_mask(faction: int, cell: Vector2i) -> int:
	return int(_get_faction_cells(faction, false).get(cell, 0))


func get_elements(faction: int, cell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var mask := get_stone_mask(faction, cell)
	for element in BattleSurfaceState.BASE_ELEMENTS:
		if (mask & _element_bit(element)) != 0:
			result.append(element)
	return result


func has_primordial(faction: int, cell: Vector2i) -> bool:
	return get_stone_mask(faction, cell) == ALL_ELEMENT_MASK


func is_primordial_available(faction: int, cell: Vector2i, current_turn_serial: int) -> bool:
	if not has_primordial(faction, cell):
		return false
	var formed_turn := int(_get_formation_turns(faction, false).get(cell, -1))
	return formed_turn < 0 or formed_turn != current_turn_serial


func consume_primordial(faction: int, cell: Vector2i) -> bool:
	if not has_primordial(faction, cell):
		return false
	_get_faction_cells(faction, false).erase(cell)
	_get_formation_turns(faction, false).erase(cell)
	return true


func snapshot() -> Dictionary:
	return {
		"stones": _stones_by_faction.duplicate(true),
		"formation_turns": _formation_turn_by_faction.duplicate(true),
	}


func restore(snapshot_data: Dictionary) -> void:
	_stones_by_faction = (snapshot_data.get("stones", {}) as Dictionary).duplicate(true)
	_formation_turn_by_faction = (snapshot_data.get("formation_turns", {}) as Dictionary).duplicate(true)


func _get_faction_cells(faction: int, create: bool) -> Dictionary:
	if _stones_by_faction.has(faction):
		return _stones_by_faction[faction] as Dictionary
	if not create:
		return {}
	var cells: Dictionary = {}
	_stones_by_faction[faction] = cells
	return cells


func _get_formation_turns(faction: int, create: bool) -> Dictionary:
	if _formation_turn_by_faction.has(faction):
		return _formation_turn_by_faction[faction] as Dictionary
	if not create:
		return {}
	var turns: Dictionary = {}
	_formation_turn_by_faction[faction] = turns
	return turns


func _element_bit(element: int) -> int:
	var index := BattleSurfaceState.BASE_ELEMENTS.find(element)
	return 0 if index < 0 else 1 << index
