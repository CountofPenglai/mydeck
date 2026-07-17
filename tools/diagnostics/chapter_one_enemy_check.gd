extends Node

const ARCHETYPES := [
	&"hungry_fish", &"harpoon_fish", &"bandit_blade", &"bandit_bow", &"fish_priest",
	&"unclean_one", &"fish_champion", &"kraken", &"high_priest", &"abyss_scale",
]

var _exit_code := 0


func _ready() -> void:
	_test_card_catalog()
	_test_enemy_catalog()
	_test_encounter_catalog()
	_test_reverse_fish()
	_test_tactical_turn()
	print("CHAPTER_ONE_ENEMY_DIAG: completed")
	get_tree().quit(_exit_code)


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
	if not fish.is_alive() or not bool(fish.enemy_state.runtime_state.get("reversed", false)) or fish.get_max_health() != 5:
		_fail("hungry fish did not reverse on first lethal damage")


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
