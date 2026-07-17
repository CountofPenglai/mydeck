extends Node

var exit_code: int = 0


func _ready() -> void:
	_test_starter_deck_configuration()
	_test_map_generation()
	_test_save_round_trip()
	_test_battle_health_bridge()
	_test_enemy_health_scaling()
	_test_battle_reward_selection()
	_test_adventure_instance_modifiers()
	_test_inventory_loadout_model()
	print("ADVENTURE_DIAG: completed")
	get_tree().quit(exit_code)


func _test_starter_deck_configuration() -> void:
	var expected_by_character := {
		"res://resources/characters/battle_warrior_state.tres": {
			"res://resources/cards/battle_slam.tres": 5,
			"res://resources/cards/battle_charge.tres": 2,
			"res://resources/cards/defensive_stance.tres": 1,
		},
		"res://resources/characters/battle_ranger_state.tres": {
			"res://resources/cards/ranger_perilous_assault.tres": 5,
			"res://resources/cards/ranger_shadow_passage.tres": 2,
			"res://resources/cards/ranger_overdrawn_inspiration.tres": 1,
		},
		"res://resources/characters/battle_druid_state.tres": {
			"res://resources/cards/druid_verdant_strike.tres": 5,
			"res://resources/cards/druid_moonlit_mend.tres": 2,
			"res://resources/cards/druid_rooted_insight.tres": 1,
		},
	}
	for character_path in expected_by_character:
		var character := load(character_path) as CharacterState
		if character == null:
			_fail("ADVENTURE_DIAG: missing starter character %s" % character_path)
			continue
		var expected: Dictionary = expected_by_character[character_path]
		if character.deck.size() != expected.size() or character.get_deck_card_count() != 8:
			_fail("ADVENTURE_DIAG: %s starter deck must contain only three stacks and eight cards" % character_path)
		for card_path in expected:
			var actual_count := 0
			for stack in character.deck:
				if stack != null and stack.card_data != null and stack.card_data.resource_path == card_path:
					actual_count += stack.count
			if actual_count != int(expected[card_path]):
				_fail("ADVENTURE_DIAG: %s expected %s x%d, got %d" % [character_path, card_path, expected[card_path], actual_count])
	for removed_path in [
		"res://resources/cards/battle_strike.tres",
		"res://resources/cards/piercing_shot.tres",
	]:
		if ResourceLoader.exists(removed_path):
			_fail("ADVENTURE_DIAG: removed test card still exists: %s" % removed_path)
	var expected_weapons := {
		"res://resources/characters/battle_warrior_state.tres": "res://resources/items/mountain_cleaver.tres",
		"res://resources/characters/battle_ranger_state.tres": "res://resources/items/ranger_dagger_crossbow.tres",
	}
	for character_path in expected_weapons:
		var loadout_character := load(character_path) as CharacterState
		if loadout_character == null:
			continue
		if loadout_character.weapon_equipment == null \
				or loadout_character.weapon_equipment.resource_path != str(expected_weapons[character_path]):
			_fail("ADVENTURE_DIAG: %s does not have only its starter weapon equipped" % character_path)
		if not loadout_character.inventory.is_empty():
			_fail("ADVENTURE_DIAG: %s starter inventory still contains test weapons" % character_path)
	print("ADVENTURE_DIAG: starter deck configuration passed")


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
	run.enemy_health_percent = 175
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
	if loaded.run_seed != run.run_seed or loaded.gold != 73 or loaded.provisions != 9 or loaded.camp_points != 5 \
			or loaded.enemy_health_percent != 175:
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


