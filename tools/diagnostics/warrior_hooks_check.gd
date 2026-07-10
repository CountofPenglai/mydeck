extends Node

const BREACH_STATUS_SCRIPT := preload("res://scripts/status/breach_status.gd")

var _exit_code: int = 0


func _ready() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("WARRIOR_HOOK: scenario missing")
		get_tree().quit(_exit_code)
		return

	var controller := BattleController.new()
	controller.setup(scenario)
	var warrior := _find_warrior(controller)
	var ally := _find_other_player(controller, warrior)
	var enemy := controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if warrior == null or ally == null or enemy == null:
		_fail("WARRIOR_HOOK: missing test units")
		get_tree().quit(_exit_code)
		return

	_prepare(controller, warrior, ally, enemy)
	_test_breach(controller, warrior, ally, enemy)
	_test_armed_and_armored(controller, warrior)
	_test_bloodied_battle(controller, warrior, enemy)
	_test_stand_immovable(controller, warrior, enemy)
	_test_rehearsal(controller, warrior, enemy)

	print("WARRIOR_HOOK: completed")
	get_tree().quit(_exit_code)


func _test_breach(controller: BattleController, warrior: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	var card := load("res://resources/cards/breaching_strike.tres") as CardData
	if card == null:
		_fail("WARRIOR_HOOK: breach card missing")
		return
	enemy.statuses.clear()
	_reset_enemy(enemy)
	card.effect.play({
		"controller": controller,
		"user": warrior,
		"card": card,
		"equipment_slot": "weapon",
	}, [enemy])
	controller.resolve_effect_queue()
	var breach_id := "breach_%d" % warrior.unit_id
	if not enemy.has_status(breach_id):
		_fail("WARRIOR_HOOK: breach status was not applied")
		return

	var actual := controller.apply_damage(ally, enemy, 4, "破绽诊断")
	if actual != 6:
		_fail("WARRIOR_HOOK: breach multiplier expected 6, got %d" % actual)
	if enemy.has_status(breach_id):
		_fail("WARRIOR_HOOK: breach was not consumed by positive friendly damage")

	var status := BREACH_STATUS_SCRIPT.new()
	status.status_id = breach_id
	status.applied_by = warrior
	status.expires_on_source_turn = warrior.turn_serial + 1
	enemy.add_status(status)
	warrior.turn_serial += 1
	enemy.remove_expired_statuses()
	if enemy.has_status(breach_id):
		_fail("WARRIOR_HOOK: breach did not expire at source turn start")


func _test_armed_and_armored(controller: BattleController, warrior: BattleUnitState) -> void:
	var card := (load("res://resources/cards/armed_and_armored.tres") as CardData).duplicate() as CardData
	if card == null:
		_fail("WARRIOR_HOOK: armed and armored card missing")
		return
	warrior.enchant_zone.clear()
	warrior.discard_pile.clear()
	warrior.card_runtime_states.clear()
	warrior.clear_armor({"controller": controller})
	warrior.add_card_to_enchant_zone(card, {"controller": controller})
	var first := controller.switch_weapon_from_inventory(warrior)
	if not bool(first.get("success", false)) or warrior.get_armor_stacks() != 3:
		_fail("WARRIOR_HOOK: first weapon switch did not grant 3 armor")
	controller.switch_weapon_from_inventory(warrior)
	if warrior.get_armor_stacks() != 3:
		_fail("WARRIOR_HOOK: enchant triggered twice in one turn")
	warrior.turn_serial += 1
	controller.switch_weapon_from_inventory(warrior)
	if warrior.get_armor_stacks() != 6:
		_fail("WARRIOR_HOOK: enchant did not refresh on next turn")

	var armor_before := warrior.get_armor_stacks()
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	if not controller.activate_enchant_card(warrior, card):
		_fail("WARRIOR_HOOK: enchant active ability failed")
	if warrior.enchant_zone.find(card) >= 0 or warrior.discard_pile.find(card) < 0:
		_fail("WARRIOR_HOOK: enchant active did not discard itself first")
	if warrior.get_armor_stacks() != armor_before:
		_fail("WARRIOR_HOOK: enchant active incorrectly granted final armor")


func _test_bloodied_battle(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var card := (load("res://resources/cards/bloodied_battle.tres") as CardData).duplicate() as CardData
	if card == null:
		_fail("WARRIOR_HOOK: bloodied battle card missing")
		return
	warrior.enchant_zone.clear()
	warrior.discard_pile.clear()
	warrior.card_runtime_states.clear()
	warrior.clear_armor({"controller": controller})
	warrior.set_current_health(warrior.get_max_health() - 12)
	warrior.add_card_to_enchant_zone(card, {"controller": controller})
	_reset_enemy(enemy)
	var before := warrior.get_current_health()
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_deal_twice"), [controller, warrior, enemy]))
	if warrior.get_current_health() != before + 3:
		_fail("WARRIOR_HOOK: bloodied battle did not trigger exactly once in a multi-hit action")

	for _i in range(3):
		controller.push_action_frame(BattleActionFrame.create(Callable(self, "_deal_twice"), [controller, warrior, enemy]))
	if warrior.enchant_zone.find(card) >= 0 or warrior.discard_pile.find(card) < 0:
		_fail("WARRIOR_HOOK: bloodied battle did not leave after four actions")


func _test_stand_immovable(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var card := (load("res://resources/cards/stand_immovable.tres") as CardData).duplicate() as CardData
	if card == null:
		_fail("WARRIOR_HOOK: stand immovable card missing")
		return
	warrior.hand.clear()
	warrior.enchant_zone.clear()
	warrior.discard_pile.clear()
	warrior.card_runtime_states.clear()
	warrior.clear_armor({"controller": controller})
	warrior.set_current_health(warrior.get_max_health())
	warrior.hand.append(card)
	card.play({"controller": controller, "user": warrior, "card": card}, [warrior])
	if warrior.get_armor_stacks() != 4 or warrior.enchant_zone.find(card) < 0:
		_fail("WARRIOR_HOOK: stand immovable did not enter enchant with 4 armor")
		return

	var health_before := warrior.get_current_health()
	var actual := controller.apply_damage(enemy, warrior, 4, "铁壁诊断")
	if actual != 0 or warrior.get_current_health() != health_before:
		_fail("WARRIOR_HOOK: stand immovable damage reached health")
	if warrior.get_armor_stacks() != 3:
		_fail("WARRIOR_HOOK: reduction was not applied before armor; expected 3 armor")

	warrior.clear_armor({"controller": controller, "reason": "diagnostic"})
	if warrior.enchant_zone.find(card) >= 0 or warrior.discard_pile.find(card) < 0:
		_fail("WARRIOR_HOOK: stand immovable did not leave when armor reached zero")


func _test_rehearsal(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var rehearsal := (load("res://resources/cards/rehearsal.tres") as CardData).duplicate() as CardData
	var selected := (load("res://resources/cards/battle_strike.tres") as CardData).duplicate() as CardData
	if rehearsal == null or selected == null:
		_fail("WARRIOR_HOOK: rehearsal resources missing")
		return
	warrior.hand.clear()
	warrior.discard_pile.assign([selected, rehearsal])
	warrior.exiled_pile.clear()
	warrior.card_runtime_states.clear()
	rehearsal.effect.play({
		"controller": controller,
		"user": warrior,
		"card": rehearsal,
		"play_mode": CardEnums.CardPlayMode.MOMENTUM,
		"ordered_discard_cards": [selected],
	}, [warrior])
	if warrior.hand.find(selected) < 0 or warrior.get_card_ap_cost(selected) != 0:
		_fail("WARRIOR_HOOK: rehearsal did not recover and discount selected card")

	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	warrior.current_ap = 10
	_reset_enemy(enemy)
	if not controller.play_card(warrior, selected, [enemy]):
		_fail("WARRIOR_HOOK: rehearsed card could not be played")
	if warrior.exiled_pile.find(selected) < 0:
		_fail("WARRIOR_HOOK: rehearsed card did not exile after play")

	var unplayed := (load("res://resources/cards/battle_strike.tres") as CardData).duplicate() as CardData
	warrior.discard_pile.append(unplayed)
	warrior.move_discard_card_to_hand(unplayed)
	warrior.mark_temporary_card(unplayed, -2, true, true)
	warrior.exile_expiring_temporary_cards(controller)
	if warrior.exiled_pile.find(unplayed) < 0:
		_fail("WARRIOR_HOOK: unplayed rehearsed card did not exile at turn end")


func _deal_twice(controller: BattleController, source: BattleUnitState, target: BattleUnitState) -> void:
	controller.apply_damage(source, target, 1, "浴血诊断一")
	controller.apply_damage(source, target, 1, "浴血诊断二")


func _prepare(controller: BattleController, warrior: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	warrior.turn_serial = 1
	warrior.position = Vector2(200.0, 200.0)
	ally.position = warrior.position + Vector2(30.0, 0.0)
	enemy.position = warrior.position + Vector2(70.0, 0.0)


func _reset_enemy(enemy: BattleUnitState) -> void:
	enemy.set_current_health(enemy.get_max_health())
	enemy.statuses.clear()


func _find_warrior(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			return unit
	return null


func _find_other_player(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit != excluded:
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
