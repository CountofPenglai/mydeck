extends Node

var _exit_code := 0


func _ready() -> void:
	_test_templates_are_inactive()
	_test_mage_resources_and_elements()
	_test_mage_infusion_state()
	_test_warlock_orientation_and_corruption()
	_test_warlock_payment_and_life_rules()
	print("MAGE_WARLOCK: completed")
	get_tree().quit(_exit_code)


func _test_templates_are_inactive() -> void:
	var mage := load("res://resources/characters/battle_mage_state.tres") as CharacterState
	var warlock := load("res://resources/characters/battle_warlock_state.tres") as CharacterState
	if mage == null or mage.character_data == null or mage.character_data.character_class != CardEnums.CardClass.MAGE:
		_fail("MAGE_WARLOCK: mage template is invalid")
	if warlock == null or warlock.character_data == null or warlock.character_data.character_class != CardEnums.CardClass.WARLOCK:
		_fail("MAGE_WARLOCK: warlock template is invalid")
	if not CharacterClassDefaults.get_resource_pools(CardEnums.CardClass.MAGE).is_empty() \
			or not CharacterClassDefaults.get_resource_pools(CardEnums.CardClass.WARLOCK).is_empty():
		_fail("MAGE_WARLOCK: legacy capped resource pools are still active")
	for path in AdventureSessionService.HERO_PATHS:
		if "mage" in path or "warlock" in path:
			_fail("MAGE_WARLOCK: unfinished class was registered as selectable")


func _test_mage_resources_and_elements() -> void:
	var state := (load("res://resources/characters/battle_mage_state.tres") as CharacterState).duplicate(true) as CharacterState
	var unit := BattleUnitState.new()
	unit.setup_player(101, state, 24.0)
	var card := CardData.new()
	card.card_name = "诊断双元素牌"
	card.element_tags = CardEnums.ElementTag.FIRE | CardEnums.ElementTag.WATER
	unit.hand.append(card)
	unit.get_card_runtime_state(card)["adventure_element_infusion"] = BattleSurfaceState.Element.AIR
	var opening := unit.initialize_mage_opening_hand()
	if opening.size() != 3 or unit.mage_state.get_mana(BattleSurfaceState.Element.FIRE) != 1 \
			or unit.mage_state.get_mana(BattleSurfaceState.Element.WATER) != 1 \
			or unit.mage_state.get_mana(BattleSurfaceState.Element.AIR) != 1:
		_fail("MAGE_WARLOCK: opening hand element projection failed")
	unit.mage_state.gain_mana(BattleSurfaceState.Element.FIRE, 100)
	if unit.mage_state.get_mana(BattleSurfaceState.Element.FIRE) != 101:
		_fail("MAGE_WARLOCK: mage mana was unexpectedly capped")

	var controller := BattleController.new()
	controller.setup(null)
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = unit
	controller.units.append(unit)
	controller.player_units.append(unit)
	unit.battle_controller = controller
	if not controller.submit_mage_discard_conversion(
		unit,
		[card],
		[BattleSurfaceState.Element.NONE]
	):
		_fail("MAGE_WARLOCK: discard conversion could not be submitted")
	elif not unit.hand.is_empty() or not unit.discard_pile.has(card) \
			or unit.mage_state.get_mana(BattleSurfaceState.Element.FIRE) != 102:
		_fail("MAGE_WARLOCK: discard conversion did not use the common discard path")
	unit.cell = Vector2i(0, 0)
	controller.active_turn_serial = 2
	var primordial_card := CardData.new()
	primordial_card.card_name = "诊断初态调用"
	primordial_card.ap_cost = 3
	unit.draw_pile.append(primordial_card)
	for element in BattleSurfaceState.BASE_ELEMENTS:
		controller.mage_infusion_state.place_stone(unit.faction, unit.cell, element, 1)
	if not controller.play_mage_primordial_card(unit, primordial_card, []) \
			or not unit.discard_pile.has(primordial_card) or unit.current_ap != 0 \
			or controller.mage_infusion_state.has_primordial(unit.faction, unit.cell):
		_fail("MAGE_WARLOCK: primordial card play did not use the normal card pipeline")