func _test_enemy_health_scaling() -> void:
	if PartyRunState.new().enemy_health_percent != 100:
		_fail("ADVENTURE_DIAG: enemy health percent must default to 100")
		return
	var hero_template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	var baseline_enemy := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 42)
	if hero_template == null or baseline_enemy == null:
		_fail("ADVENTURE_DIAG: enemy health scaling resources missing")
		return
	var hero := hero_template.duplicate(true) as CharacterState
	hero.ensure_initialized()
	var heroes: Array[CharacterState] = [hero]
	var run := PartyRunState.new()
	run.initialize_adventure(4242, heroes, AdventureDefinition.new())
	run.enemy_health_percent = 175
	var service := AdventureSessionService.new()
	service.current_run = run
	var scenario := service._build_battle_scenario({
		"battle_seed": 99,
		"encounter_tier": AdventureEnums.EncounterTier.WEAK,
		"enemy_archetypes": [&"hungry_fish"],
		"enemy_health_percent": 175,
	})
	if scenario == null or scenario.get_enemy_states().size() != 1:
		_fail("ADVENTURE_DIAG: scaled battle scenario was not created")
		return
	var scaled_enemy := scenario.get_enemy_states()[0]
	var expected_health := ceili(float(baseline_enemy.get_max_health()) * 1.75)
	if scaled_enemy.max_health_percent != 175 or scaled_enemy.get_max_health() != expected_health \
			or scaled_enemy.current_health != expected_health:
		_fail("ADVENTURE_DIAG: adventure scenario did not apply enemy health percent")
		return
	scaled_enemy.runtime_state["max_health_override"] = 5
	if scaled_enemy.get_max_health() != 9:
		_fail("ADVENTURE_DIAG: transformed enemy health override ignored the test percent")
		return
	scaled_enemy.runtime_state.erase("max_health_override")
	var controller := BattleController.new()
	controller.setup(scenario)
	if controller.enemy_units.size() != 1 \
			or controller.enemy_units[0].get_max_health() != expected_health \
			or controller.enemy_units[0].get_current_health() != expected_health:
		_fail("ADVENTURE_DIAG: battle runtime did not preserve enemy health percent")
		return
	print("ADVENTURE_DIAG: enemy health scaling passed")


func _test_battle_reward_selection() -> void:
	var hero_paths := [
		"res://resources/characters/battle_warrior_state.tres",
		"res://resources/characters/battle_ranger_state.tres",
		"res://resources/characters/battle_druid_state.tres",
	]
	var heroes: Array[CharacterState] = []
	for index in range(hero_paths.size()):
		var template := load(hero_paths[index]) as CharacterState
		if template == null:
			_fail("ADVENTURE_DIAG: battle reward hero template missing")
			return
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = hero_paths[index]
		hero.ensure_initialized()
		heroes.append(hero)
	var definition := AdventureDefinition.new()
	var run := PartyRunState.new()
	run.initialize_adventure(919191, heroes, definition)
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 0, definition)
	var battle_room: AdventureRoomState
	for room in run.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
			battle_room = room
			break
	if battle_room == null:
		_fail("ADVENTURE_DIAG: normal battle room missing for reward test")
		return
	run.floor_state.current_room_id = battle_room.room_id
	run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "reward_diag_battle", {
		"room_id": battle_room.room_id,
		"ambush": false,
		"event_battle": false,
		"encounter_tier": AdventureEnums.EncounterTier.WEAK,
	})
	var service := AdventureSessionService.new()
	service.current_run = run
	service.save_store = AdventureSaveStore.new("battle_reward_diagnostic")
	service.save_store.delete_save()
	var result := BattleResult.new()
	result.victory = true
	if not service.resolve_pending_battle_result(result):
		service.save_store.delete_save()
		_fail("ADVENTURE_DIAG: victory did not resolve into a reward transaction")
		return
	var reward := service.get_pending_reward()
	var candidates := reward.get("cards", []) as Array
	if candidates.size() < heroes.size() + 2 or int(reward.get("max_cards", 0)) != 2:
		service.save_store.delete_save()
		_fail("ADVENTURE_DIAG: battle reward card candidates were not generated")
		return
	var first_candidate := candidates[0] as Dictionary
	var receiver_id := str(first_candidate.get("hero_id", ""))
	var receiver: CharacterState
	for hero in run.party:
		if hero != null and hero.adventure_character_id == receiver_id:
			receiver = hero
			break
	var before_count := receiver.get_deck_card_count() if receiver != null else -1
	if receiver == null or not service.claim_reward_candidate(str(first_candidate.get("id", ""))) \
			or receiver.get_deck_card_count() != before_count + 1:
		service.save_store.delete_save()
		_fail("ADVENTURE_DIAG: selecting a reward card did not add it to the target deck")
		return
	var map_scene := AdventureMapScene.new()
	map_scene.session = service
	map_scene.run_state = run
	map_scene._build_ui()
	map_scene._show_pending_state()
	if not map_scene.modal_layer.visible or map_scene.modal_title.text.find("选择卡牌奖励") < 0:
		service.save_store.delete_save()
		map_scene.free()
		_fail("ADVENTURE_DIAG: pending reward did not open the card selection UI")
		return
	map_scene.free()
	service.save_store.delete_save()
	print("ADVENTURE_DIAG: battle reward selection passed")


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


