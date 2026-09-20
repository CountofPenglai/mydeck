extends Node

var _exit_code := 0


func _ready() -> void:
	var controller := _build_controller()
	if controller == null:
		get_tree().quit(1)
		return
	var warrior := _find_warrior(controller)
	var enemy := _find_enemy(controller)
	if warrior == null or enemy == null:
		_fail("WARRIOR_COMMON: missing diagnostic units")
		get_tree().quit(_exit_code)
		return
	_prepare_combat(controller, warrior, enemy)
	_test_resources_are_common_and_reward_eligible(warrior)
	_test_defensive_pursuit(controller, warrior, enemy)
	_test_unfinished_guard(controller, warrior)
	_test_turning_slash(controller, warrior, enemy)
	_test_field_refit(controller, warrior)
	_test_advance_retreat(controller, warrior, enemy)
	print("WARRIOR_COMMON: completed")
	get_tree().quit(_exit_code)


func _test_resources_are_common_and_reward_eligible(warrior: BattleUnitState) -> void:
	var reward_paths: Dictionary = {}
	var reward_service := AdventureRewardService.new()
	for candidate in reward_service.get_card_candidates(CardEnums.CardClass.WARRIOR, CardEnums.Rarity.COMMON, 20260920, 4, 99):
		reward_paths[str(candidate.get("path", ""))] = true
	for resource_name in [
		"warrior_defensive_pursuit",
		"warrior_unfinished_guard",
		"warrior_turning_slash",
		"warrior_field_refit",
		"warrior_advance_retreat",
	]:
		var card := load("res://resources/cards/%s.tres" % resource_name) as CardData
		if card == null:
			_fail("WARRIOR_COMMON: missing common card %s" % resource_name)
		elif card.rarity != CardEnums.Rarity.COMMON or not card.can_appear_in_rewards():
			_fail("WARRIOR_COMMON: %s is not reward-eligible common" % resource_name)
		elif not reward_paths.has(card.resource_path):
			_fail("WARRIOR_COMMON: %s is absent from actual Warrior common rewards" % resource_name)
		for starter_card in warrior.draw_pile + warrior.hand + warrior.discard_pile:
			if starter_card != null and starter_card.card_name == card.card_name:
				_fail("WARRIOR_COMMON: %s incorrectly entered the starter deck" % resource_name)


