extends RefCounted
class_name BattlefieldFeatureGenerator

const CHAPTER_ONE := 1
const CHAPTER_TWO := 2


static func generate(
	map_data: BattleMapData,
	surface_state: BattleSurfaceState,
	chapter: int,
	encounter_tier: int,
	seed: int,
	force_abyss: bool = false,
	start_object_id: int = 0,
	existing_objects: Array[BattleObjectState] = []
) -> Array[BattleObjectState]:
	var objects: Array[BattleObjectState] = []
	if map_data == null or surface_state == null:
		return objects
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var candidates := _get_feature_candidates(map_data)
	if candidates.is_empty():
		return objects
	_shuffle_cells(candidates, rng)

	var target_budget := rng.randi_range(8, 12)
	var terrain_count := mini(rng.randi_range(5, 8), target_budget - 3)
	var object_count := mini(rng.randi_range(3, 5), target_budget - terrain_count)
	var occupied: Dictionary = {}
	for existing in existing_objects:
		if existing != null and existing.is_active():
			occupied[existing.cell] = true

	if chapter == CHAPTER_ONE:
		var abyss_count := 0
		if force_abyss:
			abyss_count = rng.randi_range(2, 5)
		var placed_abyss := _place_terrain_cluster(
			map_data,
			surface_state,
			candidates,
			occupied,
			BattleSurfaceState.Terrain.ABYSS,
			abyss_count,
			rng
		)
		if force_abyss and placed_abyss <= 0:
			for fallback_cell in candidates:
				if occupied.has(fallback_cell):
					continue
				surface_state.set_terrain(fallback_cell, BattleSurfaceState.Terrain.ABYSS)
				occupied[fallback_cell] = true
				placed_abyss = 1
				break
		_place_terrain_cluster(
			map_data,
			surface_state,
			candidates,
			occupied,
			BattleSurfaceState.Terrain.SHALLOW_WATER,
			maxi(0, terrain_count - placed_abyss),
			rng
		)
	else:
		_place_terrain_cluster(
			map_data,
			surface_state,
			candidates,
			occupied,
			BattleSurfaceState.Terrain.MAGMA_FISSURE,
			terrain_count,
			rng
		)

	var object_cells := candidates.duplicate()
	_shuffle_cells(object_cells, rng)
	for cell in object_cells:
		if objects.size() >= object_count:
			break
		var all_objects: Array[BattleObjectState] = existing_objects.duplicate()
		all_objects.append_array(objects)
		if occupied.has(cell) or not _is_object_placement_safe(map_data, cell, all_objects):
			continue
		var kind := _pick_object_kind(chapter, rng)
		var direction := _pick_fall_direction(map_data, cell, rng) \
			if kind == BattleObjectDefinition.Kind.UNSTABLE_PILLAR else Vector2i.ZERO
		var object := BattleObjectState.create(start_object_id + objects.size(), kind, cell, direction)
		objects.append(object)
		occupied[cell] = true
		if object.definition.persistent_element != BattleSurfaceState.Element.NONE:
			surface_state.add_persistent_source(
				cell,
				object.definition.persistent_element,
				"object:%d" % object.object_id,
				"battle_object"
			)
	return objects


static func _get_feature_candidates(map_data: BattleMapData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in map_data.get_all_cells():
		if map_data.is_player_deployment_cell(cell) or map_data.is_enemy_spawn_cell(cell):
			continue
		result.append(cell)
	return result


static func _place_terrain_cluster(
	map_data: BattleMapData,
	surface_state: BattleSurfaceState,
	candidates: Array[Vector2i],
	occupied: Dictionary,
	terrain: int,
	count: int,
	rng: RandomNumberGenerator
) -> int:
	if count <= 0 or candidates.is_empty():
		return 0
	var pending: Array[Vector2i] = []
	var seeds_wanted := mini(rng.randi_range(2, 3), count)
	for _index in range(seeds_wanted):
		var seed_cell := candidates[rng.randi_range(0, candidates.size() - 1)]
		if not pending.has(seed_cell):
			pending.append(seed_cell)
	var placed := 0
	var guard := 0
	while placed < count and guard < candidates.size() * 8:
		guard += 1
		if pending.is_empty():
			pending.append(candidates[rng.randi_range(0, candidates.size() - 1)])
		var cell: Vector2i = pending.pop_front()
		if occupied.has(cell) or map_data.is_player_deployment_cell(cell) \
				or map_data.is_enemy_spawn_cell(cell):
			continue
		surface_state.set_terrain(cell, terrain)
		occupied[cell] = true
		placed += 1
		var neighbors := BattleHexGrid.neighbors(cell)
		_shuffle_cells(neighbors, rng)
		for neighbor in neighbors:
			if map_data.is_valid_cell(neighbor) and not pending.has(neighbor):
				pending.append(neighbor)
	return placed


static func _pick_object_kind(chapter: int, rng: RandomNumberGenerator) -> int:
	var roll := rng.randi_range(0, 99)
	if chapter == CHAPTER_ONE:
		return BattleObjectDefinition.Kind.WATER_CISTERN \
			if roll < 62 else BattleObjectDefinition.Kind.WIND_TOTEM
	if roll < 45:
		return BattleObjectDefinition.Kind.EXPLOSIVE_BARREL
	if roll < 76:
		return BattleObjectDefinition.Kind.UNSTABLE_PILLAR
	return BattleObjectDefinition.Kind.RUBBLE


static func _is_object_placement_safe(
	map_data: BattleMapData,
	cell: Vector2i,
	objects: Array[BattleObjectState]
) -> bool:
	var adjacent_blockers := 0
	var open_neighbors := 0
	for neighbor in BattleHexGrid.neighbors(cell):
		if not map_data.is_valid_cell(neighbor):
			continue
		var blocked := false
		for object in objects:
			if object != null and object.cell == neighbor and object.blocks_movement():
				blocked = true
				break
		if blocked:
			adjacent_blockers += 1
		else:
			open_neighbors += 1
	return adjacent_blockers < 2 and open_neighbors >= 2


static func _pick_fall_direction(
	map_data: BattleMapData,
	cell: Vector2i,
	rng: RandomNumberGenerator
) -> Vector2i:
	var directions: Array[Vector2i] = BattleHexGrid.AXIAL_DIRECTIONS.duplicate()
	_shuffle_cells(directions, rng)
	for direction in directions:
		var fall_cell := BattleHexGrid.axial_to_offset(
			BattleHexGrid.offset_to_axial(cell) + direction
		)
		if map_data.is_valid_cell(fall_cell):
			return direction
	return BattleHexGrid.AXIAL_DIRECTIONS[0]


static func _shuffle_cells(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in range(cells.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := cells[index]
		cells[index] = cells[swap_index]
		cells[swap_index] = value
