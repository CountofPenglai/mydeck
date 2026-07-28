extends Node

const ARCHETYPES := [
	&"gray_shield_guard",
	&"holy_spearman",
	&"fortress_crossbow",
	&"field_priest",
	&"punishment_knight",
	&"standard_bearer",
	&"holy_bastion_commander",
	&"creation_shard",
	&"blood_construct",
	&"corrupt_heart_veil",
	&"gray_bastion_paladin",
	&"triumph_statue",
]

const EXPECTED_HEALTH := {
	&"gray_shield_guard": 26,
	&"holy_spearman": 22,
	&"fortress_crossbow": 18,
	&"field_priest": 20,
	&"punishment_knight": 28,
	&"standard_bearer": 23,
	&"holy_bastion_commander": 40,
	&"creation_shard": 20,
	&"blood_construct": 20,
	&"corrupt_heart_veil": 135,
	&"gray_bastion_paladin": 60,
	&"triumph_statue": 40,
}

var _exit_code := 0


func _ready() -> void:
	_test_catalog()
	_test_encounters()
	_test_chapter_router()
	_test_formation_and_distortion()
	_test_watchful_stance_zone_move()
	_test_tactical_turn()
	_test_construct_shared_deck()
	_test_paladin_merge()
	_test_veil_gospel()
	_test_gospel_reward_and_load()
	print("CHAPTER_TWO_ENEMY_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_catalog() -> void:
	for index in range(ARCHETYPES.size()):
		var state := ChapterTwoEnemyCatalog.create_enemy(ARCHETYPES[index], 22000 + index)
		if state == null or state.enemy_data == null:
			_fail("failed to create %s" % ARCHETYPES[index])
			continue
		if state.enemy_data.chapter != 2:
			_fail("%s is not marked as chapter two" % ARCHETYPES[index])
		if state.enemy_data.weapon_equipment == null:
			_fail("%s has no real weapon" % ARCHETYPES[index])
		if state.get_max_health() != int(EXPECTED_HEALTH[ARCHETYPES[index]]):
			_fail("%s health mismatch: %d" % [ARCHETYPES[index], state.get_max_health()])
		if ARCHETYPES[index] != &"triumph_statue" and state.deck.is_empty():
			_fail("%s generated an empty deck" % ARCHETYPES[index])
		var expected_deck_size: int = int({
			&"creation_shard": 8,
			&"blood_construct": 8,
			&"corrupt_heart_veil": 12,
		}.get(ARCHETYPES[index], -1))
		if expected_deck_size >= 0 and state.deck.size() != expected_deck_size:
			_fail("%s deck size mismatch: %d" % [ARCHETYPES[index], state.deck.size()])
		for stack in state.deck:
			if stack != null and stack.card_data != null and stack.card_data.reward_eligible:
				_fail("%s has a reward-eligible enemy card" % ARCHETYPES[index])


func _test_encounters() -> void:
	for tier in [
		AdventureEnums.EncounterTier.WEAK,
		AdventureEnums.EncounterTier.MIXED,
		AdventureEnums.EncounterTier.STRONG,
		AdventureEnums.EncounterTier.AMBUSH,
		AdventureEnums.EncounterTier.ELITE,
		AdventureEnums.EncounterTier.BOSS,
	]:
		var encounter := ChapterTwoEnemyCatalog.pick_encounter(tier, 8100 + tier)
		if str(encounter.get("id", "")).is_empty() or (encounter.get("enemies", []) as Array).is_empty():
			_fail("tier %d produced an empty encounter" % tier)
	for tier_and_count in [
		[AdventureEnums.EncounterTier.WEAK, 4],
		[AdventureEnums.EncounterTier.MIXED, 4],
		[AdventureEnums.EncounterTier.STRONG, 5],
	]:
		var tier := int(tier_and_count[0])
		var expected := int(tier_and_count[1])
		var remaining: Array = []
		var last_id := ""
		var seen := {}
		for index in range(expected):
			var draw := ChapterTwoEnemyCatalog.draw_encounter(tier, 9100 + index, remaining, last_id)
			var encounter := draw.get("encounter", {}) as Dictionary
			last_id = str(encounter.get("id", ""))
			seen[last_id] = true
			remaining = draw.get("remaining_ids", []) as Array
		if seen.size() != expected:
			_fail("tier %d repeated before bag exhaustion" % tier)


func _test_chapter_router() -> void:
	if EnemyCatalogRouter.chapter_for_floor(0) != 1 or EnemyCatalogRouter.chapter_for_floor(1) != 2:
		_fail("floor-to-chapter route is incorrect")
	var first := EnemyCatalogRouter.pick_encounter(1, AdventureEnums.EncounterTier.WEAK, 12)
	var second := EnemyCatalogRouter.pick_encounter(2, AdventureEnums.EncounterTier.WEAK, 12)
	if (first.get("enemies", []) as Array).has(&"gray_shield_guard"):
		_fail("chapter one route returned chapter two enemies")
	if not (second.get("enemies", []) as Array).has(&"gray_shield_guard"):
		_fail("chapter two route did not return chapter two enemies")
	var hero := (load("res://resources/characters/battle_warrior_state.tres") as CharacterState).duplicate(true) as CharacterState
	hero.ensure_initialized()
	var run := PartyRunState.new()
	run.run_seed = 7712
	run.floor_index = 1
	run.party = [hero]
	var session := AdventureSessionService.new()
	session.current_run = run
	var scenario := session._build_battle_scenario({
		"enemy_chapter": 2,
		"encounter_tier": AdventureEnums.EncounterTier.WEAK,
		"battle_seed": 7712,
	})
	if scenario == null or scenario.enemies.is_empty() \
			or scenario.enemies[0].enemy_data.chapter != 2:
		_fail("adventure scenario builder did not create chapter two enemies on floor two")
	var legacy := session._build_battle_scenario({
		"enemy_archetypes": [&"hungry_fish"],
		"encounter_tier": AdventureEnums.EncounterTier.WEAK,
		"battle_seed": 7713,
	})
	if legacy == null or legacy.enemies.is_empty() \
			or legacy.enemies[0].enemy_data.chapter != 1:
		_fail("legacy pending encounter did not default to chapter one")


func _test_formation_and_distortion() -> void:
	var controller := _make_controller([&"gray_shield_guard", &"holy_spearman"])
	if controller == null:
		return
	var shield: BattleUnitState = controller.enemy_units[0]
	var spear: BattleUnitState = controller.enemy_units[1]
	_place_adjacent(controller, shield, spear)
	if not ChapterTwoEnemyRules.is_in_formation(controller, shield):
		_fail("adjacent military units did not form formation")
	if not shield.distortion_state.has_field("rock_scale") or not spear.distortion_state.has_field("lashing"):
		_fail("permanent military distortion fields were not injected")
	var before := shield.get_armor_stacks()
	ChapterTwoEnemyRules.on_turn_started(controller, shield)
	if shield.get_armor_stacks() - before != 4:
		_fail("shield formation did not grant 4 armor")


func _test_watchful_stance_zone_move() -> void:
	var controller := _make_controller([&"gray_shield_guard"])
	if controller == null:
		return
	var unit: BattleUnitState = controller.enemy_units[0]
	var watchful: CardData
	for card in ChapterTwoEnemyCatalog._military_cards():
		if card != null and card.card_name == "公开戒备":
			watchful = card
			break
	if watchful == null:
		_fail("watchful stance card is missing")
		return
	unit.hand.append(watchful)
	watchful.play({"controller": controller, "user": unit, "card": watchful}, [])
	if unit.hand.has(watchful) or not unit.enchant_zone.has(watchful) or unit.discard_pile.has(watchful):
		_fail("watchful stance did not move exclusively into the enchant zone")


func _test_tactical_turn() -> void:
	var controller := _make_controller([&"gray_shield_guard", &"holy_spearman"])
	if controller == null:
		return
	var player: BattleUnitState = controller.player_units[0]
	var deploy_cell := BattleHexGrid.INVALID_CELL
	for cell in controller.map_data.get_all_cells():
		if controller.map_data.is_player_deployment_cell(cell):
			deploy_cell = cell
			break
	if deploy_cell == BattleHexGrid.INVALID_CELL or not controller.deploy_player_unit_at_cell(player, deploy_cell):
		_fail("could not deploy player for chapter two tactical turn")
		return
	if not controller.start_battle():
		_fail("could not start chapter two tactical battle")
		return
	for enemy in controller.enemy_units:
		if enemy.enemy_state.intent_plan == null:
			_fail("%s has no locked public intent" % enemy.get_display_name())
	if controller.current_unit == player:
		controller.end_current_turn()
	if controller.phase == BattleController.Phase.BATTLE and controller.current_unit != player:
		_fail("chapter two tactical turn did not return control to the player")


func _test_construct_shared_deck() -> void:
	var controller := _make_controller([&"blood_construct"])
	if controller == null:
		return
	var owner: BattleUnitState = controller.enemy_units[0]
	owner.ensure_initialized(controller.config, controller.rng)
	var spawn_cell := BattleHexGrid.INVALID_CELL
	for cell in controller.map_data.get_cells_in_range(owner.cell, 1):
		if cell != owner.cell and controller.targeting.is_unit_cell_clear(null, cell, false):
			spawn_cell = cell
			break
	if spawn_cell == BattleHexGrid.INVALID_CELL:
		_fail("no spawn cell for flesh shared-deck test")
		return
	var spawn_state := ChapterTwoEnemyCatalog.create_enemy(&"flesh_spawn", 4433)
	if spawn_state == null or spawn_state.get_max_health() != 1:
		_fail("flesh spawn does not have fixed one health")
		return
	var spawn := controller.spawn_enemy_unit(spawn_state, spawn_cell, 0, owner)
	if spawn == null:
		_fail("failed to spawn flesh unit")
		return
	var marker := ChapterTwoEnemyCatalog.create_variant_card("monster", 1)
	owner.draw_pile.append(marker)
	if not spawn.draw_pile.has(marker):
		_fail("flesh spawn does not share the owner's draw pile")
	owner.discard_pile.append(marker)
	if not spawn.discard_pile.has(marker):
		_fail("flesh spawn does not share the owner's discard pile")


func _test_paladin_merge() -> void:
	var controller := _make_controller([&"gray_bastion_paladin", &"triumph_statue"])
	if controller == null:
		return
	ChapterTwoEnemyRules.on_battle_started(controller)
	var paladin: BattleUnitState = controller.enemy_units[0]
	var statue: BattleUnitState = controller.enemy_units[1]
	controller.apply_damage(null, statue, 10, "diagnostic", {"fixed_damage": true})
	var badges: PackedStringArray = paladin.enemy_state.runtime_state.get("badges", PackedStringArray())
	if badges.has("cup"):
		_fail("statue threshold did not extinguish cup badge")
	ChapterTwoEnemyRules.resolve_paladin_merge(controller, paladin)
	if paladin.enemy_state.enemy_data.archetype_id != &"military_god_remains":
		_fail("paladin did not become military god remains")
	if controller.enemy_units.has(statue):
		_fail("statue remained after merge")
	if paladin.get_max_health() != 90:
		_fail("merge health did not include remaining statue health")


func _test_veil_gospel() -> void:
	var controller := _make_controller([&"corrupt_heart_veil"])
	if controller == null:
		return
	var veil: BattleUnitState = controller.enemy_units[0]
	ChapterTwoEnemyRules.on_battle_started(controller)
	ChapterTwoEnemyRules.resolve_gospel(controller, veil, ChapterTwoEnemyCatalog.create_gospel_card())
	if int(veil.enemy_state.runtime_state.get("phase", 0)) != 2:
		_fail("gospel did not transition veil to phase two")
	if veil.get_strength() != 6 or veil.get_agility() != 3 or veil.get_intelligence() != 1:
		_fail("veil phase two attributes were not applied")
	if veil.get_max_health() != 135:
		_fail("veil phase two maximum health is not fixed at 135")


func _test_gospel_reward_and_load() -> void:
	var gospel := load("res://resources/curses/gospel.tres") as CurseDefinition
	if gospel == null or not gospel.is_valid_definition() or not gospel.is_boss_curse:
		_fail("gospel curse resource is invalid")
		return
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("chapter_two_enemy_diag")
	session.start_new_demo(20260726)
	var hero := session.current_run.party[0]
	var base_limit := hero.get_curse_load_limit()
	session.current_run.adventure_flags["pending_reward"] = {
		"gospel_offer": true,
		"gospel_receiver": "",
		"gospel_declined": false,
		"settled": false,
	}
	if not session.claim_gospel_reward(hero.adventure_character_id):
		_fail("gospel reward could not be claimed")
	else:
		var restored := session.save_store.load_run()
		if restored == null or restored.party.is_empty() or restored.party[0].get_curse("gospel") == null:
			_fail("gospel reward did not survive save round trip")
		var instance := hero.get_curse("gospel")
		if instance == null or instance.depth != 1 or instance.state != CurseInstance.State.INDUSTRY:
			_fail("gospel reward did not create depth-one industry")
		else:
			instance.state = CurseInstance.State.REPORT
			if hero.get_curse_load_limit() != base_limit + 1:
				_fail("gospel report did not increase curse load limit")
			instance.state = CurseInstance.State.FRUIT
			if hero.get_curse_load_limit() != base_limit + 2:
				_fail("gospel fruit did not increase curse load limit")
	var controller := _make_controller([&"gray_shield_guard"])
	if controller != null:
		var owner: BattleUnitState = controller.player_units[0]
		owner.ensure_initialized(controller.config, controller.rng)
		var battle_curse := CurseInstance.new()
		battle_curse.definition = gospel
		battle_curse.state = CurseInstance.State.REPORT
		battle_curse.depth = 1
		owner.curse_zone.append(battle_curse)
		gospel.effect.on_action_phase_started(owner, battle_curse, {"controller": controller})
		if owner.curse_wave != 1:
			_fail("gospel report did not generate action-phase curse wave")
		owner.gain_curse_wave(2, {"controller": controller})
		var hand_before := owner.hand.size()
		owner.consume_curse_wave(3, {"controller": controller})
		if owner.hand.size() != hand_before + 1:
			_fail("gospel report spending threshold did not draw")
		owner.gain_curse_wave(5, {"controller": controller})
		var health_before := owner.get_current_health()
		gospel.effect.on_turn_end(owner, battle_curse, {"controller": controller})
		if owner.get_current_health() != health_before - 1:
			_fail("gospel report turn-end penalty is incorrect")
	session.save_store.delete_save()


func _make_controller(archetypes: Array) -> BattleController:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		_fail("missing sample battle scenario")
		return null
	var scenario := template.duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	scenario.players.append(load("res://resources/characters/battle_warrior_state.tres") as CharacterState)
	scenario.enemies.clear()
	for index in range(archetypes.size()):
		scenario.enemies.append(ChapterTwoEnemyCatalog.create_enemy(StringName(archetypes[index]), 30000 + index))
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _place_adjacent(controller: BattleController, first: BattleUnitState, second: BattleUnitState) -> void:
	for cell in controller.map_data.get_all_cells():
		for neighbor in controller.map_data.get_cells_in_range(cell, 1):
			if neighbor != cell and controller.map_data.is_valid_cell(neighbor):
				first.set_hex_cell(cell, controller.map_data)
				second.set_hex_cell(neighbor, controller.map_data)
				return


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("CHAPTER_TWO_ENEMY_DIAG: " + message)
