extends Node

var exit_code: int = 0


func _ready() -> void:
	_test_map_generation()
	_test_save_round_trip()
	_test_battle_health_bridge()
	_test_adventure_instance_modifiers()
	print("ADVENTURE_DIAG: completed")
	get_tree().quit(exit_code)


func _test_map_generation() -> void:
	var generator := AdventureMapGenerator.new()
	var definition := AdventureDefinition.new()
	definition.floor_count = 2
	var minimum_rooms := 99
	var maximum_rooms := 0
	for seed_value in range(1, 251):
		for floor_index in range(2):
			var floor := generator.generate(seed_value * 7919, floor_index, definition)
			var errors := generator.validate(floor)
			if not errors.is_empty():
				_fail("ADVENTURE_DIAG: seed %d floor %d invalid: %s" % [seed_value, floor_index, ", ".join(errors)])
				return
			minimum_rooms = mini(minimum_rooms, floor.rooms.size())
			maximum_rooms = maxi(maximum_rooms, floor.rooms.size())
			if seed_value % 25 == 0:
				var duplicate := generator.generate(seed_value * 7919, floor_index, definition)
				if _floor_signature(floor) != _floor_signature(duplicate):
					_fail("ADVENTURE_DIAG: deterministic topology mismatch at seed %d floor %d" % [seed_value, floor_index])
					return
	print("ADVENTURE_DIAG: validated 500 floors, room span %d-%d" % [minimum_rooms, maximum_rooms])


func _test_save_round_trip() -> void:
	var heroes: Array[CharacterState] = []
	var paths := [
		"res://resources/characters/battle_warrior_state.tres",
		"res://resources/characters/battle_ranger_state.tres",
		"res://resources/characters/battle_druid_state.tres",
	]
	for index in range(paths.size()):
		var template := load(paths[index]) as CharacterState
		if template == null:
			_fail("ADVENTURE_DIAG: missing hero template %s" % paths[index])
			return
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = paths[index]
		hero.ensure_initialized()
		hero.current_health = maxi(1, hero.get_max_health() - index - 2)
		heroes.append(hero)
	var definition := AdventureDefinition.new()
	var run := PartyRunState.new()
	run.initialize_adventure(424242, heroes, definition)
	run.gold = 73
	run.provisions = 9
	run.camp_points = 5
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 0, definition)
	run.party[1].ranger_element_inventory = {0: 2, 2: 1}
	run.begin_transaction(AdventureEnums.TransactionType.MOVE, "diag_move", {"roll": 17})
	var store := AdventureSaveStore.new("adventure_diagnostic")
	store.delete_save()
	var save_error := store.save_run(run)
	if save_error != OK:
		_fail("ADVENTURE_DIAG: save failed: %s" % error_string(save_error))
		return
	var loaded := store.load_run()
	store.delete_save()
	if loaded == null:
		_fail("ADVENTURE_DIAG: save did not load")
		return
	if loaded.run_seed != run.run_seed or loaded.gold != 73 or loaded.provisions != 9 or loaded.camp_points != 5:
		_fail("ADVENTURE_DIAG: scalar run state changed during round trip")
	if loaded.party.size() != 3 or loaded.party[0].current_health != run.party[0].current_health:
		_fail("ADVENTURE_DIAG: party state changed during round trip")
	if int(loaded.party[1].ranger_element_inventory.get(0, 0)) != 2:
		_fail("ADVENTURE_DIAG: ranger inventory changed during round trip")
	if loaded.floor_state == null or _floor_signature(loaded.floor_state) != _floor_signature(run.floor_state):
		_fail("ADVENTURE_DIAG: floor state changed during round trip")
	if loaded.pending_transaction == null or loaded.pending_transaction.transaction_id != "diag_move":
		_fail("ADVENTURE_DIAG: pending transaction changed during round trip")
	print("ADVENTURE_DIAG: save round trip passed")


