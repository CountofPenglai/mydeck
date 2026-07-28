extends Node

const REMOVED_TEST_CARD_PATHS := [
	"res://resources/cards/battle_strike.tres",
	"res://resources/cards/piercing_shot.tres",
	"res://resources/cards/quick_flourish.tres",
	"res://resources/cards/heavy_cleave.tres",
	"res://resources/cards/battle_master.tres",
	"res://resources/cards/sample_card.tres",
	"res://resources/cards/cultist_arrow.tres",
	"res://resources/cards/marauder_rend.tres",
]

var exit_code: int = 0


func _ready() -> void:
	_test_starter_deck_configuration()
	_test_reward_card_filtering()
	_test_map_generation()
	_test_save_round_trip()
	_test_distortion_map_ui()
	_test_battle_health_bridge()
	_test_enemy_health_scaling()
	_test_battle_reward_selection()
	_test_adventure_instance_modifiers()
	_test_inventory_loadout_model()
	_test_ranger_dig_activity()
	_test_event_choices_and_feedback()
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
			var starter_card := load(card_path) as CardData
			if starter_card == null or starter_card.rarity != CardEnums.Rarity.BASIC:
				_fail("ADVENTURE_DIAG: starter card must use BASIC rarity: %s" % card_path)
	for removed_path in REMOVED_TEST_CARD_PATHS:
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


func _test_reward_card_filtering() -> void:
	var basic_paths := PackedStringArray([
		"res://resources/cards/battle_slam.tres",
		"res://resources/cards/battle_charge.tres",
		"res://resources/cards/defensive_stance.tres",
		"res://resources/cards/ranger_perilous_assault.tres",
		"res://resources/cards/ranger_shadow_passage.tres",
		"res://resources/cards/ranger_overdrawn_inspiration.tres",
		"res://resources/cards/druid_verdant_strike.tres",
		"res://resources/cards/druid_moonlit_mend.tres",
		"res://resources/cards/druid_rooted_insight.tres",
	])
	var service := AdventureRewardService.new()
	for card_path in basic_paths:
		var basic_card := load(card_path) as CardData
		if basic_card == null or basic_card.can_appear_in_rewards():
			_fail("ADVENTURE_DIAG: BASIC card is still reward eligible: %s" % card_path)
		elif service.create_card_stack(card_path, "diag_basic", basic_card.card_class) != null:
			_fail("ADVENTURE_DIAG: BASIC card passed reward claim validation: %s" % card_path)
	for file_name in DirAccess.get_files_at("res://resources/cards/monster_cards"):
		if not file_name.ends_with(".tres") or file_name.ends_with("_stack.tres"):
			continue
		var monster_card_path := "res://resources/cards/monster_cards/%s" % file_name
		var monster_card := load(monster_card_path) as CardData
		if monster_card != null and monster_card.can_appear_in_rewards():
			_fail("ADVENTURE_DIAG: monster card is still reward eligible: %s" % monster_card_path)

	var candidate_count := 0
	for card_class in [
		CardEnums.CardClass.WARRIOR,
		CardEnums.CardClass.RANGER,
		CardEnums.CardClass.DRUID,
	]:
		for rarity in [
			CardEnums.Rarity.COMMON,
			CardEnums.Rarity.RARE,
			CardEnums.Rarity.EPIC,
		]:
			var candidates := service.get_card_candidates(card_class, rarity, 246810, card_class * 10 + rarity, 999)
			for candidate in candidates:
				candidate_count += 1
				var card_path := str((candidate as Dictionary).get("path", ""))
				var card := load(card_path) as CardData
				if card == null:
					_fail("ADVENTURE_DIAG: reward candidate could not be loaded: %s" % card_path)
					continue
				if not card.can_appear_in_rewards():
					_fail("ADVENTURE_DIAG: ineligible card entered reward candidates: %s" % card_path)
				if REMOVED_TEST_CARD_PATHS.has(card_path):
					_fail("ADVENTURE_DIAG: test card entered reward candidates: %s" % card_path)
	if candidate_count <= 0:
		_fail("ADVENTURE_DIAG: reward filter test produced no candidates")
	print("ADVENTURE_DIAG: reward card filtering passed")


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
	run.party[0].distortion_progress = 5
	run.party[0].selected_distortion_fields = PackedStringArray([str(DistortionCatalog.LOW_FIELDS[0])])
	run.party[0].claimed_distortion_milestones = PackedInt32Array([0])
	run.party[0].distortion_grace_count = 1
	run.party[0].strength_bonus += 1
	run.party[0].agility_bonus += 1
	run.party[0].intelligence_bonus += 1
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
	if loaded.party[0].distortion_progress != 5 \
		or not loaded.party[0].selected_distortion_fields.has(str(DistortionCatalog.LOW_FIELDS[0])) \
		or not loaded.party[0].claimed_distortion_milestones.has(0) \
		or loaded.party[0].distortion_grace_count != 1:
		_fail("ADVENTURE_DIAG: distortion state changed during round trip")
	if loaded.floor_state == null or _floor_signature(loaded.floor_state) != _floor_signature(run.floor_state):
		_fail("ADVENTURE_DIAG: floor state changed during round trip")
	if loaded.pending_transaction == null or loaded.pending_transaction.transaction_id != "diag_move":
		_fail("ADVENTURE_DIAG: pending transaction changed during round trip")
	var v3_payload := store._serialize_run(run)
	v3_payload["version"] = 3
	for hero_data_value in v3_payload.get("party", []):
		if hero_data_value is Dictionary:
			var hero_data := hero_data_value as Dictionary
			hero_data.erase("selected_distortion_fields")
			hero_data.erase("claimed_distortion_milestones")
			hero_data.erase("distortion_grace_count")
			hero_data.erase("strength_bonus")
			hero_data.erase("agility_bonus")
			hero_data.erase("intelligence_bonus")
	var migrated := store._deserialize_run(v3_payload)
	if migrated == null or migrated.save_version != PartyRunState.SAVE_VERSION:
		_fail("ADVENTURE_DIAG: v3 save migration failed")
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


