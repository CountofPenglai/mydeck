extends Node

const ARCHETYPES := [
	&"hungry_fish", &"harpoon_fish", &"bandit_blade", &"bandit_bow", &"fish_priest",
	&"unclean_one", &"fish_champion", &"kraken", &"high_priest", &"abyss_scale",
]

var _exit_code := 0


func _ready() -> void:
	_test_global_balance_adjustments()
	_test_card_catalog()
	_test_enemy_catalog()
	_test_encounter_catalog()
	_test_reverse_fish()
	_test_kraken_threshold_draw()
	_test_champion_weapon_switch()
	_test_abyss_shared_armor()
	_test_tactical_turn()
	print("CHAPTER_ONE_ENEMY_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_global_balance_adjustments() -> void:
	var fish := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 101)
	if fish == null or fish.get_max_health() != 15:
		_fail("chapter one enemy health was not increased directly in its data")
	elif fish.get_strength() != 2 or fish.get_agility() != 4 or fish.get_intelligence() != 2:
		_fail("chapter one enemy base attributes were not increased directly")
	elif fish.build_strike_profile_object().primary_base_damage != 3:
		_fail("chapter one enemy weapon base damage was not increased directly")

	var guard := ChapterTwoEnemyCatalog.create_enemy(&"gray_shield_guard", 102)
	if guard == null or guard.get_max_health() != 33:
		_fail("chapter two enemy health was not increased directly in its data")
	elif guard.get_strength() != 4 or guard.get_agility() != 3 or guard.get_intelligence() != 2:
		_fail("chapter two enemy base attributes were not increased directly")
	elif guard.build_strike_profile_object().primary_base_damage != 3:
		_fail("chapter two enemy weapon base damage was not increased directly")

	var training_data := load("res://resources/enemies/sample_enemy_data.tres") as EnemyData
	var training_state := EnemyState.new()
	training_state.enemy_data = training_data
	if training_data == null or training_state.get_max_health() != 30 \
			or training_data.innate_base_damage != 5 \
			or training_data.base_strength != 1 \
			or training_data.base_agility != 4 \
			or training_data.base_intelligence != 1:
		_fail("training enemy data did not receive the direct balance adjustment")


func _test_card_catalog() -> void:
	var seen_kinds := {}
	for path in ChapterOneEnemyCatalog.BASIC_CARDS + ChapterOneEnemyCatalog.MUTATION_CARDS:
		var card := load(path) as CardData
		if card == null:
			_fail("missing monster card %s" % path)
			continue
		if not (card.effect is MonsterCardEffect):
			_fail("monster card has wrong effect %s" % path)
			continue
		var kind := (card.effect as MonsterCardEffect).kind
		if seen_kinds.has(kind):
			_fail("duplicate monster effect kind %d" % kind)
		seen_kinds[kind] = true
	if seen_kinds.size() != 16:
		_fail("expected 16 monster card kinds, got %d" % seen_kinds.size())


func _test_enemy_catalog() -> void:
	for index in range(ARCHETYPES.size()):
		var state := ChapterOneEnemyCatalog.create_enemy(ARCHETYPES[index], 9000 + index)
		if state == null or state.enemy_data == null:
			_fail("failed to create archetype %s" % ARCHETYPES[index])
			continue
		if state.enemy_data.weapon_equipment == null:
			_fail("archetype %s has no real weapon" % ARCHETYPES[index])
		if state.enemy_data.portrait == null or state.enemy_data.battle_sprite == null:
			_fail("archetype %s is missing bound portrait or battle art" % ARCHETYPES[index])
		elif state.enemy_data.portrait.resource_path == state.enemy_data.battle_sprite.resource_path:
			_fail("archetype %s still reuses a single atlas texture" % ARCHETYPES[index])
		else:
			for texture in [state.enemy_data.portrait, state.enemy_data.battle_sprite]:
				if not FileAccess.file_exists(texture.resource_path + ".import"):
					_fail("archetype %s art was not imported: %s" % [ARCHETYPES[index], texture.resource_path])
		if state.deck.is_empty():
			_fail("archetype %s generated an empty deck" % ARCHETYPES[index])
		if state.current_health != state.get_max_health():
			_fail("archetype %s did not start at full health" % ARCHETYPES[index])
		if not (state.enemy_data.behavior is TacticalEnemyBehavior):
			_fail("archetype %s does not use tactical intent behavior" % ARCHETYPES[index])