func _test_mage_infusion_state() -> void:
	var state := MageInfusionState.new()
	var cell := Vector2i(3, 2)
	var elements := BattleSurfaceState.BASE_ELEMENTS
	for element in elements:
		if not state.place_stone(BattleUnitState.Faction.PLAYER, cell, element, 7):
			_fail("MAGE_WARLOCK: a unique magic stone was not placed")
	if state.place_stone(BattleUnitState.Faction.PLAYER, cell, elements[0], 7):
		_fail("MAGE_WARLOCK: duplicate magic stone was stored")
	if not state.has_primordial(BattleUnitState.Faction.PLAYER, cell) \
			or state.is_primordial_available(BattleUnitState.Faction.PLAYER, cell, 7) \
			or not state.is_primordial_available(BattleUnitState.Faction.PLAYER, cell, 8):
		_fail("MAGE_WARLOCK: primordial formation lock is invalid")
	if state.has_primordial(BattleUnitState.Faction.ENEMY, cell):
		_fail("MAGE_WARLOCK: magic stones leaked between factions")
	if not state.consume_primordial(BattleUnitState.Faction.PLAYER, cell) \
			or state.has_primordial(BattleUnitState.Faction.PLAYER, cell):
		_fail("MAGE_WARLOCK: primordial consumption failed")


func _test_warlock_orientation_and_corruption() -> void:
	var state := (load("res://resources/characters/battle_warlock_state.tres") as CharacterState).duplicate(true) as CharacterState
	var curse := state.acquire_curse(load("res://resources/curses/blood.tres") as CurseDefinition)
	curse.transform_to_report()
	var unit := BattleUnitState.new()
	unit.setup_player(102, state, 24.0)
	unit.add_curse_to_zone(curse)
	if not unit.set_warlock_curse_face_down(curse, true) or unit.warlock_state.get_mana() != 1 \
			or unit.is_curse_effect_active(curse):
		_fail("MAGE_WARLOCK: curse face-down transition failed")
	unit.add_warlock_curse_counter(curse, "diagnostic", 2)
	if not unit.set_warlock_curse_face_down(curse, false) \
			or not unit.warlock_state.get_curse_counters(curse).is_empty() \
			or not unit.is_curse_effect_active(curse):
		_fail("MAGE_WARLOCK: face-up transition did not clear card counters")

	var stun := StunStatus.new()
	stun.stacks = 2
	unit.add_status(stun)
	unit.curse_wave = 1
	unit.set_warlock_curse_face_down(curse, true)
	unit.add_warlock_curse_counter(curse, "diagnostic", 1)
	unit.corrupt_existing_indicators(1)
	if unit.get_status("stun").stacks != 3 or unit.curse_wave != 2 \
			or int(unit.warlock_state.get_curse_counters(curse).get("diagnostic", 0)) != 2:
		_fail("MAGE_WARLOCK: corruption did not increase existing indicators")


func _test_warlock_payment_and_life_rules() -> void:
	var state := (load("res://resources/characters/battle_warlock_state.tres") as CharacterState).duplicate(true) as CharacterState
	var unit := BattleUnitState.new()
	unit.setup_player(103, state, 24.0)
	var controller := BattleController.new()
	controller.setup(null)
	unit.battle_controller = controller
	controller.units.append(unit)
	controller.player_units.append(unit)
	for index in range(3):
		var card := CardData.new()
		card.card_name = "诊断抽牌%d" % index
		unit.draw_pile.append(card)
	unit.warlock_state.gain_mana(2)
	unit.curse_wave = 3
	if not unit.pay_warlock_mana(4, 2, {"controller": controller, "reason": "diagnostic_payment"}) \
			or unit.warlock_state.get_mana() != 0 or unit.curse_wave != 1 or unit.hand.size() != 2:
		_fail("MAGE_WARLOCK: mixed mana payment or curse-wave draw failed")

	unit.set_current_health(unit.get_max_health() - 5)
	var before_heal := unit.get_current_health()
	if controller.heal_unit(unit, unit, 3, "诊断治疗") != 0 \
			or unit.get_current_health() != before_heal - 3:
		_fail("MAGE_WARLOCK: healing was not replaced with life loss")

	unit.set_current_health(unit.get_max_health())
	var previous_max := unit.get_max_health()
	var result := controller.gain_life(unit, unit, 4, "诊断获得生命")
	if int(result.get("max_health_lost", 0)) != 4 or unit.get_max_health() != previous_max - 4:
		_fail("MAGE_WARLOCK: life gain overflow did not reduce adventure max health")


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