func _test_inventory_loadout_model() -> void:
	var template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	var incoming_weapon := load("res://resources/items/lion_greatsword.tres") as EquipmentData
	if template == null or incoming_weapon == null:
		_fail("ADVENTURE_DIAG: loadout test resources missing")
		return
	var hero := template.duplicate(true) as CharacterState
	hero.ensure_initialized()
	hero.ensure_adventure_instance_ids(0)
	var old_weapon := hero.weapon_equipment
	var old_weapon_id := str(hero.equipment_instance_ids.get(CharacterEquipmentModel.SLOT_WEAPON, ""))
	hero.equipment_adventure_modifiers[old_weapon_id] = {"damage_bonus": 3}
	hero.inventory.clear()
	var incoming_stack := InventoryStack.new()
	incoming_stack.item_data = incoming_weapon
	incoming_stack.stack_id = "diag_incoming_weapon"
	hero.inventory.append(incoming_stack)

	var switched := CharacterEquipmentModel.equip_inventory_stack_to_slot(
		hero, incoming_stack.stack_id, CharacterEquipmentModel.SLOT_WEAPON
	)
	if not bool(switched.get("success", false)) or hero.weapon_equipment != incoming_weapon:
		_fail("ADVENTURE_DIAG: explicit inventory weapon switch failed")
		return
	if str(hero.equipment_instance_ids.get(CharacterEquipmentModel.SLOT_WEAPON, "")) != "diag_incoming_weapon":
		_fail("ADVENTURE_DIAG: incoming equipment instance id did not move into the slot")
		return
	var returned_old_stack := _find_inventory_stack(hero, old_weapon)
	if returned_old_stack == null or returned_old_stack.stack_id != old_weapon_id:
		_fail("ADVENTURE_DIAG: replaced weapon did not keep its instance id in the inventory")
		return
	if int((hero.equipment_adventure_modifiers.get(old_weapon_id, {}) as Dictionary).get("damage_bonus", 0)) != 3:
		_fail("ADVENTURE_DIAG: equipment adventure modifier did not stay with the replaced weapon")
		return

	var unequipped := CharacterEquipmentModel.unequip_slot_to_inventory(hero, CharacterEquipmentModel.SLOT_WEAPON)
	if not bool(unequipped.get("success", false)) or hero.weapon_equipment != null:
		_fail("ADVENTURE_DIAG: unequip to inventory failed")
		return
	var returned_incoming_stack := _find_inventory_stack(hero, incoming_weapon)
	if returned_incoming_stack == null or returned_incoming_stack.stack_id != "diag_incoming_weapon":
		_fail("ADVENTURE_DIAG: unequipped weapon lost its instance id")
		return

	var accessory := EquipmentData.new()
	accessory.item_name = "诊断饰品"
	accessory.equip_slot = EquipmentData.EquipSlot.ACCESSORY
	var accessory_stack := InventoryStack.new()
	accessory_stack.item_data = accessory
	accessory_stack.stack_id = "diag_accessory"
	hero.inventory.append(accessory_stack)
	var accessory_result := CharacterEquipmentModel.equip_inventory_stack_to_slot(
		hero, accessory_stack.stack_id, CharacterEquipmentModel.SLOT_ACCESSORY_2
	)
	if not bool(accessory_result.get("success", false)) or hero.accessory_equipment_2 != accessory \
			or hero.accessory_equipment_1 != null:
		_fail("ADVENTURE_DIAG: explicit accessory slot selection failed")
		return

	var potion := load("res://resources/items/healing_potion.tres") as ItemData
	if potion != null:
		CharacterEquipmentModel.add_inventory_item(hero, potion)
		CharacterEquipmentModel.sort_inventory(hero)
		if hero.inventory.is_empty() or hero.inventory[0].item_data == potion:
			_fail("ADVENTURE_DIAG: inventory sorting did not place equipment before consumables")
			return
	print("ADVENTURE_DIAG: inventory loadout model passed")


func _find_inventory_stack(hero: CharacterState, item: ItemData) -> InventoryStack:
	for stack in hero.inventory:
		if stack != null and stack.item_data == item:
			return stack
	return null


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