func _test_defensive_pursuit(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/warrior_defensive_pursuit.tres") as CardData
	if template == null:
		return
	_reset(warrior, enemy)
	var normal := template.duplicate() as CardData
	if normal.requires_weapon_choice({"play_mode": CardEnums.CardPlayMode.NORMAL}):
		_fail("WARRIOR_COMMON: defensive pursuit normal mode requested a weapon choice")
	if not normal.requires_weapon_choice({"play_mode": CardEnums.CardPlayMode.MOMENTUM}):
		_fail("WARRIOR_COMMON: defensive pursuit momentum mode did not request a weapon choice")
	warrior.hand.append(normal)
	warrior.current_ap = 10
	if not controller.play_card(warrior, normal, [warrior]) or warrior.get_armor_stacks() != 2:
		_fail("WARRIOR_COMMON: defensive pursuit normal did not grant exactly 2 armor")
	_reset(warrior, enemy)
	var unavailable := template.duplicate() as CardData
	warrior.discard_pile.append(unavailable)
	warrior.current_ap = 7
	if controller.play_card(warrior, unavailable, [enemy], {}, CardEnums.CardPlayMode.MOMENTUM) or warrior.current_ap != 7:
		_fail("WARRIOR_COMMON: defensive pursuit allowed momentum without armor")
	_reset(warrior, enemy)
	warrior.gain_armor(7, {"controller": controller})
	var momentum := template.duplicate() as CardData
	warrior.discard_pile.append(momentum)
	warrior.current_ap = 10
	var health_before := enemy.get_current_health()
	if not controller.play_card(warrior, momentum, [enemy], {}, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_COMMON: defensive pursuit momentum play failed")
	elif warrior.get_armor_stacks() != 2 or enemy.get_current_health() > health_before - 10:
		_fail("WARRIOR_COMMON: defensive pursuit did not consume capped armor for +10 strike")


func _test_unfinished_guard(controller: BattleController, warrior: BattleUnitState) -> void:
	var template := load("res://resources/cards/warrior_unfinished_guard.tres") as CardData
	if template == null:
		return
	_reset(warrior)
	var normal := template.duplicate() as CardData
	warrior.hand.append(normal)
	warrior.current_ap = 10
	if not controller.play_card(warrior, normal, [warrior]) or warrior.get_armor_stacks() != 4:
		_fail("WARRIOR_COMMON: unfinished guard normal did not grant 4 armor")
	_reset(warrior)
	var unavailable := template.duplicate() as CardData
	warrior.discard_pile.append(unavailable)
	warrior.current_ap = 7
	if controller.play_card(warrior, unavailable, [warrior], {}, CardEnums.CardPlayMode.MOMENTUM) or warrior.current_ap != 7:
		_fail("WARRIOR_COMMON: unfinished guard allowed momentum below 4 armor")
	_reset(warrior)
	warrior.gain_armor(4, {"controller": controller})
	var momentum := template.duplicate() as CardData
	warrior.discard_pile.append(momentum)
	warrior.current_ap = 10
	if not controller.play_card(warrior, momentum, [warrior], {}, CardEnums.CardPlayMode.MOMENTUM) or not warrior.has_status("block"):
		_fail("WARRIOR_COMMON: unfinished guard momentum did not grant block")


func _test_turning_slash(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/warrior_turning_slash.tres") as CardData
	if template == null:
		return
	_reset(warrior, enemy)
	_ensure_spare_weapon(warrior)
	var card := template.duplicate() as CardData
	warrior.hand.append(card)
	warrior.current_ap = 10
	var weapon_before := warrior.character_state.weapon_equipment
	var health_before := enemy.get_current_health()
	if not controller.play_card(warrior, card, [enemy]):
		_fail("WARRIOR_COMMON: turning slash play failed")
	elif warrior.character_state.weapon_equipment == weapon_before or enemy.get_current_health() > health_before - 1:
		_fail("WARRIOR_COMMON: turning slash missed strike or switch")
	_reset(warrior, enemy)
	warrior.character_state.reserve_weapon_equipment = null
	var failed_switch := template.duplicate() as CardData
	warrior.hand.append(failed_switch)
	warrior.current_ap = 10
	health_before = enemy.get_current_health()
	if not controller.play_card(warrior, failed_switch, [enemy]) or enemy.get_current_health() >= health_before:
		_fail("WARRIOR_COMMON: turning slash lost its first strike when the switch failed")


func _test_field_refit(controller: BattleController, warrior: BattleUnitState) -> void:
	var template := load("res://resources/cards/warrior_field_refit.tres") as CardData
	if template == null:
		return
	_reset(warrior)
	warrior.character_state.reserve_weapon_equipment = null
	var blocked := template.duplicate() as CardData
	warrior.hand.append(blocked)
	warrior.current_ap = 7
	if controller.play_card(warrior, blocked, [warrior]) or warrior.current_ap != 7:
		_fail("WARRIOR_COMMON: field refit spent AP without a spare weapon")
	_ensure_spare_weapon(warrior)
	var card := template.duplicate() as CardData
	var draw := _dummy_card()
	warrior.hand.assign([card])
	warrior.draw_pile.assign([draw])
	warrior.current_ap = 10
	if not controller.play_card(warrior, card, [warrior]) or warrior.hand.find(draw) < 0:
		_fail("WARRIOR_COMMON: field refit did not switch and draw")


func _test_advance_retreat(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/warrior_advance_retreat.tres") as CardData
	if template == null:
		return
	_reset(warrior, enemy)
	var missing_choice := template.duplicate() as CardData
	warrior.hand.append(missing_choice)
	warrior.current_ap = 10
	var ap_before := warrior.current_ap
	if controller.play_card(warrior, missing_choice, [enemy]) or warrior.current_ap != ap_before:
		_fail("WARRIOR_COMMON: advance retreat consumed AP without a selected choice")
	_reset(warrior, enemy)
	var steady := template.duplicate() as CardData
	warrior.hand.append(steady)
	warrior.current_ap = 10
	if not controller.play_card(warrior, steady, [enemy], {"card_choice": "steady"}):
		_fail("WARRIOR_COMMON: advance retreat steady play failed")
	elif warrior.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) != 1 or warrior.get_armor_stacks() != 2:
		_fail("WARRIOR_COMMON: advance retreat steady did not grant momentum and armor")
	_reset(warrior, enemy)
	var strong := template.duplicate() as CardData
	warrior.hand.append(strong)
	warrior.current_ap = 10
	ap_before = warrior.current_ap
	if controller.play_card(warrior, strong, [enemy], {"card_choice": "assault"}) or warrior.current_ap != ap_before:
		_fail("WARRIOR_COMMON: advance retreat allowed strong attack without 2 momentum")
	var momentum := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	if momentum != null:
		momentum.current_value = 2
	var health_before := enemy.get_current_health()
	if not controller.play_card(warrior, strong, [enemy], {"card_choice": "assault"}) or warrior.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) != 0 or enemy.get_current_health() >= health_before:
		_fail("WARRIOR_COMMON: advance retreat assault did not spend 2 momentum for its strike")


func _build_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("WARRIOR_COMMON: failed to load scenario")
		return null
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _find_warrior(controller: BattleController) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			return unit
	return null


func _find_enemy(controller: BattleController) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit.faction == BattleUnitState.Faction.ENEMY:
			return unit
	return null


func _prepare_combat(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	warrior.set_hex_cell(Vector2i(3, 3), controller.map_data)
	warrior.is_deployed = true
	enemy.set_hex_cell(Vector2i(4, 3), controller.map_data)
	warrior.ensure_initialized(controller.config, controller.rng)
	warrior.turn_serial = 1


func _reset(warrior: BattleUnitState, enemy: BattleUnitState = null) -> void:
	warrior.hand.clear()
	warrior.draw_pile.clear()
	warrior.discard_pile.clear()
	warrior.exiled_pile.clear()
	warrior.statuses.clear()
	warrior.current_ap = 10
	var momentum := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	if momentum != null:
		momentum.current_value = 0
	if enemy != null:
		enemy.statuses.clear()
		enemy.set_current_health(enemy.get_max_health())


func _ensure_spare_weapon(warrior: BattleUnitState) -> void:
	if warrior.character_state.reserve_weapon_equipment == null:
		warrior.character_state.reserve_weapon_equipment = load("res://resources/items/training_sword.tres") as EquipmentData


func _dummy_card() -> CardData:
	return (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData


func _fail(message: String) -> void:
	push_error(message)
	_exit_code = 1
