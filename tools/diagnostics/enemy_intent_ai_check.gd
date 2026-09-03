extends Node

var _exit_code := 0


func _ready() -> void:
	_test_multi_intent_rating_isolation()
	_test_profile_presets()
	_test_category_only_public_plan()
	_test_intent_budget_allocation_and_returns()
	_test_adjacent_intents_merge_only()
	_test_intent_action_limit()
	_test_intent_modifier_normalization()
	_test_fallback_reduction_and_residual_discard()
	_test_dynamic_action_selection()
	_test_fallback_finishes_with_ap_remaining()
	_test_chapter_catalog_tactical_metadata()
	_test_public_intent_ui_text()
	_test_intent_order_prefers_setup_combo()
	_test_chapter_one_uses_monster_class_copies()
	_test_multi_role_card_respects_intent_targeting()
	print("ENEMY_INTENT_AI_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_multi_intent_rating_isolation() -> void:
	var card := CardData.new()
	card.card_name = "攻守测试牌"
	var attack_rating := EnemyCardIntentRating.new()
	attack_rating.category = EnemyIntentCategory.Type.ATTACK
	attack_rating.base_score = 11
	attack_rating.damage_value = 4
	var defend_rating := EnemyCardIntentRating.new()
	defend_rating.category = EnemyIntentCategory.Type.DEFEND
	defend_rating.base_score = 7
	defend_rating.defense_value = 6
	var entry := EnemyCardPoolEntry.new()
	entry.card = card
	entry.intent_ratings = [attack_rating, defend_rating]

	var runtime_copy := card.duplicate() as CardData
	if not entry.matches_card(runtime_copy):
		_fail("runtime card copy did not resolve its tactical entry")
	var resolved_attack := entry.get_intent_rating(EnemyIntentCategory.Type.ATTACK)
	var resolved_defend := entry.get_intent_rating(EnemyIntentCategory.Type.DEFEND)
	if resolved_attack != attack_rating or resolved_attack.defense_value != 0:
		_fail("attack intent leaked another intent's numeric values")
	if resolved_defend != defend_rating or resolved_defend.damage_value != 0:
		_fail("defend intent leaked another intent's numeric values")
	if entry.get_intent_rating(EnemyIntentCategory.Type.CURSE) != null:
		_fail("entry matched an intent category it does not have")

	var rule := EnemyDeckRule.new()
	rule.tactical_entries.append(entry)
	if rule.find_tactical_entry(runtime_copy) != entry:
		_fail("deck rule could not find tactical metadata for a runtime copy")


func _test_profile_presets() -> void:
	var balanced := EnemyAIProfile.create_preset(EnemyAIProfile.Preset.BALANCED)
	var ranged := EnemyAIProfile.create_preset(EnemyAIProfile.Preset.RANGED_CONTROL)
	var guard := EnemyAIProfile.create_preset(EnemyAIProfile.Preset.LOW_HEALTH_GUARD)
	var berserk := EnemyAIProfile.create_preset(EnemyAIProfile.Preset.LOW_HEALTH_BERSERK)
	if balanced == null or ranged == null or guard == null or berserk == null:
		_fail("an AI profile preset could not be created")
		return
	if ranged.get_intent_weight(EnemyIntentCategory.Type.RETREAT) <= balanced.get_intent_weight(EnemyIntentCategory.Type.RETREAT):
		_fail("ranged profile does not prefer retreat over balanced profile")
	if guard.get_low_health_modifier(EnemyIntentCategory.Type.DEFEND) <= berserk.get_low_health_modifier(EnemyIntentCategory.Type.DEFEND):
		_fail("guard profile is not more defensive at low health")
	if berserk.get_low_health_modifier(EnemyIntentCategory.Type.ATTACK) <= guard.get_low_health_modifier(EnemyIntentCategory.Type.ATTACK):
		_fail("berserk profile is not more aggressive at low health")


func _test_category_only_public_plan() -> void:
	var plan := EnemyIntentPlan.new()
	plan.configure(
		PackedInt32Array([
			EnemyIntentCategory.Type.UTILITY,
			EnemyIntentCategory.Type.ATTACK,
		]),
		EnemyIntentCategory.Type.DEFEND,
		3
	)
	if plan.round_locked != 3 or plan.primary_intents != PackedInt32Array([
		EnemyIntentCategory.Type.UTILITY,
		EnemyIntentCategory.Type.ATTACK,
	]):
		_fail("public plan did not preserve its two primary intent categories")
	for property in plan.get_property_list():
		if str(property.get("name", "")) == "steps":
			_fail("public plan still exposes concrete action steps")
	if plan.get_headline() != "功能 → 攻击" or not plan.get_summary().contains("备 防御"):
		_fail("public plan category summary is incorrect")


func _test_intent_budget_allocation_and_returns() -> void:
	var plan := EnemyIntentPlan.new()
	plan.configure(PackedInt32Array([
		EnemyIntentCategory.Type.UTILITY,
		EnemyIntentCategory.Type.ATTACK,
	]), EnemyIntentCategory.Type.DEFEND, 3)
	plan.prepare_execution(5)
	_assert_int_array(plan.primary_allocations, PackedInt32Array([2, 2]), "primary allocations")
	if plan.residual_ap != 1 or plan.get_current_budget() != 2:
		_fail("intent allocation did not reserve the residual AP")
	plan.consume_current_budget(1)
	plan.complete_current_group()
	if plan.residual_ap != 2 or plan.get_current_budget() != 2:
		_fail("unused primary AP did not return before fallback")
	plan.consume_current_budget(2)
	plan.complete_current_group()
	if not plan.is_fallback_stage() or plan.get_current_budget() != 2:
		_fail("fallback did not receive up to 2 residual AP")
	plan.consume_current_budget(1)
	plan.complete_current_group()
	if not plan.is_finished() or plan.residual_ap != 0:
		_fail("fallback remainder was returned instead of discarded")


func _test_adjacent_intents_merge_only() -> void:
	var adjacent := EnemyIntentPlan.new()
	adjacent.configure(PackedInt32Array([
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.DEFEND,
	]), EnemyIntentCategory.Type.ATTACK, 1)
	adjacent.prepare_execution(6)
	if adjacent.execution_groups.size() != 2 \
			or adjacent.execution_groups[0].allocated_ap != 4:
		_fail("adjacent attack intents did not merge into a 4 AP group")

	var separated := EnemyIntentPlan.new()
	separated.configure(PackedInt32Array([
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.DEFEND,
		EnemyIntentCategory.Type.ATTACK,
	]), EnemyIntentCategory.Type.ATTACK, 1)
	separated.prepare_execution(6)
	if separated.execution_groups.size() != 3:
		_fail("non-adjacent attack intents merged")


func _test_intent_action_limit() -> void:
	var plan := EnemyIntentPlan.new()
	plan.configure(
		PackedInt32Array([EnemyIntentCategory.Type.UTILITY]),
		EnemyIntentCategory.Type.DEFEND,
		1
	)
	plan.prepare_execution(2)
	for _index in range(EnemyIntentPlan.MAX_ACTIONS_PER_GROUP):
		plan.consume_current_budget(0)
	if not plan.current_group_reached_action_limit():
		_fail("intent group did not stop after 8 zero-cost actions")
	var group := plan.get_current_group()
	var remaining_before_ninth := plan.get_current_budget()
	if plan.consume_current_budget(0) != 0 or group.action_count != EnemyIntentPlan.MAX_ACTIONS_PER_GROUP \
			or plan.get_current_budget() != remaining_before_ninth:
		_fail("ninth zero-cost action changed a capped intent group")
	plan.complete_current_group()
	if not plan.is_fallback_stage() or plan.get_current_budget() != 2:
		_fail("capped primary did not return unused AP to fallback")


func _test_intent_modifier_normalization() -> void:
	var negative := EnemyIntentPlan.new()
	negative.configure(PackedInt32Array([EnemyIntentCategory.Type.ATTACK]), EnemyIntentCategory.Type.DEFEND, 1)
	negative.stolen_ap_total = -5
	negative.primary_ap_reductions = PackedInt32Array([-1])
	negative.fallback_ap_reduction = -1
	negative.prepare_execution(3)
	_assert_int_array(negative.primary_allocations, PackedInt32Array([2]), "negative modifier allocation")
	if negative.residual_ap != 1 or negative.get_current_group().allocated_ap != 2:
		_fail("negative theft or primary reduction minted AP")
	negative.complete_current_group()
	if negative.get_current_budget() != 2:
		_fail("negative fallback reduction exceeded its 2 AP cap")

	var reduced := EnemyIntentPlan.new()
	reduced.configure(PackedInt32Array([
		EnemyIntentCategory.Type.UTILITY,
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.DEFEND,
	]), EnemyIntentCategory.Type.CURSE, 1)
	reduced.stolen_ap_total = 3
	reduced.primary_ap_reductions = PackedInt32Array([1, 0, 2])
	reduced.prepare_execution(8)
	_assert_int_array(reduced.primary_allocations, PackedInt32Array([1, 2, 0]), "reduced ordered allocations")
	if reduced.residual_ap != 2:
		_fail("stolen AP and primary reductions did not leave the expected residual")


func _test_fallback_reduction_and_residual_discard() -> void:
	var plan := EnemyIntentPlan.new()
	plan.configure(PackedInt32Array([EnemyIntentCategory.Type.UTILITY]), EnemyIntentCategory.Type.DEFEND, 1)
	plan.fallback_ap_reduction = 1
	plan.prepare_execution(6)
	if plan.get_current_budget() != 2 or plan.residual_ap != 4:
		_fail("fallback reduction changed primary allocation")
	plan.complete_current_group()
	if not plan.is_fallback_stage() or plan.get_current_budget() != 1 or plan.residual_ap != 5:
		_fail("fallback reduction did not cap only the fallback group")
	plan.complete_current_group()
	if not plan.is_finished() or plan.residual_ap != 0:
		_fail("fallback did not discard residual AP beyond its capped budget")


func _test_dynamic_action_selection() -> void:
	var controller := _make_test_controller()
	if controller == null:
		return
	var enemy: BattleUnitState = controller.enemy_units[0]
	var hide_template := load("res://resources/cards/monster_cards/hunker_hide.tres") as CardData
	var eye_template := load("res://resources/cards/monster_cards/empty_eye.tres") as CardData
	var hide := hide_template.duplicate() as CardData
	var eye := eye_template.duplicate() as CardData
	var hide_entry := _make_entry(hide_template, EnemyIntentCategory.Type.DEFEND, 12, 0, 5)
	var eye_entry := _make_entry(eye_template, EnemyIntentCategory.Type.DEFEND, 5, 0, 1)
	enemy.enemy_state.enemy_data.deck_rule.tactical_entries = [hide_entry, eye_entry]
	enemy.hand = [hide, eye]
	enemy.current_ap = 4
	var chosen := EnemyIntentPlanner.choose_action(controller, enemy, EnemyIntentCategory.Type.DEFEND, 4, PackedStringArray())
	if chosen == null or chosen.card != hide:
		_fail("dynamic planner did not select the higher-scored current-intent card")
	enemy.hand = [eye]
	chosen = EnemyIntentPlanner.choose_action(controller, enemy, EnemyIntentCategory.Type.DEFEND, 4, PackedStringArray())
	if chosen == null or chosen.card != eye:
		_fail("dynamic planner retained a concrete card after the hand changed")
	var too_small_budget := EnemyIntentPlanner.choose_action(controller, enemy, EnemyIntentCategory.Type.DEFEND, 0, PackedStringArray())
	if too_small_budget != null:
		_fail("dynamic planner ignored the current intent AP budget")


func _test_fallback_finishes_with_ap_remaining() -> void:
	var controller := _make_test_controller()
	if controller == null:
		return
	var enemy: BattleUnitState = controller.enemy_units[0]
	enemy.hand.clear()
	enemy.current_ap = 4
	enemy.enemy_state.intent_plan.configure(
		PackedInt32Array([
			EnemyIntentCategory.Type.UTILITY,
			EnemyIntentCategory.Type.CURSE,
		]),
		EnemyIntentCategory.Type.DEFEND,
		1
	)
	var behavior := enemy.enemy_state.enemy_data.behavior as TacticalEnemyBehavior
	var result := behavior.choose_action({"controller": controller}, enemy)
	if bool(result.get("action_started", false)):
		_fail("empty intent stages unexpectedly started an action")
	if not enemy.enemy_state.intent_plan.is_finished() or enemy.current_ap != 4:
		_fail("fallback completion did not end planning with AP remaining")


func _make_entry(card: CardData, category: int, score: int, damage: int, defense: int) -> EnemyCardPoolEntry:
	var rating := EnemyCardIntentRating.new()
	rating.category = category
	rating.base_score = score
	rating.damage_value = damage
	rating.defense_value = defense
	var entry := EnemyCardPoolEntry.new()
	entry.card = card
	entry.intent_ratings = [rating]
	return entry


func _make_test_controller(archetypes: Array = [&"hungry_fish"]) -> BattleController:
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
		scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(StringName(archetypes[index]), 811 + index))
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _test_chapter_catalog_tactical_metadata() -> void:
	var chapter_one_ids := [
		&"hungry_fish", &"harpoon_fish", &"bandit_blade", &"bandit_bow", &"fish_priest",
		&"unclean_one", &"fish_champion", &"kraken", &"high_priest", &"abyss_scale",
	]
	var chapter_two_ids := [
		&"gray_shield_guard", &"holy_spearman", &"fortress_crossbow", &"field_priest",
		&"punishment_knight", &"standard_bearer", &"holy_bastion_commander", &"creation_shard",
		&"blood_construct", &"corrupt_heart_veil", &"gray_bastion_paladin", &"military_god_remains",
		&"flesh_spawn",
	]
	for index in range(chapter_one_ids.size()):
		_assert_enemy_has_tactical_metadata(ChapterOneEnemyCatalog.create_enemy(chapter_one_ids[index], 90000 + index))
	for index in range(chapter_two_ids.size()):
		_assert_enemy_has_tactical_metadata(ChapterTwoEnemyCatalog.create_enemy(chapter_two_ids[index], 91000 + index))
	var ranged := ChapterOneEnemyCatalog.create_enemy(&"bandit_bow", 92001)
	var guard := ChapterTwoEnemyCatalog.create_enemy(&"gray_shield_guard", 92002)
	var berserk := ChapterTwoEnemyCatalog.create_enemy(&"punishment_knight", 92003)
	if ranged.enemy_data.ai_profile == null or ranged.enemy_data.ai_profile.preset != EnemyAIProfile.Preset.RANGED_CONTROL:
		_fail("ranged enemy did not receive the ranged-control AI profile")
	if guard.enemy_data.ai_profile == null or guard.enemy_data.ai_profile.preset != EnemyAIProfile.Preset.LOW_HEALTH_GUARD:
		_fail("defensive enemy did not receive the low-health guard profile")
	if berserk.enemy_data.ai_profile == null or berserk.enemy_data.ai_profile.preset != EnemyAIProfile.Preset.LOW_HEALTH_BERSERK:
		_fail("aggressive enemy did not receive the low-health berserk profile")