func _test_distortion_map_ui() -> void:
	var template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	if template == null:
		_fail("ADVENTURE_DIAG: distortion UI hero missing")
		return
	var hero := template.duplicate(true) as CharacterState
	hero.adventure_source_path = template.resource_path
	hero.ensure_initialized()
	hero.distortion_progress = 2
	hero.selected_distortion_fields.clear()
	hero.claimed_distortion_milestones.clear()
	var heroes: Array[CharacterState] = [hero]
	var run := PartyRunState.new()
	run.initialize_adventure(858585, heroes, AdventureDefinition.new())
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 0, AdventureDefinition.new())
	run.adventure_flags["pending_reward"] = {"settled": false, "cards": [], "max_cards": 0}
	var service := AdventureSessionService.new()
	service.current_run = run
	service.save_store = AdventureSaveStore.new("distortion_ui_diagnostic")
	service.save_store.delete_save()
	var first_options := service.get_distortion_reward_options(hero.adventure_character_id)
	var second_options := service.get_distortion_reward_options(hero.adventure_character_id)
	if first_options.size() != 3 or first_options != second_options:
		_fail("ADVENTURE_DIAG: distortion options are not deterministic three-choice rewards")
	var map_scene := AdventureMapScene.new()
	map_scene.session = service
	map_scene.run_state = run
	map_scene.selected_room_id = run.floor_state.current_room_id
	map_scene._build_ui()
	map_scene._refresh()
	var reward_button := _find_button_with_text(map_scene, "奖励待选")
	if reward_button == null:
		_fail("ADVENTURE_DIAG: map party bar did not highlight pending distortion reward")
	map_scene._show_curse_zone(hero.adventure_character_id)
	if not map_scene.modal_layer.visible or not map_scene.modal_title.text.contains("诅咒与畸变"):
		_fail("ADVENTURE_DIAG: curse and distortion modal did not open")
	if not first_options.is_empty():
		var reward_id := str(first_options[0].get("id", ""))
		if not service.choose_distortion_reward(hero.adventure_character_id, reward_id):
			_fail("ADVENTURE_DIAG: offered distortion reward could not be claimed")
		elif not hero.selected_distortion_fields.has(reward_id) or not service.has_pending_reward():
			_fail("ADVENTURE_DIAG: distortion claim replaced the existing card reward flow")
	map_scene.free()
	service.save_store.delete_save()
	print("ADVENTURE_DIAG: distortion map UI passed")


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
	var equipment_reward := service.current_run.adventure_flags["pending_reward"] as Dictionary
	equipment_reward["equipment"] = [{
		"id": "equipment_receiver_diag",
		"path": "res://resources/items/lion_greatsword.tres",
		"name": "怒狮大剑",
		"rarity": CardEnums.Rarity.RARE,
	}]
	equipment_reward["max_equipment"] = 1
	var equipment_receiver: CharacterState = run.party[1]
	var first_inventory_before := run.party[0].get_inventory_item_count()
	var receiver_inventory_before := equipment_receiver.get_inventory_item_count()
	if service.claim_reward_candidate("equipment_receiver_diag") \
			or not service.claim_reward_candidate(
				"equipment_receiver_diag",
				equipment_receiver.adventure_character_id
			):
		_fail("ADVENTURE_DIAG: equipment reward did not require an explicit receiver")
	if run.party[0].get_inventory_item_count() != first_inventory_before \
			or equipment_receiver.get_inventory_item_count() != receiver_inventory_before + 1:
		_fail("ADVENTURE_DIAG: equipment reward was assigned to the wrong hero")
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
	if not controller.surface_state.get_readable_elements(target_cell).has(BattleSurfaceState.Element.FIRE):
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
	var target_template := load("res://resources/characters/battle_ranger_state.tres") as CharacterState
	var target := target_template.duplicate(true) as CharacterState
	target.ensure_initialized()
	target.ensure_adventure_instance_ids(1)
	hero.equipment_adventure_modifiers[returned_incoming_stack.stack_id] = {"damage_bonus": 2}
	var transferred := CharacterEquipmentModel.transfer_inventory_stack(
		hero,
		target,
		returned_incoming_stack.stack_id
	)
	if not bool(transferred.get("success", false)) \
			or _find_inventory_stack(hero, incoming_weapon) != null \
			or _find_inventory_stack(target, incoming_weapon) == null \
			or int((target.equipment_adventure_modifiers.get(
				returned_incoming_stack.stack_id,
				{}
			) as Dictionary).get("damage_bonus", 0)) != 2:
		_fail("ADVENTURE_DIAG: equipment transfer lost ownership or instance modifiers")
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


