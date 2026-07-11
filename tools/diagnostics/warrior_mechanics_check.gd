extends Node

var _exit_code: int = 0


func _ready() -> void:
	var controller := _build_controller()
	if controller == null:
		get_tree().quit(_exit_code)
		return
	var warrior := _find_warrior(controller)
	var enemy := _first_enemy(controller)
	if warrior == null or enemy == null:
		_fail("WARRIOR_MECH: missing warrior or enemy")
		get_tree().quit(_exit_code)
		return

	_prepare_combat(controller, warrior, enemy)
	_test_resources_and_runtime_identity(warrior)
	_test_hidden_blade_again(controller, warrior, enemy)
	_test_battle_cry(controller, warrior, enemy)
	_test_wound_forged_bulwark(controller, warrior, enemy)
	_test_attack_defense_dance(controller, warrior, enemy)

	print("WARRIOR_MECH: completed")
	get_tree().quit(_exit_code)


func _test_resources_and_runtime_identity(warrior: BattleUnitState) -> void:
	var required := [
		"hidden_blade_again", "breaching_strike", "battle_cry", "armed_and_armored",
		"rehearsal", "wound_forged_bulwark", "bloodied_battle", "stand_immovable",
		"attack_defense_dance",
	]
	for resource_name in required:
		var card := load("res://resources/cards/%s.tres" % resource_name) as CardData
		if card == null:
			_fail("WARRIOR_MECH: failed to load %s" % resource_name)

	var relentless := load("res://resources/cards/relentless.tres") as CardData
	var relentless_effect := load("res://resources/cards/relentless_effect.tres") as RelentlessCardEffect
	if relentless == null or relentless.rarity != CardEnums.Rarity.EPIC:
		_fail("WARRIOR_MECH: relentless is not epic")
	if relentless_effect == null or relentless_effect.power_per_returned_card != 2:
		_fail("WARRIOR_MECH: relentless return bonus is not 2")

	var battle_strikes: Array[CardData] = []
	for zone in [warrior.draw_pile, warrior.hand, warrior.discard_pile]:
		for card in zone:
			if card != null and card.card_name == "战斗打击":
				battle_strikes.append(card)
	if battle_strikes.size() >= 2 and battle_strikes[0] == battle_strikes[1]:
		_fail("WARRIOR_MECH: runtime deck cards still share CardData identity")


