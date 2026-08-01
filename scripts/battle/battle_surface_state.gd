extends RefCounted
class_name BattleSurfaceState

signal state_changed(cell: Vector2i)

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

enum Terrain {
	NONE,
	SHALLOW_WATER,
	MAGMA_FISSURE,
	ABYSS,
}

enum Channel {
	NONE,
	GROUND,
	AIR,
}

const BASE_ELEMENTS: Array[int] = [Element.FIRE, Element.WATER, Element.EARTH, Element.AIR]
const ADVANCED_ELEMENTS: Array[int] = [
	Element.STEAM,
	Element.LAVA,
	Element.BLAZE,
	Element.POISON_BOG,
	Element.ICE,
	Element.SANDSTORM,
]
const REACTION_ORDER: Array[int] = [
	Element.STEAM,
	Element.LAVA,
	Element.BLAZE,
	Element.POISON_BOG,
	Element.ICE,
	Element.SANDSTORM,
]

var _map_data: BattleMapData
var _cells: Dictionary = {}
var _collected_sources: Dictionary = {}
var _next_source_serial: int = 1


func setup(map_data: BattleMapData) -> void:
	_map_data = map_data
	_cells.clear()
	_collected_sources.clear()
	_next_source_serial = 1
	if map_data == null:
		return
	for terrain_entry in map_data.terrain_cells:
		if terrain_entry == null or not map_data.is_valid_cell(terrain_entry.cell):
			continue
		if terrain_entry.terrain <= Terrain.NONE or terrain_entry.terrain > Terrain.ABYSS:
			continue
		set_terrain(terrain_entry.cell, terrain_entry.terrain)
		var terrain_element := _element_for_terrain(terrain_entry.terrain)
		if terrain_element != Element.NONE:
			add_persistent_source(
				terrain_entry.cell,
				terrain_element,
				"terrain:%d:%d" % [terrain_entry.cell.x, terrain_entry.cell.y],
				"terrain"
			)
	for entry in map_data.element_cells:
		if entry == null or not map_data.is_valid_cell(entry.cell):
			continue
		if not BASE_ELEMENTS.has(entry.element):
			continue
		add_persistent_source(
			entry.cell,
			entry.element,
			"legacy:%d:%d:%d" % [entry.cell.x, entry.cell.y, entry.element],
			"map"
		)


func clear() -> void:
	_cells.clear()
	_collected_sources.clear()
	_next_source_serial = 1


func set_terrain(cell: Vector2i, terrain: int) -> bool:
	if not _is_valid_cell(cell) or terrain < Terrain.NONE or terrain > Terrain.ABYSS:
		return false
	var state: Dictionary = _get_or_create_cell(cell)
	var previous := int(state.get("terrain", Terrain.NONE))
	var sources: Array = state.get("sources", []) as Array
	for index in range(sources.size() - 1, -1, -1):
		var source: Dictionary = sources[index] as Dictionary
		if str(source.get("kind", "")) == "terrain":
			sources.remove_at(index)
	var terrain_element := _element_for_terrain(terrain)
	if terrain_element != Element.NONE:
		sources.append({
			"id": "terrain:%d:%d" % [cell.x, cell.y],
			"element": terrain_element,
			"kind": "terrain",
		})
	state["terrain"] = terrain
	state["sources"] = sources
	_store_or_erase(cell, state)
	state_changed.emit(cell)
	return previous != terrain


func get_terrain(cell: Vector2i) -> int:
	var state: Dictionary = _get_cell(cell)
	return int(state.get("terrain", Terrain.NONE))


func is_terrain_effective(cell: Vector2i, terrain: int = -1) -> bool:
	var state: Dictionary = _get_cell(cell)
	if not (state.get("ground", {}) as Dictionary).is_empty():
		return false
	var current: int = int(state.get("terrain", Terrain.NONE))
	return current != Terrain.NONE if terrain < 0 else current == terrain