func _assert_enemy_has_tactical_metadata(state: EnemyState) -> void:
	if state == null or state.enemy_data == null or state.enemy_data.deck_rule == null:
		_fail("enemy catalog returned incomplete tactical data")
		return
	if state.enemy_data.ai_profile == null:
		_fail("%s has no AI profile" % state.get_enemy_name())
	for stack in state.deck:
		if stack == null or stack.card_data == null:
			continue
		var entry := state.enemy_data.deck_rule.find_tactical_entry(stack.card_data)
		if entry == null or entry.intent_ratings.is_empty():
			_fail("%s card %s has no tactical intent rating" % [state.get_enemy_name(), stack.card_data.card_name])


func _test_public_intent_ui_text() -> void:
	var controller := _make_test_controller()
	if controller == null:
		return
	var enemy: BattleUnitState = controller.enemy_units[0]
	enemy.enemy_state.intent_plan.configure(
		PackedInt32Array([
			EnemyIntentCategory.Type.UTILITY,
			EnemyIntentCategory.Type.ATTACK,
		]),
		EnemyIntentCategory.Type.DEFEND,
		1
	)
	var panel := BattleDetailPanel.new()
	var intent_text: String = panel._build_enemy_intent(enemy)
	panel.free()
	if not intent_text.contains("主要：功能 → 攻击") or not intent_text.contains("备用：防御"):
		_fail("detail panel does not show the three public intent categories")
	if intent_text.contains("1.") or intent_text.contains(" AP") or intent_text.contains("猛击"):
		_fail("detail panel still leaks concrete intent actions")