func _test_encounter_catalog() -> void:
	for tier in [AdventureEnums.EncounterTier.WEAK, AdventureEnums.EncounterTier.MIXED, AdventureEnums.EncounterTier.STRONG, AdventureEnums.EncounterTier.ELITE, AdventureEnums.EncounterTier.BOSS]:
		var encounter := ChapterOneEnemyCatalog.pick_encounter(tier, 12345 + tier)
		if str(encounter.get("id", "")).is_empty() or (encounter.get("enemies", []) as Array).is_empty():
			_fail("tier %d produced an empty encounter" % tier)
	for tier_and_count in [[AdventureEnums.EncounterTier.WEAK, 3], [AdventureEnums.EncounterTier.MIXED, 4], [AdventureEnums.EncounterTier.STRONG, 4]]:
		var tier := int(tier_and_count[0])
		var expected_count := int(tier_and_count[1])
		var remaining: Array = []
		var last_id := ""
		var seen := {}
		for index in range(expected_count):
			var draw := ChapterOneEnemyCatalog.draw_encounter(tier, 3100 + index, remaining, last_id)
			var entry := draw.get("encounter", {}) as Dictionary
			last_id = str(entry.get("id", ""))
			seen[last_id] = true
			remaining = draw.get("remaining_ids", []) as Array
		if seen.size() != expected_count:
			_fail("tier %d encounter bag repeated before exhaustion" % tier)


func _test_reverse_fish() -> void:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.enemies.clear()
	scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 77))
	var controller := BattleController.new()
	controller.setup(scenario)
	var fish := controller.enemy_units[0]
	controller.apply_damage(null, fish, 999, "diagnostic", {"fixed_damage": true})
	if not fish.is_alive() or not bool(fish.enemy_state.runtime_state.get("reversed", false)) or fish.get_max_health() != 7:
		_fail("hungry fish did not reverse on first lethal damage")


func _test_kraken_threshold_draw() -> void:
	for case in [[0.8, 2], [0.5, 1], [0.3, 0]]:
		var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
		scenario.scene_prototype = null
		scenario.enemies.clear()
		scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"kraken", 7000 + int(float(case[0]) * 100.0)))
		var controller := BattleController.new()
		controller.setup(scenario)
		var kraken: BattleUnitState = controller.enemy_units[0]
		var draw_template := load("res://resources/cards/monster_cards/approach_bite.tres") as CardData
		for index in range(3):
			kraken.draw_pile.append(draw_template)
		kraken.enemy_state.current_health = maxi(1, int(ceil(float(kraken.get_max_health()) * float(case[0]))))
		var hand_before := kraken.hand.size()
		ChapterOneEnemyRules.on_turn_started(controller, kraken)
		var drawn := kraken.hand.size() - hand_before
		if drawn != int(case[1]):
			_fail("kraken at %.0f%% health drew %d extra cards instead of %d" % [float(case[0]) * 100.0, drawn, int(case[1])])


func _test_champion_weapon_switch() -> void:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	scenario.players.append(load("res://resources/characters/battle_warrior_state.tres") as CharacterState)
	scenario.enemies.clear()
	scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"fish_champion", 1177))
	var controller := BattleController.new()
	controller.setup(scenario)
	var player: BattleUnitState = controller.player_units[0]
	var deploy_cell := BattleHexGrid.INVALID_CELL
	for cell in controller.map_data.get_all_cells():
		if controller.map_data.is_player_deployment_cell(cell):
			deploy_cell = cell
			break
	if deploy_cell == BattleHexGrid.INVALID_CELL or not controller.deploy_player_unit_at_cell(player, deploy_cell):
		_fail("could not deploy champion-switch player")
		return

	var champion: BattleUnitState = controller.enemy_units[0]
	for candidate in BattleHexGrid.neighbors(champion.cell):
		if controller.map_data.is_valid_cell(candidate) \
				and controller.targeting.is_unit_cell_clear(player, candidate, false):
			player.set_hex_cell(candidate, controller.map_data)
			break
	controller.phase = BattleController.Phase.BATTLE
	champion.enemy_state.runtime_state["momentum"] = 3
	var behavior := champion.enemy_state.enemy_data.behavior as TacticalEnemyBehavior
	var switched := behavior._execute_step(controller, champion, {
		"type": "switch",
		"target_id": player.unit_id,
	})
	if not switched:
		_fail("champion switch intent did not execute")
	if champion.enemy_state.active_weapon_index != 1:
		_fail("champion did not switch to reserve spear")
	if int(champion.enemy_state.runtime_state.get("momentum", -1)) != 0:
		_fail("champion switch did not consume momentum")
	if champion.pending_next_attack_damage_bonus != 6:
		_fail("champion switch did not grant the expected next-attack bonus")

	var charge := load("res://resources/cards/battle_charge.tres") as CardData
	var effect := charge.effect as ChargeCardEffect
	var charge_context := {"controller": controller, "user": champion, "card": charge}
	var charge_targets := effect.get_valid_targets(charge_context)
	if not charge_targets.has(player):
		_fail("champion had no valid charge target after switching to spear")
		return
	champion.hand.append(charge)
	champion.current_ap = 10
	controller.current_unit = champion
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	if not controller.play_card(champion, charge, [player]):
		_fail("champion could not resolve a unit-target charge after switching")