func add_persistent_source(
	cell: Vector2i,
	element: int,
	source_id: String = "",
	source_kind: String = "effect"
) -> String:
	if not _is_valid_cell(cell) or not BASE_ELEMENTS.has(element):
		return ""
	var actual_id := source_id
	if actual_id.is_empty():
		actual_id = "source:%d" % _next_source_serial
		_next_source_serial += 1
	var state: Dictionary = _get_or_create_cell(cell)
	var sources: Array = state.get("sources", []) as Array
	for value in sources:
		var source: Dictionary = value as Dictionary
		if str(source.get("id", "")) == actual_id:
			source["element"] = element
			source["kind"] = source_kind
			_store_or_erase(cell, state)
			state_changed.emit(cell)
			return actual_id
	sources.append({"id": actual_id, "element": element, "kind": source_kind})
	state["sources"] = sources
	_store_or_erase(cell, state)
	state_changed.emit(cell)
	return actual_id


func remove_persistent_source(cell: Vector2i, source_id: String) -> bool:
	var state: Dictionary = _get_cell(cell)
	var sources: Array = state.get("sources", []) as Array
	for index in range(sources.size() - 1, -1, -1):
		var source: Dictionary = sources[index] as Dictionary
		if str(source.get("id", "")) == source_id:
			sources.remove_at(index)
			state["sources"] = sources
			_store_or_erase(cell, state)
			state_changed.emit(cell)
			return true
	return false


func add_residue(cell: Vector2i, element: int, current_round: int) -> bool:
	if not _is_valid_cell(cell) or not BASE_ELEMENTS.has(element):
		return false
	var state: Dictionary = _get_or_create_cell(cell)
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	var entry: Dictionary = residues.get(element, {}) as Dictionary
	if entry.is_empty():
		entry = {
			"id": "residue:%d" % _next_source_serial,
			"element": element,
			"kind": "residue",
		}
		_next_source_serial += 1
	entry["expires_round"] = current_round + 3
	residues[element] = entry
	state["residues"] = residues
	_store_or_erase(cell, state)
	state_changed.emit(cell)
	return true


func remove_residue(cell: Vector2i, element: int) -> bool:
	var state: Dictionary = _get_cell(cell)
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	if not residues.has(element):
		return false
	residues.erase(element)
	state["residues"] = residues
	_store_or_erase(cell, state)
	state_changed.emit(cell)
	return true


func apply_base_element(cell: Vector2i, element: int, current_round: int) -> Dictionary:
	var result := {
		"cell": cell,
		"incoming": element,
		"reactions": [],
		"consumed_residues": [],
		"residue_created": false,
	}
	if not _is_valid_cell(cell) or not BASE_ELEMENTS.has(element):
		return result

	var reaction_elements: Array[int] = get_reaction_elements(cell)
	var reactions: Array[int] = []
	for other in reaction_elements:
		var reaction := reaction_for(element, other)
		if reaction != Element.NONE and not reactions.has(reaction):
			reactions.append(reaction)
	reactions.sort_custom(func(left: int, right: int) -> bool:
		return REACTION_ORDER.find(left) < REACTION_ORDER.find(right)
	)

	if reactions.is_empty():
		result["residue_created"] = add_residue(cell, element, current_round)
		return result

	var state: Dictionary = _get_cell(cell)
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	for reaction in reactions:
		for component in get_component_elements(reaction):
			if component == element or not residues.has(component):
				continue
			residues.erase(component)
			(result["consumed_residues"] as Array).append(component)
		create_advanced_surface(cell, reaction, current_round)
	state = _get_cell(cell)
	state["residues"] = residues
	_store_or_erase(cell, state)
	result["reactions"] = reactions
	state_changed.emit(cell)
	return result


func create_advanced_surface(cell: Vector2i, element: int, current_round: int) -> void:
	if not _is_valid_cell(cell) or not ADVANCED_ELEMENTS.has(element):
		return
	var state: Dictionary = _get_or_create_cell(cell)
	var channel := get_channel_for_element(element)
	var key := "ground" if channel == Channel.GROUND else "air"
	var current: Dictionary = state.get(key, {}) as Dictionary
	if int(current.get("element", Element.NONE)) == element:
		current["expires_round"] = current_round + 3
	else:
		current = {
			"id": "effect:%d" % _next_source_serial,
			"element": element,
			"expires_round": current_round + 3,
			"kind": "advanced",
		}
		_next_source_serial += 1
	state[key] = current
	_store_or_erase(cell, state)
	state_changed.emit(cell)