func _test_intent_order_prefers_setup_combo() -> void:
	var controller := _make_test_controller()
	if controller == null:
		return
	var enemy: BattleUnitState = controller.enemy_units[0]
	var player: BattleUnitState = controller.player_units[0]
	_place_adjacent(controller, enemy, player)
	var setup_card := (load("res://resources/cards/monster_cards/empty_eye.tres") as CardData).duplicate() as CardData
	var attack_card := (load("res://resources/cards/monster_cards/approach_bite.tres") as CardData).duplicate() as CardData
	var setup_entry := _make_entry(setup_card, EnemyIntentCategory.Type.UTILITY, 10, 0, 0)
	setup_entry.intent_ratings[0].provided_tags = PackedStringArray(["damage_buff"])
	var attack_entry := _make_entry(attack_card, EnemyIntentCategory.Type.ATTACK, 10, 4, 0)
	attack_entry.intent_ratings[0].preferred_tags = PackedStringArray(["damage_buff"])
	attack_entry.intent_ratings[0].combo_bonus = 8
	enemy.enemy_state.enemy_data.deck_rule.tactical_entries = [setup_entry, attack_entry]
	enemy.hand = [setup_card, attack_card]
	var plan := EnemyIntentPlanner.build_plan(controller, enemy, 2)
	if plan.primary_intents.size() < 2 or plan.primary_intents[0] != EnemyIntentCategory.Type.UTILITY \
			or plan.primary_intents[1] != EnemyIntentCategory.Type.ATTACK:
		_fail("intent ordering did not prefer setup before its tagged attack follow-up")