func _test_ranger_dig_activity() -> void:
	var heroes: Array[CharacterState] = []
	for path in [
		"res://resources/characters/battle_warrior_state.tres",
		"res://resources/characters/battle_ranger_state.tres",
		"res://resources/characters/battle_druid_state.tres",
	]:
		var template := load(path) as CharacterState
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = path
		hero.ensure_initialized()
		heroes.append(hero)
	var definition := AdventureDefinition.new()
	var run := PartyRunState.new()
	run.initialize_adventure(24681357, heroes, definition)
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 0, definition)
	var shelter: AdventureRoomState
	for room in run.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.SHELTER:
			shelter = room
			break
	if shelter == null:
		_fail("ADVENTURE_DIAG: shelter missing for ranger dig test")
		return
	run.floor_state.current_room_id = shelter.room_id
	run.camp_points = 10
	var service := AdventureSessionService.new()
	service.current_run = run
	service.save_store = AdventureSaveStore.new("ranger_dig_diagnostic")
	service.save_store.delete_save()
	var ranger := heroes[1]
	if not service.use_camp_activity("ranger_dig", ranger.adventure_character_id) \
			or not service.use_camp_activity("ranger_dig", ranger.adventure_character_id):
		_fail("ADVENTURE_DIAG: first two ranger digs failed")
	for element in ranger.ranger_element_inventory:
		if not BattleSurfaceState.BASE_ELEMENTS.has(int(element)):
			_fail("ADVENTURE_DIAG: ranger dig granted NONE or an advanced element")
	if service._get_ranger_element_total(ranger) != 4:
		_fail("ADVENTURE_DIAG: first two ranger digs did not grant four elements")
	if not service.use_camp_activity("ranger_dig", ranger.adventure_character_id):
		_fail("ADVENTURE_DIAG: third ranger dig failed")
	var reward := service.get_pending_event_reward()
	if str(reward.get("kind", "")) != "equipment" \
			or (reward.get("equipment", []) as Array).size() != 3 \
			or int(run.adventure_flags.get(
				"ranger_dig_%s" % ranger.adventure_character_id,
				0
			)) != 3:
		_fail("ADVENTURE_DIAG: third ranger dig did not open an equipment choice")
	service.save_store.delete_save()
	print("ADVENTURE_DIAG: ranger dig activity passed")