func _test_abyss_shared_armor() -> void:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	scenario.players.append(load("res://resources/characters/battle_warrior_state.tres") as CharacterState)
	scenario.players.append(load("res://resources/characters/battle_ranger_state.tres") as CharacterState)
	scenario.enemies.clear()
	scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"abyss_scale", 1888))
	var controller := BattleController.new()
	controller.setup(scenario)
	var boss := controller.enemy_units[0]
	ChapterOneEnemyRules.on_battle_started(controller)
	if boss.get_armor_stacks() != 0:
		_fail("abyss scale incorrectly owns the shared armor")
	for player in controller.player_units:
		var shared := player.get_status("abyss_shared_armor")
		if shared == null or shared.stacks != 16:
			_fail("player did not receive the 16-point shared armor status")
		elif not (shared is AbyssSharedArmorStatus) \
				or (shared as AbyssSharedArmorStatus).boss_unit_id != boss.unit_id:
			_fail("shared armor status lost its abyss scale runtime reference")
	var first_player := controller.player_units[0]
	var second_player := controller.player_units[1]
	var first_health := first_player.get_current_health()
	# The shared pool absorbs the full request after personal mitigation.
	controller.apply_damage(boss, first_player, 6, "shared armor diagnostic", {"fixed_damage": true})
	if first_player.get_current_health() != first_health:
		_fail("shared armor did not absorb damage to the first player")
	for player in controller.player_units:
		var shared := player.get_status("abyss_shared_armor")
		if shared == null or shared.stacks != 10:
			_fail("shared armor pool did not synchronize after partial damage: status=%d runtime=%d" % [
				shared.stacks if shared != null else -1,
				int(boss.enemy_state.runtime_state.get("abyss_shared_armor", -1)),
			])
	if int(boss.enemy_state.runtime_state.get("abyss_phase", 0)) != 1:
		_fail("abyss scale changed phase before shared armor was broken")
	var second_health := second_player.get_current_health()
	controller.apply_damage(boss, second_player, 20, "shared armor break diagnostic", {"fixed_damage": true})
	if second_player.get_current_health() != second_health - 10:
		_fail("shared armor overflow damage was not applied correctly: before=%d after=%d runtime=%d" % [
			second_health,
			second_player.get_current_health(),
			int(boss.enemy_state.runtime_state.get("abyss_shared_armor", -1)),
		])
	for player in controller.player_units:
		if player.has_status("abyss_shared_armor"):
			_fail("broken shared armor status remained on a player")
	if int(boss.enemy_state.runtime_state.get("abyss_phase", 0)) != 2 \
			or boss.enemy_state.active_weapon_index != 1:
		_fail("abyss scale did not enter phase two when shared armor broke")


func _test_tactical_turn() -> void:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	scenario.players.append(load("res://resources/characters/battle_warrior_state.tres") as CharacterState)
	scenario.enemies.clear()
	scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"harpoon_fish", 177))
	var controller := BattleController.new()
	controller.setup(scenario)
	var player := controller.player_units[0]
	var deploy_cell := BattleHexGrid.INVALID_CELL
	for cell in controller.map_data.get_all_cells():
		if controller.map_data.is_player_deployment_cell(cell):
			deploy_cell = cell
			break
	if deploy_cell == BattleHexGrid.INVALID_CELL or not controller.deploy_player_unit_at_cell(player, deploy_cell):
		_fail("could not deploy tactical-turn player")
		return
	var enemy := controller.enemy_units[0]
	var enemy_start_cell := enemy.cell
	if not controller.start_battle():
		_fail("could not start tactical-turn battle")
		return
	if enemy.enemy_state.intent_plan == null:
		_fail("enemy has no locked intent")
		return
	if controller.current_unit == player:
		controller.end_current_turn()
	if controller.phase == BattleController.Phase.BATTLE and controller.current_unit != player:
		_fail("enemy tactical turn did not return control to player")
	if enemy.enemy_state.seen_card_names.is_empty() and enemy.cell == enemy_start_cell:
		_fail("enemy tactical turn produced no public or movement state")


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("CHAPTER_ONE_ENEMY_DIAG: " + message)