func _test_battle_health_bridge() -> void:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		_fail("ADVENTURE_DIAG: sample battle scenario missing")
		return
	var scenario := template.duplicate(true) as BattleScenario
	var source := scenario.get_player_states()[0]
	source.current_health = 7
	var controller := BattleController.new()
	controller.setup(scenario)
	if controller.player_units.is_empty() or controller.player_units[0].get_current_health() != 7:
		_fail("ADVENTURE_DIAG: battle setup still refills persistent health")
		return
	controller.player_units[0].set_current_health(3)
	controller._commit_battle_result(true)
	if source.current_health != 3:
		_fail("ADVENTURE_DIAG: battle result did not commit surviving health")
	print("ADVENTURE_DIAG: battle health bridge passed")


func _test_adventure_instance_modifiers() -> void:
	var template := load("res://resources/characters/battle_druid_state.tres") as CharacterState
	if template == null:
		_fail("ADVENTURE_DIAG: druid template missing")
		return
	var hero := template.duplicate(true) as CharacterState
	hero.ensure_initialized()
	hero.ensure_adventure_instance_ids(0)
	var weapon_id := hero.get_equipment_instance_id(hero.weapon_equipment)
	if weapon_id.is_empty():
		_fail("ADVENTURE_DIAG: weapon instance id missing")
		return
	var before_bonus := hero.get_damage_bonus({"equipment": hero.get_active_weapon_equipment()})
	hero.equipment_adventure_modifiers[weapon_id] = {"damage_bonus": 1}
	var after_bonus := hero.get_damage_bonus({"equipment": hero.get_active_weapon_equipment()})
	if after_bonus != before_bonus + 1:
		_fail("ADVENTURE_DIAG: sharpen modifier did not stay on its equipment instance")
		return
	if hero.deck.is_empty():
		_fail("ADVENTURE_DIAG: druid deck missing")
		return
	var stack := hero.deck[0]
	hero.card_adventure_modifiers[stack.stack_id] = {"element": BattleSurfaceState.Element.FIRE}
	var battle_template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var scenario := battle_template.duplicate(true) as BattleScenario
	scenario.players.clear()
	scenario.players.append(hero)
	var controller := BattleController.new()
	controller.setup(scenario)
	var unit := controller.player_units[0]
	unit.ensure_initialized(controller.config, controller.rng)
	var infused_card: CardData
	for card in unit.draw_pile + unit.hand:
		var state := unit.get_card_runtime_state(card, false)
		if str(state.get("adventure_stack_id", "")) == stack.stack_id:
			infused_card = card
			break
	if infused_card == null:
		_fail("ADVENTURE_DIAG: card instance origin was not propagated into battle")
		return
	var target_cell := controller.map_data.get_all_cells()[0]
	controller._apply_adventure_card_infusion(unit, infused_card, {"adventure_infusion_cell": target_cell})
	if controller.surface_state.get_element(target_cell) != BattleSurfaceState.Element.FIRE:
		_fail("ADVENTURE_DIAG: natural infusion did not apply its element")
		return
	controller._apply_adventure_card_infusion(unit, infused_card, {"adventure_infusion_cell": target_cell})
	if not bool(unit.get_card_runtime_state(infused_card, false).get("adventure_element_infusion_used", false)):
		_fail("ADVENTURE_DIAG: natural infusion did not consume its per-battle use")
	print("ADVENTURE_DIAG: instance modifiers passed")


func _floor_signature(floor: AdventureFloorState) -> String:
	var entries := PackedStringArray()
	for room in floor.rooms:
		var neighbors := Array(room.neighbor_ids)
		neighbors.sort()
		entries.append("%s@%d,%d#%d>%s" % [room.room_id, room.cell.x, room.cell.y, room.room_type, ",".join(neighbors)])
	entries.sort()
	return "|".join(entries)


func _fail(message: String) -> void:
	exit_code = 1
	push_error(message)
	print("ERROR: " + message)