func _place_adjacent(controller: BattleController, first: BattleUnitState, second: BattleUnitState) -> void:
	for cell in controller.map_data.get_all_cells():
		for neighbor in controller.map_data.get_cells_in_range(cell, 1):
			if neighbor == cell or not controller.map_data.is_valid_cell(neighbor):
				continue
			first.set_hex_cell(cell, controller.map_data)
			second.set_hex_cell(neighbor, controller.map_data)
			first.is_deployed = true
			second.is_deployed = true
			return


func _test_chapter_one_uses_monster_class_copies() -> void:
	var expected_names := PackedStringArray([
		"猛击", "冲锋", "防御架势", "险步突袭", "弩索牵引",
		"苍翠打击", "月光", "根系洞察", "蓄翠化形", "野性变形",
	])
	var expected_by_archetype := {
		&"bandit_blade": PackedStringArray(["猛击", "冲锋"]),
		&"bandit_bow": PackedStringArray(["险步突袭", "弩索牵引"]),
		&"fish_priest": PackedStringArray(["苍翠打击", "月光"]),
		&"fish_champion": PackedStringArray(["猛击", "冲锋", "防御架势"]),
		&"high_priest": PackedStringArray(["苍翠打击", "月光", "根系洞察", "蓄翠化形", "野性变形"]),
	}
	for archetype in [&"bandit_blade", &"bandit_bow", &"fish_priest", &"fish_champion", &"high_priest"]:
		var state := ChapterOneEnemyCatalog.create_enemy(archetype, 93000)
		var found_names := PackedStringArray()
		for stack in state.deck:
			if stack == null or stack.card_data == null or not expected_names.has(stack.card_data.card_name):
				continue
			found_names.append(stack.card_data.card_name)
			if stack.card_data.reward_eligible:
				_fail("monster class copy %s is still reward eligible" % stack.card_data.card_name)
			if not (stack.card_data.effect is ChapterOneEnemyClassCardEffect):
				_fail("%s still references a player class effect" % stack.card_data.card_name)
		for expected_name in expected_by_archetype[archetype]:
			if not found_names.has(expected_name):
				_fail("%s is missing monster class copy %s" % [archetype, expected_name])


