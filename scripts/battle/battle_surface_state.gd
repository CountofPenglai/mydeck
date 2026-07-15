extends RefCounted
class_name BattleSurfaceState

enum Element {
	NONE,
	FIRE,
	WATER,
	EARTH,
	AIR,
	STEAM,
	LAVA,
	BLAZE,
	POISON_BOG,
	ICE,
	SANDSTORM,
}

const BASE_ELEMENTS: Array[int] = [Element.FIRE, Element.WATER, Element.EARTH, Element.AIR]

var _cells: Dictionary = {}


func setup(map_data: BattleMapData) -> void:
	_cells.clear()
	if map_data == null:
		return
	for entry in map_data.element_cells:
		if entry == null or not map_data.is_valid_cell(entry.cell):
			continue
		if not BASE_ELEMENTS.has(entry.element):
			continue
		_cells[entry.cell] = {
			"base": entry.element,
			"current": entry.element,
			"expires_round": -1,
		}


func get_element(cell: Vector2i) -> int:
	var state: Dictionary = _cells.get(cell, {}) as Dictionary
	return int(state.get("current", Element.NONE))


func get_base_element(cell: Vector2i) -> int:
	var state: Dictionary = _cells.get(cell, {}) as Dictionary
	return int(state.get("base", Element.NONE))


func set_base_element(cell: Vector2i, element: int) -> void:
	if not BASE_ELEMENTS.has(element):
		return
	_cells[cell] = {
		"base": element,
		"current": element,
		"expires_round": -1,
	}


func create_advanced_surface(cell: Vector2i, element: int, current_round: int) -> void:
	if element < Element.STEAM or element > Element.SANDSTORM:
		return
	var state: Dictionary = _cells.get(cell, {}) as Dictionary
	_cells[cell] = {
		"base": int(state.get("base", Element.NONE)),
		"current": element,
		"expires_round": current_round + 3,
	}


func advance_round(current_round: int) -> void:
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		var state: Dictionary = _cells.get(cell, {}) as Dictionary
		var expires_round := int(state.get("expires_round", -1))
		if expires_round < 0 or current_round < expires_round:
			continue
		var base_element := int(state.get("base", Element.NONE))
		if base_element == Element.NONE:
			_cells.erase(cell)
		else:
			state["current"] = base_element
			state["expires_round"] = -1
			_cells[cell] = state


func get_movement_cost(cell: Vector2i) -> int:
	var element := get_element(cell)
	return 2 if element == Element.WATER or element == Element.POISON_BOG else 1


func is_concealing(cell: Vector2i) -> bool:
	var element := get_element(cell)
	return element == Element.STEAM or element == Element.SANDSTORM


func get_component_elements(element: int) -> Array[int]:
	var result: Array[int] = []
	match element:
		Element.STEAM:
			result.assign([Element.FIRE, Element.WATER])
		Element.LAVA:
			result.assign([Element.FIRE, Element.EARTH])
		Element.BLAZE:
			result.assign([Element.FIRE, Element.AIR])
		Element.POISON_BOG:
			result.assign([Element.WATER, Element.EARTH])
		Element.ICE:
			result.assign([Element.WATER, Element.AIR])
		Element.SANDSTORM:
			result.assign([Element.EARTH, Element.AIR])
		_:
			if BASE_ELEMENTS.has(element):
				result.append(element)
	return result


static func reaction_for(first: int, second: int) -> int:
	var low := mini(first, second)
	var high := maxi(first, second)
	if low == Element.FIRE and high == Element.WATER:
		return Element.STEAM
	if low == Element.FIRE and high == Element.EARTH:
		return Element.LAVA
	if low == Element.FIRE and high == Element.AIR:
		return Element.BLAZE
	if low == Element.WATER and high == Element.EARTH:
		return Element.POISON_BOG
	if low == Element.WATER and high == Element.AIR:
		return Element.ICE
	if low == Element.EARTH and high == Element.AIR:
		return Element.SANDSTORM
	return Element.NONE


static func label(element: int) -> String:
	match element:
		Element.FIRE: return "火"
		Element.WATER: return "水"
		Element.EARTH: return "土"
		Element.AIR: return "风"
		Element.STEAM: return "蒸汽"
		Element.LAVA: return "熔岩"
		Element.BLAZE: return "烈焰"
		Element.POISON_BOG: return "毒沼"
		Element.ICE: return "冰面"
		Element.SANDSTORM: return "沙暴"
		_: return "无"


static func color(element: int) -> Color:
	match element:
		Element.FIRE: return Color(0.9, 0.2, 0.08, 0.34)
		Element.WATER: return Color(0.1, 0.45, 0.9, 0.32)
		Element.EARTH: return Color(0.35, 0.5, 0.18, 0.34)
		Element.AIR: return Color(0.65, 0.85, 0.9, 0.28)
		Element.STEAM: return Color(0.75, 0.78, 0.8, 0.42)
		Element.LAVA: return Color(0.95, 0.15, 0.02, 0.5)
		Element.BLAZE: return Color(1.0, 0.48, 0.05, 0.48)
		Element.POISON_BOG: return Color(0.3, 0.58, 0.12, 0.46)
		Element.ICE: return Color(0.45, 0.8, 1.0, 0.44)
		Element.SANDSTORM: return Color(0.68, 0.58, 0.28, 0.42)
		_: return Color.TRANSPARENT