func get_ground_effect(cell: Vector2i) -> int:
	var state: Dictionary = _get_cell(cell)
	var effect: Dictionary = state.get("ground", {}) as Dictionary
	return int(effect.get("element", Element.NONE))


func get_air_effect(cell: Vector2i) -> int:
	var state: Dictionary = _get_cell(cell)
	var effect: Dictionary = state.get("air", {}) as Dictionary
	return int(effect.get("element", Element.NONE))


func get_element(cell: Vector2i) -> int:
	var ground := get_ground_effect(cell)
	if ground != Element.NONE:
		return ground
	var air := get_air_effect(cell)
	if air != Element.NONE:
		return air
	var elements: Array[int] = get_readable_elements(cell)
	return elements[0] if not elements.is_empty() else Element.NONE


func get_base_element(cell: Vector2i) -> int:
	var elements: Array[int] = get_reaction_elements(cell)
	return elements[0] if not elements.is_empty() else Element.NONE


func set_base_element(cell: Vector2i, element: int) -> void:
	if not _is_valid_cell(cell) or not BASE_ELEMENTS.has(element):
		return
	var state: Dictionary = _get_or_create_cell(cell)
	state["sources"] = []
	state["residues"] = {}
	add_persistent_source(
		cell,
		element,
		"legacy:%d:%d" % [cell.x, cell.y],
		"legacy"
	)


