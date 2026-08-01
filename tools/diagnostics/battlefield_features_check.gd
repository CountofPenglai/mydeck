extends Node

var _exit_code := 0


func _ready() -> void:
	_test_layered_surface_state()
	_test_reactions_and_expiration()
	_test_collection_lifecycle()
	_test_deterministic_generation()
	_test_abyss_pity()
	_test_battle_objects()
	print("BATTLEFIELD_FEATURES_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_layered_surface_state() -> void:
	var map_data := BattleMapData.new()
	var surfaces := BattleSurfaceState.new()
	surfaces.setup(map_data)
	var cell := Vector2i(5, 4)
	surfaces.set_terrain(cell, BattleSurfaceState.Terrain.MAGMA_FISSURE)
	if not BattleSurfaceState.terrain_description(
		BattleSurfaceState.Terrain.MAGMA_FISSURE
	).contains("3 点环境伤害"):
		_fail("BATTLEFIELD_FEATURES_DIAG: terrain detail omitted its gameplay effect")
	surfaces.add_persistent_source(cell, BattleSurfaceState.Element.FIRE, "terrain:test", "terrain")
	if surfaces.get_damage_bonus(cell) != 0 or surfaces.get_damage_reduction(cell, false) != 0:
		_fail("BATTLEFIELD_FEATURES_DIAG: base elements still grant combat modifiers")
	surfaces.create_advanced_surface(cell, BattleSurfaceState.Element.ICE, 1)
	if surfaces.is_terrain_effective(cell) or surfaces.get_movement_cost(cell) != 1:
		_fail("BATTLEFIELD_FEATURES_DIAG: ground effect did not suppress terrain rules")
	if surfaces.get_terrain(cell) != BattleSurfaceState.Terrain.MAGMA_FISSURE:
		_fail("BATTLEFIELD_FEATURES_DIAG: overlay erased permanent terrain identity")


func _test_reactions_and_expiration() -> void:
	var map_data := BattleMapData.new()
	var surfaces := BattleSurfaceState.new()
	surfaces.setup(map_data)
	var cell := Vector2i(4, 4)
	surfaces.add_persistent_source(cell, BattleSurfaceState.Element.WATER, "water", "test")
	surfaces.add_persistent_source(cell, BattleSurfaceState.Element.EARTH, "earth", "test")
	surfaces.add_persistent_source(cell, BattleSurfaceState.Element.AIR, "air", "test")
	var result := surfaces.apply_base_element(cell, BattleSurfaceState.Element.FIRE, 1)
	var reactions: Array = result.get("reactions", []) as Array
	var expected := [
		BattleSurfaceState.Element.STEAM,
		BattleSurfaceState.Element.LAVA,
		BattleSurfaceState.Element.BLAZE,
	]
	if reactions != expected:
		_fail("BATTLEFIELD_FEATURES_DIAG: multi-reaction order mismatch: %s" % [reactions])
	if surfaces.get_ground_effect(cell) != BattleSurfaceState.Element.LAVA \
			or surfaces.get_air_effect(cell) != BattleSurfaceState.Element.BLAZE:
		_fail("BATTLEFIELD_FEATURES_DIAG: fixed channel overwrite order mismatch")
	surfaces.advance_round(3)
	if surfaces.get_ground_effect(cell) == BattleSurfaceState.Element.NONE:
		_fail("BATTLEFIELD_FEATURES_DIAG: advanced effect expired too early")
	surfaces.advance_round(4)
	if surfaces.get_ground_effect(cell) != BattleSurfaceState.Element.NONE \
			or surfaces.get_air_effect(cell) != BattleSurfaceState.Element.NONE:
		_fail("BATTLEFIELD_FEATURES_DIAG: advanced effect did not expire on schedule")


func _test_collection_lifecycle() -> void:
	var map_data := BattleMapData.new()
	var surfaces := BattleSurfaceState.new()
	surfaces.setup(map_data)
	var cell := Vector2i(3, 3)
	surfaces.add_persistent_source(cell, BattleSurfaceState.Element.FIRE, "spring", "test")
	surfaces.add_residue(cell, BattleSurfaceState.Element.WATER, 1)
	var entries: Array[Dictionary] = surfaces.get_collectible_entries(cell, "hero")
	if entries.size() != 2:
		_fail("BATTLEFIELD_FEATURES_DIAG: collectible sources were not separated")
	surfaces.commit_collection(
		cell,
		"hero",
		entries,
		[BattleSurfaceState.Element.FIRE, BattleSurfaceState.Element.WATER]
	)
	if not surfaces.get_collectible_entries(cell, "hero").is_empty():
		_fail("BATTLEFIELD_FEATURES_DIAG: collection did not consume/record sources")
	if surfaces.get_collectible_entries(cell, "other").size() != 1:
		_fail("BATTLEFIELD_FEATURES_DIAG: permanent source was not collector-specific")


func _test_deterministic_generation() -> void:
	var map_data := BattleMapData.new()
	var first_surfaces := BattleSurfaceState.new()
	var second_surfaces := BattleSurfaceState.new()
	first_surfaces.setup(map_data)
	second_surfaces.setup(map_data)
	var first := BattlefieldFeatureGenerator.generate(
		map_data,
		first_surfaces,
		2,
		AdventureEnums.EncounterTier.STRONG,
		90210,
		false
	)
	var second := BattlefieldFeatureGenerator.generate(
		map_data,
		second_surfaces,
		2,
		AdventureEnums.EncounterTier.STRONG,
		90210,
		false
	)
	if _feature_signature(first_surfaces, first) != _feature_signature(second_surfaces, second):
		_fail("BATTLEFIELD_FEATURES_DIAG: feature generation is not deterministic")
	if first.size() < 3 or first.size() > 5:
		_fail("BATTLEFIELD_FEATURES_DIAG: object count is outside design bounds")
	for battle_object in first:
		if map_data.is_player_deployment_cell(battle_object.cell) \
				or map_data.is_enemy_spawn_cell(battle_object.cell):
			_fail("BATTLEFIELD_FEATURES_DIAG: object entered protected deployment cells")
	var forced_surfaces := BattleSurfaceState.new()
	forced_surfaces.setup(map_data)
	BattlefieldFeatureGenerator.generate(
		map_data,
		forced_surfaces,
		1,
		AdventureEnums.EncounterTier.STRONG,
		90211,
		true
	)
	var abyss_found := false
	for cell in forced_surfaces.get_all_active_cells():
		if forced_surfaces.get_terrain(cell) == BattleSurfaceState.Terrain.ABYSS:
			abyss_found = true
			break
	if not abyss_found:
		_fail("BATTLEFIELD_FEATURES_DIAG: forced abyss generation produced no abyss")


func _test_battle_objects() -> void:
	var source := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var scenario := source.duplicate(true) as BattleScenario
	scenario.generate_battlefield_features = false
	var controller := BattleController.new()
	controller.setup(scenario)
	var attacker := controller.player_units[0]
	var attack_card := load("res://resources/cards/battle_slam.tres") as CardData
	var cistern := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.WATER_CISTERN,
		Vector2i(4, 2)
	)
	if attacker == null or attack_card == null or cistern == null \
			or not attack_card.can_target_objects() \
			or not attack_card.is_object_target_allowed(
				{"controller": controller, "user": attacker, "card": attack_card},
				cistern
			):
		_fail("BATTLEFIELD_FEATURES_DIAG: strike attack card did not accept a destructible object")
	elif controller.get_cell_detail_text(cistern.cell).find("被摧毁时") < 0:
		_fail("BATTLEFIELD_FEATURES_DIAG: object detail omitted its destruction effect")
	else:
		var cistern_health := cistern.current_health
		attack_card.play(
			{"controller": controller, "user": attacker, "card": attack_card},
			[cistern]
		)
		if cistern.current_health >= cistern_health:
			_fail("BATTLEFIELD_FEATURES_DIAG: strike attack card did not damage an object")
	var first := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.EXPLOSIVE_BARREL,
		Vector2i(5, 4)
	)
	var second := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.EXPLOSIVE_BARREL,
		Vector2i(6, 4)
	)
	if first == null or second == null:
		_fail("BATTLEFIELD_FEATURES_DIAG: failed to spawn test objects")
		return
	if controller.targeting.is_unit_cell_clear(null, first.cell, false):
		_fail("BATTLEFIELD_FEATURES_DIAG: object did not block occupancy")
	controller.apply_object_damage(null, first, 4, "test", {"source_cell": Vector2i(4, 4)})
	if first.is_active() or second.is_active():
		_fail("BATTLEFIELD_FEATURES_DIAG: explosive chain did not resolve through queue")
	if not controller.surface_state.get_readable_elements(Vector2i(5, 4)).has(
		BattleSurfaceState.Element.FIRE
	):
		_fail("BATTLEFIELD_FEATURES_DIAG: explosion did not leave fire residue")
	var wall := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.UNSTABLE_PILLAR,
		Vector2i(5, 2),
		BattleHexGrid.AXIAL_DIRECTIONS[0]
	)
	if wall == null or controller.targeting.has_line_of_sight(Vector2i(4, 2), Vector2i(6, 2)):
		_fail("BATTLEFIELD_FEATURES_DIAG: line-of-sight blocker was ignored")
	var indestructible_cell := _find_empty_cell(controller)
	var indestructible := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.RUBBLE,
		indestructible_cell
	)
	if indestructible != null:
		indestructible.definition.destructible = false
		var health_before := indestructible.current_health
		controller.apply_object_damage(null, indestructible, 99, "test")
		if indestructible.current_health != health_before:
			_fail("BATTLEFIELD_FEATURES_DIAG: indestructible object took damage")
	var totem_cell := _find_empty_cell(controller)
	var totem := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.WIND_TOTEM,
		totem_cell
	)
	if totem != null:
		controller.resolution_runner.effect_limit_reached = true
		controller.apply_object_damage(null, totem, totem.current_health, "queue limit test")
		controller.resolution_runner.effect_limit_reached = false
		if not totem.destroyed or _cell_has_source(
			controller.surface_state,
			totem_cell,
			"object:%d" % totem.object_id
		):
			_fail("BATTLEFIELD_FEATURES_DIAG: critical destruction state depended on effect queue")