func _test_multi_role_card_respects_intent_targeting() -> void:
	var controller := _make_test_controller([&"fish_priest", &"hungry_fish"])
	if controller == null:
		return
	var priest: BattleUnitState = controller.enemy_units[0]
	var ally: BattleUnitState = controller.enemy_units[1]
	var player: BattleUnitState = controller.player_units[0]
	var center := controller.map_data.get_all_cells()[0]
	var neighbors := controller.map_data.get_cells_in_range(center, 1)
	if neighbors.size() < 3:
		_fail("multi-role targeting diagnostic could not place units")
		return
	priest.set_hex_cell(center, controller.map_data)
	ally.set_hex_cell(neighbors[1], controller.map_data)
	player.set_hex_cell(neighbors[2], controller.map_data)
	ally.set_current_health(maxi(1, ally.get_max_health() - 5))
	var moonlight: CardData
	for stack in priest.enemy_state.enemy_data.deck_rule.fixed_cards:
		if stack != null and stack.card_data != null and stack.card_data.card_name == "月光":
			moonlight = stack.card_data.duplicate(true) as CardData
			break
	if moonlight == null:
		_fail("fish priest has no monster moonlight copy")
		return
	priest.hand = [moonlight]
	priest.current_ap = 1
	var defend := EnemyIntentPlanner.choose_action(controller, priest, EnemyIntentCategory.Type.DEFEND, 1)
	if defend == null or defend.targets.is_empty() or defend.targets[0] != ally:
		_fail("moonlight defense intent did not select the wounded ally")
	var attack := EnemyIntentPlanner.choose_action(controller, priest, EnemyIntentCategory.Type.ATTACK, 1)
	if attack == null or attack.targets.is_empty() or attack.targets[0] != player:
		_fail("moonlight attack intent did not select an opponent")


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("ENEMY_INTENT_AI_DIAG: " + message)


func _assert_int_array(actual: PackedInt32Array, expected: PackedInt32Array, label: String) -> void:
	if actual != expected:
		_fail("%s expected %s, got %s" % [label, str(expected), str(actual)])