func get_reaction_elements(cell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var state: Dictionary = _get_cell(cell)
	for value in state.get("sources", []) as Array:
		var source: Dictionary = value as Dictionary
		_append_base_element(result, int(source.get("element", Element.NONE)))
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	for element in BASE_ELEMENTS:
		if residues.has(element):
			_append_base_element(result, element)
	return result


func get_readable_elements(cell: Vector2i) -> Array[int]:
	var result: Array[int] = get_reaction_elements(cell)
	for component in get_component_elements(get_ground_effect(cell)):
		_append_base_element(result, component)
	for component in get_component_elements(get_air_effect(cell)):
		_append_base_element(result, component)
	return result


func get_collectible_entries(cell: Vector2i, collector_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = _get_cell(cell)
	for value in state.get("sources", []) as Array:
		var source: Dictionary = value as Dictionary
		if not _collected_sources.has(_collection_key(collector_id, str(source.get("id", "")))):
			result.append(source.duplicate(true))
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	for element in BASE_ELEMENTS:
		if residues.has(element):
			result.append((residues[element] as Dictionary).duplicate(true))
	for key in ["ground", "air"]:
		var effect: Dictionary = state.get(key, {}) as Dictionary
		if effect.is_empty():
			continue
		if _collected_sources.has(_collection_key(collector_id, str(effect.get("id", "")))):
			continue
		var collectible := effect.duplicate(true)
		collectible["components"] = get_component_elements(int(effect.get("element", Element.NONE)))
		result.append(collectible)
	return result


func commit_collection(
	cell: Vector2i,
	collector_id: String,
	entries: Array[Dictionary],
	successful_elements: Array[int]
) -> void:
	if successful_elements.is_empty():
		return
	var state: Dictionary = _get_cell(cell)
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	var changed := false
	for entry in entries:
		var components: Array[int] = []
		if entry.has("components"):
			components.assign(entry.get("components", []) as Array)
		else:
			components.append(int(entry.get("element", Element.NONE)))
		var collected := false
		for component in components:
			if successful_elements.has(component):
				collected = true
				break
		if not collected:
			continue
		if str(entry.get("kind", "")) == "residue":
			var residue_element := int(entry.get("element", Element.NONE))
			if residues.has(residue_element):
				residues.erase(residue_element)
				changed = true
		else:
			_collected_sources[_collection_key(collector_id, str(entry.get("id", "")))] = true
	state["residues"] = residues
	_store_or_erase(cell, state)
	if changed:
		state_changed.emit(cell)


func advance_round(current_round: int) -> void:
	var changed_cells: Array[Vector2i] = []
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		var state: Dictionary = _get_cell(cell)
		var changed := false
		for key in ["ground", "air"]:
			var effect: Dictionary = state.get(key, {}) as Dictionary
			var expires_round := int(effect.get("expires_round", -1))
			if expires_round >= 0 and current_round >= expires_round:
				state[key] = {}
				changed = true
		var residues: Dictionary = state.get("residues", {}) as Dictionary
		for element_value in residues.keys():
			var residue: Dictionary = residues.get(element_value, {}) as Dictionary
			var expires_round := int(residue.get("expires_round", -1))
			if expires_round >= 0 and current_round >= expires_round:
				residues.erase(element_value)
				changed = true
		state["residues"] = residues
		_store_or_erase(cell, state)
		if changed:
			changed_cells.append(cell)
	for cell in changed_cells:
		state_changed.emit(cell)


func get_movement_cost(cell: Vector2i) -> int:
	var ground := get_ground_effect(cell)
	if ground != Element.NONE:
		return 2 if ground == Element.POISON_BOG else 1
	var terrain := get_terrain(cell)
	return 2 if terrain == Terrain.SHALLOW_WATER or terrain == Terrain.ABYSS else 1


func stops_movement_on_entry(cell: Vector2i) -> bool:
	return get_ground_effect(cell) == Element.ICE


func is_concealing(cell: Vector2i) -> bool:
	var air := get_air_effect(cell)
	return air == Element.STEAM or air == Element.SANDSTORM


func get_damage_bonus(cell: Vector2i) -> int:
	match get_ground_effect(cell):
		Element.POISON_BOG:
			return -1
	return 2 if get_air_effect(cell) == Element.BLAZE else 0


func get_damage_reduction(cell: Vector2i, is_ranged: bool) -> int:
	var result := 0
	if get_ground_effect(cell) == Element.ICE:
		result -= 1
	if is_ranged and get_air_effect(cell) == Element.STEAM:
		result += 1
	return result


func is_ranged_range_capped(cell: Vector2i) -> bool:
	return get_air_effect(cell) == Element.SANDSTORM


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


func get_cell_snapshot(cell: Vector2i) -> Dictionary:
	var state: Dictionary = _get_cell(cell)
	return {
		"terrain": int(state.get("terrain", Terrain.NONE)),
		"ground_effect": get_ground_effect(cell),
		"ground_effect_state": (state.get("ground", {}) as Dictionary).duplicate(true),
		"air_effect": get_air_effect(cell),
		"air_effect_state": (state.get("air", {}) as Dictionary).duplicate(true),
		"persistent_sources": (state.get("sources", []) as Array).duplicate(true),
		"residues": (state.get("residues", {}) as Dictionary).duplicate(true),
		"readable_elements": get_readable_elements(cell),
	}


func get_all_active_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value in _cells.keys():
		result.append(cell_value as Vector2i)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return result


static func get_channel_for_element(element: int) -> int:
	if [Element.LAVA, Element.POISON_BOG, Element.ICE].has(element):
		return Channel.GROUND
	if [Element.STEAM, Element.BLAZE, Element.SANDSTORM].has(element):
		return Channel.AIR
	return Channel.NONE


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
		Element.FIRE: return "\u706b"
		Element.WATER: return "\u6c34"
		Element.EARTH: return "\u571f"
		Element.AIR: return "\u6c14"
		Element.STEAM: return "\u84b8\u6c7d"
		Element.LAVA: return "\u7194\u5ca9"
		Element.BLAZE: return "\u70c8\u7130"
		Element.POISON_BOG: return "\u6bd2\u6cbc"
		Element.ICE: return "\u51b0\u9762"
		Element.SANDSTORM: return "\u6c99\u66b4"
		_: return "\u65e0"


static func terrain_label(terrain: int) -> String:
	match terrain:
		Terrain.SHALLOW_WATER: return "\u6d45\u6c34"
		Terrain.MAGMA_FISSURE: return "\u5ca9\u6d46\u88c2\u9699"
		Terrain.ABYSS: return "\u6df1\u6e0a"
		_: return "\u666e\u901a\u5730\u9762"


static func terrain_description(terrain: int) -> String:
	match terrain:
		Terrain.SHALLOW_WATER:
			return "没有地面效果覆盖时，非飞行单位进入该格需要 2 点移动距离。该地形始终提供永久水元素源。"
		Terrain.MAGMA_FISSURE:
			return "没有地面效果覆盖时，非飞行单位进入该格以及在该格开始回合时受到 3 点环境伤害。该地形始终提供永久火元素源。"
		Terrain.ABYSS:
			return "没有地面效果覆盖时，非飞行单位进入该格需要 2 点移动距离；位于该格的单位每回合打出的第一张非诅咒牌 AP 消耗 +1。该地形始终提供永久水元素源。"
		_:
			return "没有额外地形效果。"


static func element_description(element: int) -> String:
	match element:
		Element.FIRE, Element.WATER, Element.EARTH, Element.AIR:
			return "基础元素仅用于反应、采集与条件读取，不直接提供战斗加成。"
		Element.STEAM:
			return "生成时，尝试将本格的非飞行单位沿远离元素来源的方向强制移动 1 格；没有合法落点时留在原格。存在期间，本格提供隐蔽，位于本格的单位受到远程伤害时获得 1 点伤害减免。"
		Element.LAVA:
			return "生成时，本格的非飞行单位和可破坏对象受到 3 点环境伤害；存在期间，非飞行单位进入本格或在本格开始回合时再受到 3 点环境伤害。"
		Element.BLAZE:
			return "生成时，本格的非飞行单位和可破坏对象受到 2 点环境伤害。存在期间，位于本格的伤害来源每段伤害获得 +2 伤害加值；同一行动首次造成正数实际伤害后，该来源受到 1 点环境伤害。"
		Element.POISON_BOG:
			return "存在期间，进入本格需要 2 点移动距离，位于本格的单位伤害加值 -1。"
		Element.ICE:
			return "生成时，本格的非飞行单位获得 1 层冻结：主动移动的 AP 消耗 +1，持续至其下次回合结束。单位进入本格时立即停止本次移动；位于本格的单位伤害减免 -1。"
		Element.SANDSTORM:
			return "生成时，本格的非飞行单位获得致盲，使其远程范围至多为 2，持续至其下次回合结束。存在期间，本格提供隐蔽；远程打击的来源格或目标格为沙暴时，范围至多为 2。"
		_:
			return ""


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


static func terrain_color(terrain: int) -> Color:
	match terrain:
		Terrain.SHALLOW_WATER: return Color(0.08, 0.34, 0.62, 0.36)
		Terrain.MAGMA_FISSURE: return Color(0.48, 0.08, 0.02, 0.52)
		Terrain.ABYSS: return Color(0.03, 0.08, 0.12, 0.7)
		_: return Color.TRANSPARENT


func _get_or_create_cell(cell: Vector2i) -> Dictionary:
	if _cells.has(cell):
		return _cells[cell] as Dictionary
	var state := {
		"terrain": Terrain.NONE,
		"ground": {},
		"air": {},
		"sources": [],
		"residues": {},
	}
	_cells[cell] = state
	return state


func _get_cell(cell: Vector2i) -> Dictionary:
	return _cells.get(cell, {}) as Dictionary


func _store_or_erase(cell: Vector2i, state: Dictionary) -> void:
	var terrain := int(state.get("terrain", Terrain.NONE))
	var ground: Dictionary = state.get("ground", {}) as Dictionary
	var air: Dictionary = state.get("air", {}) as Dictionary
	var sources: Array = state.get("sources", []) as Array
	var residues: Dictionary = state.get("residues", {}) as Dictionary
	if terrain == Terrain.NONE and ground.is_empty() and air.is_empty() \
			and sources.is_empty() and residues.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = state


func _is_valid_cell(cell: Vector2i) -> bool:
	return _map_data == null or _map_data.is_valid_cell(cell)


func _append_base_element(target: Array[int], element: int) -> void:
	if BASE_ELEMENTS.has(element) and not target.has(element):
		target.append(element)


func _collection_key(collector_id: String, source_id: String) -> String:
	return "%s|%s" % [collector_id, source_id]


func _element_for_terrain(terrain: int) -> int:
	match terrain:
		Terrain.SHALLOW_WATER, Terrain.ABYSS:
			return Element.WATER
		Terrain.MAGMA_FISSURE:
			return Element.FIRE
	return Element.NONE