func _test_abyss_pity() -> void:
	var service := AdventureSessionService.new()
	service.current_run = PartyRunState.new()
	service.current_run.adventure_flags["chapter_1_battlefield_abyss_misses"] = 2
	if not service._roll_chapter_one_abyss(
		1,
		AdventureEnums.EncounterTier.STRONG,
		12345
	):
		_fail("BATTLEFIELD_FEATURES_DIAG: abyss pity did not force the third eligible battle")
	if int(service.current_run.adventure_flags.get(
		"chapter_1_battlefield_abyss_misses",
		-1
	)) != 0:
		_fail("BATTLEFIELD_FEATURES_DIAG: abyss pity did not reset after success")
	service.current_run.adventure_flags["chapter_1_battlefield_abyss_misses"] = 1
	if service._roll_chapter_one_abyss(
		2,
		AdventureEnums.EncounterTier.STRONG,
		12345
	):
		_fail("BATTLEFIELD_FEATURES_DIAG: chapter two incorrectly generated chapter one abyss")
	if int(service.current_run.adventure_flags.get(
		"chapter_1_battlefield_abyss_misses",
		-1
	)) != 1:
		_fail("BATTLEFIELD_FEATURES_DIAG: ineligible battle changed abyss pity state")


func _feature_signature(
	surfaces: BattleSurfaceState,
	objects: Array[BattleObjectState]
) -> String:
	var parts: Array[String] = []
	for cell in surfaces.get_all_active_cells():
		var snapshot := surfaces.get_cell_snapshot(cell)
		parts.append("%d,%d:%d:%s" % [
			cell.x,
			cell.y,
			int(snapshot.get("terrain", 0)),
			snapshot.get("readable_elements", []),
		])
	for battle_object in objects:
		parts.append("o:%d:%d:%d" % [
			battle_object.definition.kind,
			battle_object.cell.x,
			battle_object.cell.y,
		])
	return "|".join(parts)


func _find_empty_cell(controller: BattleController) -> Vector2i:
	for cell in controller.map_data.get_all_cells():
		if controller.get_unit_at_cell(cell) == null \
				and controller.get_battle_object_at_cell(cell) == null:
			return cell
	return BattleHexGrid.INVALID_CELL


func _cell_has_source(
	surfaces: BattleSurfaceState,
	cell: Vector2i,
	source_id: String
) -> bool:
	var snapshot := surfaces.get_cell_snapshot(cell)
	for source_value in snapshot.get("persistent_sources", []) as Array:
		if str((source_value as Dictionary).get("id", "")) == source_id:
			return true
	return false


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