func _test_event_choices_and_feedback() -> void:
	var event_ids := [
		"hermit_house", "fallen_altar", "adventurer_remains", "the_fall", "cursed_wanderer",
		"sealed_chapel", "wilderness_merchant", "creation_ascetic", "alchemy_lesson",
		"nature_blessing", "trapped_arcanist", "master_forging", "chaos_gate",
	]
	for event_id in event_ids:
		var event := AdventureContentCatalog.get_event_definition(event_id)
		if str(event.get("summary", "")).length() < 20 or str(event.get("rules", "")).length() < 20:
			_fail("ADVENTURE_DIAG: event %s lacks detailed narrative or rules" % event_id)
		for option in event.get("options", []):
			if not (option is Dictionary) or str(option.get("preview", "")).is_empty():
				_fail("ADVENTURE_DIAG: event %s has an option without effect preview" % event_id)

	var altar_service := _create_event_service("fallen_altar", "event_altar_diagnostic")
	var altar_run := altar_service.current_run
	for hero in altar_run.party:
		hero.current_health = maxi(1, hero.get_max_health() - 30)
	var altar_selection := altar_service.get_event_selection("altar_resolve")
	if str(altar_selection.get("kind", "")) != "altar" or (altar_selection.get("heroes", []) as Array).size() != altar_run.party.size():
		_fail("ADVENTURE_DIAG: fallen altar did not expose one numeric choice per hero")
	var counts := {
		altar_run.party[0].adventure_character_id: 1,
		altar_run.party[1].adventure_character_id: 0,
		altar_run.party[2].adventure_character_id: 2,
	}
	var curse_counts_before := [altar_run.party[0].curse_instances.size(), altar_run.party[1].curse_instances.size(), altar_run.party[2].curse_instances.size()]
	var altar_result := altar_service.resolve_current_event("altar_resolve", {"curse_counts": counts})
	if not bool(altar_result.get("ok", false)) or not str(altar_result.get("message", "")).contains(altar_run.party[0].get_character_name()) \
			or altar_run.party[0].curse_instances.size() != curse_counts_before[0] + 1 \
			or altar_run.party[1].curse_instances.size() != curse_counts_before[1] \
			or altar_run.party[2].curse_instances.size() != curse_counts_before[2] + 2:
		_fail("ADVENTURE_DIAG: fallen altar did not resolve explicit per-hero choices")
	altar_service.save_store.delete_save()

	var wanderer_service := _create_event_service("cursed_wanderer", "event_wanderer_diagnostic")
	wanderer_service.current_run.ritual_points = 0
	var aid_option: Dictionary
	for option in wanderer_service.get_current_event_options():
		if str(option.get("id", "")) == "aid":
			aid_option = option
			break
	if aid_option.is_empty() or bool(aid_option.get("available", true)) or not str(aid_option.get("reason", "")).contains("仪式点"):
		_fail("ADVENTURE_DIAG: unavailable event option did not expose its resource reason")
	var map_scene := AdventureMapScene.new()
	map_scene.session = wanderer_service
	map_scene.run_state = wanderer_service.current_run
	map_scene.selected_room_id = wanderer_service.current_run.floor_state.current_room_id
	map_scene._build_ui()
	map_scene._refresh()
	map_scene._begin_event_option("share")
	if not map_scene.modal_layer.visible or not map_scene.modal_title.text.contains("承担") or map_scene.modal_body.get_child_count() < wanderer_service.current_run.party.size() + 2:
		_fail("ADVENTURE_DIAG: event hero choice UI did not expose selectable party members")
	map_scene.free()
	wanderer_service.save_store.delete_save()

	var merchant_service := _create_event_service("wilderness_merchant", "event_merchant_diagnostic")
	var merchant_stock := merchant_service.get_shop_stock()
	var merchant_kinds := {}
	for stock_entry in merchant_stock:
		merchant_kinds[str(stock_entry.get("kind", ""))] = int(merchant_kinds.get(str(stock_entry.get("kind", "")), 0)) + 1
	if merchant_stock.size() != 6 or int(merchant_kinds.get("consumable", 0)) != 3 \
			or int(merchant_kinds.get("equipment", 0)) != 2 or int(merchant_kinds.get("camp_supply", 0)) != 1:
		_fail("ADVENTURE_DIAG: wilderness merchant stock does not match 3 consumables + 2 equipment + 1 camp supply")
	merchant_service.save_store.delete_save()

	var chapel_service := _create_event_service("sealed_chapel", "event_chapel_diagnostic")
	var chapel_room := chapel_service.current_run.floor_state.get_current_room()
	chapel_service._complete_event_battle("sealed_chapel", chapel_room)
	if not chapel_service.has_pending_event_reward() or chapel_room.completed:
		_fail("ADVENTURE_DIAG: sealed chapel did not wait for an explicit reward receiver")
	var chapel_receiver := chapel_service.current_run.party[1]
	var chapel_result := chapel_service.claim_pending_event_reward("sealed_reliquary", chapel_receiver.adventure_character_id)
	var has_reliquary := false
	for item_stack in chapel_receiver.inventory:
		if item_stack != null and item_stack.item_data != null and item_stack.item_data.resource_path == "res://resources/items/sealed_reliquary.tres":
			has_reliquary = true
			break
	if not bool(chapel_result.get("ok", false)) or not has_reliquary or chapel_service.has_pending_event_reward() or not chapel_room.completed:
		_fail("ADVENTURE_DIAG: sealed chapel reward receiver choice was not applied")
	chapel_service.save_store.delete_save()

	var arcanist_service := _create_event_service("trapped_arcanist", "event_arcanist_diagnostic")
	var arcanist_room := arcanist_service.current_run.floor_state.get_current_room()
	arcanist_service._complete_event_battle("trapped_arcanist", arcanist_room)
	var arcanist_receiver := arcanist_service.current_run.party[2]
	var previous_limit := arcanist_receiver.get_curse_load_limit()
	var arcanist_result := arcanist_service.claim_pending_event_reward("arcanist_load", arcanist_receiver.adventure_character_id)
	if not bool(arcanist_result.get("ok", false)) or arcanist_receiver.get_curse_load_limit() != previous_limit + 2:
		_fail("ADVENTURE_DIAG: arcanist reward did not apply to the selected hero")
	arcanist_service.save_store.delete_save()

	var card_choice_service := _create_event_service("alchemy_lesson", "event_card_choice_diagnostic")
	var card_choice_room := card_choice_service.current_run.floor_state.get_current_room()
	var card_choice_hero := card_choice_service.current_run.party[1]
	var deck_size_before := card_choice_hero.get_deck_card_count()
	card_choice_service._create_pending_card_event_reward(card_choice_room, card_choice_hero, CardEnums.Rarity.EPIC, "诊断选牌", "三选一", false)
	var pending_card_reward := card_choice_service.get_pending_event_reward()
	var card_candidates := pending_card_reward.get("cards", []) as Array
	if card_candidates.size() != 3:
		_fail("ADVENTURE_DIAG: event card reward did not expose three explicit candidates")
	elif not bool(card_choice_service.claim_pending_event_reward("card", card_choice_hero.adventure_character_id, str(card_candidates[0].get("id", ""))).get("ok", false)) \
			or not bool(card_choice_service.settle_pending_event_reward().get("ok", false)) \
			or card_choice_hero.get_deck_card_count() != deck_size_before + 1 or card_choice_room.completed:
		_fail("ADVENTURE_DIAG: repeatable event card choice did not add the chosen card without closing the room")
	card_choice_service.save_store.delete_save()

	var delivery_service := _create_event_service("adventurer_remains", "event_remains_delivery_diagnostic")
	var delivery_hero := delivery_service.current_run.party[0]
	var remains_stack := delivery_service.reward_service.create_item_stack("res://resources/items/adventurer_remains.tres", "diagnostic_remains")
	delivery_hero.inventory.append(remains_stack)
	delivery_service.current_run.adventure_flags["adventurer_remains"] = true
	var outpost: AdventureRoomState
	for room in delivery_service.current_run.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.SHELTER:
			outpost = room
			break
	if outpost != null:
		outpost.shelter_type = AdventureEnums.ShelterType.OUTPOST
		delivery_service.current_run.floor_state.current_room_id = outpost.room_id
	var delivery_result := delivery_service.begin_adventurer_remains_delivery()
	var delivery_reward := delivery_service.get_pending_event_reward()
	var delivery_candidates := delivery_reward.get("equipment", []) as Array
	if outpost == null or not bool(delivery_result.get("ok", false)) or delivery_candidates.size() != 3:
		_fail("ADVENTURE_DIAG: remains delivery did not expose a three-equipment choice at an outpost")
	else:
		var selected_equipment := delivery_candidates[0] as Dictionary
		delivery_service.claim_pending_event_reward("equipment", delivery_hero.adventure_character_id, str(selected_equipment.get("id", "")))
		delivery_service.settle_pending_event_reward()
		var still_has_remains := false
		for item_stack in delivery_hero.inventory:
			if item_stack != null and item_stack.item_data != null and item_stack.item_data.resource_path == "res://resources/items/adventurer_remains.tres":
				still_has_remains = true
		if still_has_remains or bool(delivery_service.current_run.adventure_flags.get("adventurer_remains", false)):
			_fail("ADVENTURE_DIAG: remains task item was not removed after claiming the outpost reward")
	delivery_service.save_store.delete_save()

	var chaos_service := _create_event_service("chaos_gate", "event_chaos_diagnostic")
	var chaos_result := chaos_service.resolve_current_event("event_battle", {})
	if not bool(chaos_result.get("pending_event_reward", false)) or chaos_service.has_pending_battle() \
			or not bool(chaos_service.get_pending_event_reward().get("starts_battle", false)):
		_fail("ADVENTURE_DIAG: chaos gate did not require reward choices before battle")
	chaos_service.save_store.delete_save()
	print("ADVENTURE_DIAG: event choices and feedback passed")