func _test_hidden_blade_again(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/hidden_blade_again.tres") as CardData
	var filler_template := load("res://resources/cards/battle_strike.tres") as CardData
	if template == null or filler_template == null:
		_fail("WARRIOR_MECH: hidden blade resources missing")
		return

	_reset_card_zones(warrior)
	_reset_enemy(enemy)
	var normal := template.duplicate() as CardData
	warrior.hand.append(normal)
	warrior.current_ap = 10
	var before := enemy.get_current_health()
	if not controller.play_card(warrior, normal, [enemy]):
		_fail("WARRIOR_MECH: hidden blade normal play failed")
	elif enemy.get_current_health() >= before:
		_fail("WARRIOR_MECH: hidden blade normal dealt no damage")

	_reset_card_zones(warrior)
	_reset_enemy(enemy)
	var combo := template.duplicate() as CardData
	var combo_filler := filler_template.duplicate() as CardData
	warrior.hand.assign([combo_filler, combo])
	warrior.current_ap = 7
	var ap_before := warrior.current_ap
	if not controller.play_card(warrior, combo, [enemy], {}, CardEnums.CardPlayMode.COMBO):
		_fail("WARRIOR_MECH: hidden blade combo play failed")
	elif warrior.current_ap != ap_before:
		_fail("WARRIOR_MECH: hidden blade combo consumed AP")
	if warrior.discard_pile.find(combo_filler) < 0 or warrior.discard_pile.find(combo) < 0:
		_fail("WARRIOR_MECH: hidden blade combo did not discard cost and card")

	_reset_card_zones(warrior)
	_reset_enemy(enemy)
	var momentum := template.duplicate() as CardData
	var momentum_filler := filler_template.duplicate() as CardData
	warrior.discard_pile.assign([momentum_filler, momentum])
	warrior.current_ap = 0
	if not controller.play_card(warrior, momentum, [enemy], {}, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_MECH: hidden blade momentum play failed")
	if warrior.exiled_pile.find(momentum) < 0 or warrior.exiled_pile.find(momentum_filler) < 0:
		_fail("WARRIOR_MECH: hidden blade momentum did not banish both cards")


func _test_battle_cry(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var card := (load("res://resources/cards/battle_cry.tres") as CardData).duplicate() as CardData
	var filler := load("res://resources/cards/battle_strike.tres") as CardData
	if card == null or filler == null:
		_fail("WARRIOR_MECH: battle cry resources missing")
		return
	_reset_card_zones(warrior)
	enemy.statuses.clear()
	warrior.hand.append(card)
	warrior.draw_pile.assign([filler.duplicate() as CardData, filler.duplicate() as CardData])
	warrior.current_ap = 10
	var weapon_before := warrior.character_state.weapon_equipment
	if not controller.play_card(warrior, card, [enemy]):
		_fail("WARRIOR_MECH: battle cry play failed")
	if warrior.draw_pile.size() != 0 or warrior.discard_pile.size() < 3:
		_fail("WARRIOR_MECH: battle cry did not mill two cards")
	var stun := enemy.get_status("stun")
	if stun == null or stun.stacks != 3:
		_fail("WARRIOR_MECH: battle cry did not apply stun 3")
	if warrior.character_state.weapon_equipment == weapon_before:
		_fail("WARRIOR_MECH: battle cry did not switch weapon")


func _test_wound_forged_bulwark(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/wound_forged_bulwark.tres") as CardData
	if template == null:
		_fail("WARRIOR_MECH: bulwark resource missing")
		return
	_reset_card_zones(warrior)
	warrior.clear_armor({"controller": controller})
	warrior.set_current_health(warrior.get_max_health() - 7)
	var card := template.duplicate() as CardData
	warrior.hand.append(card)
	warrior.current_ap = 10
	if not controller.play_card(warrior, card, [warrior]):
		_fail("WARRIOR_MECH: bulwark normal play failed")
	if warrior.get_armor_stacks() != 7 or not warrior.has_status("clear_armor_next_turn"):
		_fail("WARRIOR_MECH: bulwark normal armor or expiry status incorrect")

	_reset_enemy(enemy)
	enemy.position = warrior.position + Vector2(80.0, 0.0)
	var before := enemy.get_current_health()
	if not controller.play_card(warrior, card, [], {}, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_MECH: bulwark momentum play failed")
	if warrior.get_armor_stacks() != 0:
		_fail("WARRIOR_MECH: bulwark momentum did not clear armor")
	if enemy.get_current_health() != before - 7:
		_fail("WARRIOR_MECH: bulwark momentum damage incorrect")


func _test_attack_defense_dance(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/attack_defense_dance.tres") as CardData
	if template == null:
		_fail("WARRIOR_MECH: dance resource missing")
		return
	_reset_card_zones(warrior)
	warrior.clear_armor({"controller": controller})
	_reset_enemy(enemy)
	enemy.position = warrior.position + Vector2(70.0, 0.0)
	var card := template.duplicate() as CardData
	warrior.hand.append(card)
	warrior.current_ap = 10
	var weapon_before := warrior.character_state.weapon_equipment
	var health_before := enemy.get_current_health()
	if not controller.play_card(warrior, card, [enemy]):
		_fail("WARRIOR_MECH: dance play failed")
	if warrior.character_state.weapon_equipment == weapon_before:
		_fail("WARRIOR_MECH: dance did not switch weapon")
	if health_before - enemy.get_current_health() <= 6:
		_fail("WARRIOR_MECH: dance did not perform its second strike")

	_reset_card_zones(warrior)
	warrior.clear_armor({"controller": controller})
	_reset_enemy(enemy)
	warrior.character_state.inventory.clear()
	var fallback := template.duplicate() as CardData
	warrior.hand.append(fallback)
	warrior.current_ap = 10
	var expected_armor := warrior.character_state.get_active_weapon_equipment().power
	if not controller.play_card(warrior, fallback, [enemy]):
		_fail("WARRIOR_MECH: dance fallback play failed")
	if warrior.get_armor_stacks() != expected_armor:
		_fail("WARRIOR_MECH: dance fallback armor incorrect")


func _build_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("WARRIOR_MECH: scenario missing")
		return null
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _prepare_combat(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	warrior.ensure_initialized(controller.config, controller.rng)
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	warrior.position = Vector2(200.0, 200.0)
	warrior.is_deployed = true
	enemy.position = warrior.position + Vector2(70.0, 0.0)
	warrior.turn_serial = 1


func _reset_card_zones(unit: BattleUnitState) -> void:
	unit.hand.clear()
	unit.discard_pile.clear()
	unit.exiled_pile.clear()
	unit.mana_zone.clear()
	unit.enchant_zone.clear()
	unit.curse_zone.clear()
	unit.card_runtime_states.clear()


func _reset_enemy(enemy: BattleUnitState) -> void:
	enemy.set_current_health(enemy.get_max_health())
	enemy.statuses.clear()


func _find_warrior(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			return unit
	return null


func _first_enemy(controller: BattleController) -> BattleUnitState:
	return controller.enemy_units[0] if not controller.enemy_units.is_empty() else null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