func _create_event_service(event_id: String, save_slot: String) -> AdventureSessionService:
	var heroes: Array[CharacterState] = []
	var hero_paths := [
		"res://resources/characters/battle_warrior_state.tres",
		"res://resources/characters/battle_ranger_state.tres",
		"res://resources/characters/battle_druid_state.tres",
	]
	for path in hero_paths:
		var template := load(path) as CharacterState
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = path
		hero.ensure_initialized()
		heroes.append(hero)
	var definition := AdventureDefinition.new()
	var run := PartyRunState.new()
	run.initialize_adventure(717171 + event_id.hash(), heroes, definition)
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 0, definition)
	var event_room: AdventureRoomState
	for room in run.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.EVENT:
			event_room = room
			break
	if event_room != null:
		event_room.content_id = event_id
		event_room.visited = true
		event_room.content_revealed = true
		run.floor_state.current_room_id = event_room.room_id
	var service := AdventureSessionService.new()
	service.current_run = run
	service.save_store = AdventureSaveStore.new(save_slot)
	service.save_store.delete_save()
	return service


func _find_inventory_stack(hero: CharacterState, item: ItemData) -> InventoryStack:
	for stack in hero.inventory:
		if stack != null and stack.item_data == item:
			return stack
	return null


func _find_button_with_text(root: Node, fragment: String) -> Button:
	if root is Button and (root as Button).text.contains(fragment):
		return root as Button
	for child in root.get_children():
		var found := _find_button_with_text(child, fragment)
		if found != null:
			return found
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
