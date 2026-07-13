extends Node

var _exit_code := 0


func _ready() -> void:
	var controller := _build_controller()
	var warrior := _find_warrior(controller)
	var enemy := controller.enemy_units[0] if controller != null and not controller.enemy_units.is_empty() else null
	if controller == null or warrior == null or enemy == null:
		_fail("WARRIOR_WEAPONS: missing controller or units")
		get_tree().quit(_exit_code)
		return

	_prepare(controller, warrior, enemy)
	_test_resources_and_pair_profile(warrior)
	_test_next_card_damage_bonus(warrior)
	_test_mountain_cleaver(controller, warrior)
	_test_ceremonial_pair(controller, warrior)
	_test_lion_weapon(controller, warrior, enemy)
	_test_iron_rock_pair(controller, warrior, enemy)
	_test_molten_blackstone(controller, warrior, enemy)
	_test_ember_iron_greataxe(controller, warrior, enemy)
	_test_clockwork_pair(controller, warrior, enemy)

	print("WARRIOR_WEAPONS: completed")
	get_tree().quit(_exit_code)


func _test_resources_and_pair_profile(warrior: BattleUnitState) -> void:
	var paths := [
		"mountain_cleaver", "ceremonial_sword_shield", "lion_greatsword",
		"iron_rock_pair", "molten_blackstone_pair", "ember_iron_greataxe",
		"clockwork_gear_pair",
	]
	for item_name in paths:
		if load("res://resources/items/%s.tres" % item_name) as EquipmentData == null:
			_fail("WARRIOR_WEAPONS: failed to load %s" % item_name)

	var iron := load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	_set_weapon(warrior, iron)
	var profile := warrior.build_strike_profile_object("weapon", {"controller": null})
	if not profile.add_offhand or profile.primary_base_damage != 3 or profile.offhand_base_damage != 3:
		_fail("WARRIOR_WEAPONS: paired strike profile is not 3 + 3")
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	if pool == null or pool.get_max_value() != 5:
		_fail("WARRIOR_WEAPONS: momentum maximum is not 5")


func _test_next_card_damage_bonus(warrior: BattleUnitState) -> void:
	warrior.pending_next_card_damage_bonus = 0
	warrior.active_card_damage_bonuses.clear()
	var card_a := CardData.new()
	var card_b := CardData.new()
	warrior.gain_next_card_damage_bonus(3)
	warrior.bind_next_card_damage_bonus(card_a)
	warrior.gain_next_card_damage_bonus(2)
	if warrior.get_next_card_damage_bonus({"source": card_a}) != 3:
		_fail("WARRIOR_WEAPONS: active card damage bonus incorrect")
	if warrior.get_next_card_damage_bonus({"source": card_b}) != 0:
		_fail("WARRIOR_WEAPONS: next-card bonus leaked to another card")
	warrior.finish_next_card_damage_bonus(card_a)
	if warrior.pending_next_card_damage_bonus != 2:
		_fail("WARRIOR_WEAPONS: bonus gained during a card did not remain pending")
	warrior.bind_next_card_damage_bonus(card_b)
	warrior.finish_next_card_damage_bonus(card_b)


func _test_mountain_cleaver(controller: BattleController, warrior: BattleUnitState) -> void:
	var mountain := load("res://resources/items/mountain_cleaver.tres") as EquipmentData
	var ceremonial := load("res://resources/items/ceremonial_sword_shield.tres") as EquipmentData
	_set_weapon(warrior, mountain)
	_set_inventory(warrior, ceremonial)
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 1
	warrior.notify_equipment_turn_start({"controller": controller})
	if pool.current_value != 0 or warrior.character_state.weapon_equipment != mountain:
		_fail("WARRIOR_WEAPONS: mountain cleaver did not pay momentum")
	warrior.notify_equipment_turn_start({"controller": controller})
	if warrior.character_state.weapon_equipment != ceremonial:
		_fail("WARRIOR_WEAPONS: mountain cleaver did not switch when unpaid")


func _test_ceremonial_pair(controller: BattleController, warrior: BattleUnitState) -> void:
	var ceremonial := load("res://resources/items/ceremonial_sword_shield.tres") as EquipmentData
	_set_weapon(warrior, ceremonial)
	warrior.statuses.clear()
	warrior.notify_equipment_switched_in(ceremonial, 0, {"controller": controller})
	if not warrior.has_status("block"):
		_fail("WARRIOR_WEAPONS: ceremonial shield did not grant block")
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 0
	warrior.draw_pile.assign([CardData.new()])
	warrior.draw_cards(1, controller.rng, {"controller": controller})
	if pool.current_value != 1:
		_fail("WARRIOR_WEAPONS: ceremonial sword did not gain momentum on draw")
	var action := _first_action(warrior, controller)
	if action.is_empty() or not _activate_action_direct(warrior, action, controller):
		_fail("WARRIOR_WEAPONS: ceremonial prepare failed")
	elif warrior.pending_next_card_damage_bonus != 1:
		_fail("WARRIOR_WEAPONS: ceremonial prepare bonus incorrect")
	var block := warrior.get_status("block")
	block.on_turn_start(warrior, {"controller": controller})
	if block.stacks <= 0:
		_fail("WARRIOR_WEAPONS: ceremonial shield did not preserve block")


func _test_lion_weapon(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var lion := load("res://resources/items/lion_greatsword.tres") as EquipmentData
	_set_weapon(warrior, lion)
	warrior.statuses.clear()
	warrior.notify_equipment_switched_in(lion, 0, {"controller": controller})
	var flip := _first_action(warrior, controller)
	if flip.is_empty() or not _activate_action_direct(warrior, flip, controller) or warrior.character_state.weapon_face != 1:
		_fail("WARRIOR_WEAPONS: lion weapon did not invert")
		return
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 1
	var prepare := _first_action(warrior, controller)
	if prepare.is_empty() or not _activate_action_direct(warrior, prepare, controller):
		_fail("WARRIOR_WEAPONS: lion roar prepare failed")
	_reset_enemy(enemy)
	warrior.clear_armor({"controller": controller})
	controller.perform_strike(warrior, enemy, CardData.new(), "lion diagnostic", "weapon")
	if warrior.get_armor_stacks() <= 0 or warrior.character_state.weapon_face != 0:
		_fail("WARRIOR_WEAPONS: lion roar strike did not grant armor and return upright")


func _test_iron_rock_pair(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var iron := load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	_set_weapon(warrior, iron)
	_reset_enemy(enemy)
	var before := enemy.get_current_health()
	warrior.notify_equipment_switched_in(iron, 0, {"controller": controller})
	if enemy.get_current_health() >= before:
		_fail("WARRIOR_WEAPONS: iron cutter switch damage missing")
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 0
	warrior.turn_serial += 1
	warrior.notify_equipment_turn_end({"controller": controller})
	if pool.current_value != 1:
		_fail("WARRIOR_WEAPONS: rock breaker no-strike momentum missing")


func _test_molten_blackstone(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var molten := load("res://resources/items/molten_blackstone_pair.tres") as EquipmentData
	_set_weapon(warrior, molten)
	warrior.statuses.clear()
	warrior.notify_equipment_switched_in(molten, 0, {"controller": controller})
	var runtime := warrior.get_equipment_runtime_state(molten)
	if runtime.get_counter("molten_permanent_damage_bonus") != 5 or warrior.get_armor_stacks() != 4:
		_fail("WARRIOR_WEAPONS: molten switch benefits incorrect")
	if warrior.get_damage_reduction({"controller": controller}) < 1:
		_fail("WARRIOR_WEAPONS: blackstone reduction missing")
	_reset_enemy(enemy)
	controller.perform_strike(warrior, enemy, CardData.new(), "molten diagnostic", "weapon")
	if runtime.get_counter("molten_permanent_damage_bonus") != 4:
		_fail("WARRIOR_WEAPONS: molten permanent bonus did not decay")
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 2
	var action := _first_action(warrior, controller)
	if action.is_empty() or not _activate_action_direct(warrior, action, controller) or not warrior.has_status("block"):
		_fail("WARRIOR_WEAPONS: blackstone prepare did not grant block")


func _test_ember_iron_greataxe(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var ember := load("res://resources/items/ember_iron_greataxe.tres") as EquipmentData
	var training := load("res://resources/items/training_sword.tres") as EquipmentData
	_set_weapon(warrior, ember)
	warrior.hand.assign([CardData.new()])
	warrior.discard_pile.clear()
	warrior.draw_pile.assign([CardData.new()])
	warrior.exiled_pile.assign([CardData.new()])
	warrior.discard_card(warrior.hand[0], {"controller": controller})
	warrior.move_draw_card_to_discard(warrior.draw_pile[0], {"controller": controller})
	warrior.move_exiled_card_to_discard(warrior.exiled_pile[0], {"controller": controller})
	var runtime := warrior.get_equipment_runtime_state(ember)
	if runtime.get_counter("embers") != 3:
		_fail("WARRIOR_WEAPONS: ember count did not include every discard source")
	_set_inventory(warrior, training)
	_reset_enemy(enemy)
	warrior.clear_armor({"controller": controller})
	var before := enemy.get_current_health()
	controller.switch_weapon_from_inventory(warrior)
	controller.resolve_effect_queue()
	if runtime.get_counter("embers") != 0 or enemy.get_current_health() >= before or warrior.get_armor_stacks() != 3:
		_fail("WARRIOR_WEAPONS: ember burst result incorrect")


func _test_clockwork_pair(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	var clockwork := load("res://resources/items/clockwork_gear_pair.tres") as EquipmentData
	var training := load("res://resources/items/training_sword.tres") as EquipmentData
	_set_weapon(warrior, clockwork)
	warrior.statuses.clear()
	warrior.notify_equipment_switched_in(clockwork, 0, {"controller": controller})
	var profile := warrior.build_strike_profile_object("weapon", {"controller": controller})
	if not profile.add_offhand or profile.primary_base_damage != 3 or profile.offhand_base_damage != 1:
		_fail("WARRIOR_WEAPONS: clockwork pair profile incorrect")
	var pool := warrior.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	pool.current_value = 0
	warrior.turn_serial += 1
	_reset_enemy(enemy)
	controller.perform_strike(warrior, enemy, CardData.new(), "clockwork diagnostic", "weapon")
	controller.perform_strike(warrior, enemy, CardData.new(), "clockwork diagnostic 2", "weapon")
	if pool.current_value != 1:
		_fail("WARRIOR_WEAPONS: clockwork strike momentum triggered more than once")
	pool.current_value = 2
	var base_bonus := warrior.get_strength()
	if warrior.get_damage_bonus({"controller": controller, "equipment": clockwork}) < base_bonus + 2:
		_fail("WARRIOR_WEAPONS: gear disc turn damage bonus missing")
	var action := _first_action(warrior, controller)
	if action.is_empty() or not _activate_action_direct(warrior, action, controller):
		_fail("WARRIOR_WEAPONS: clockwork prepare failed")
	else:
		var card := CardData.new()
		card.ap_cost = 2
		if warrior.get_card_ap_cost(card) != 1:
			_fail("WARRIOR_WEAPONS: clockwork AP discount incorrect")
	_set_inventory(warrior, training)
	var before_switch := pool.current_value
	controller.switch_weapon_from_inventory(warrior)
	if pool.current_value != mini(5, before_switch + 1):
		_fail("WARRIOR_WEAPONS: clockwork switch-out momentum missing")


func _activate_action_direct(owner: BattleUnitState, action: Dictionary, controller: BattleController) -> bool:
	var effect := action.get("effect") as EquipmentEffect
	var cost := int(action.get("momentum_cost", 0))
	if cost > 0 and not owner.consume_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, cost):
		return false
	return effect != null and effect.activate(owner, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {"controller": controller})


func _first_action(owner: BattleUnitState, controller: BattleController) -> Dictionary:
	var actions := owner.get_equipment_actions({"controller": controller, "unit": owner})
	return actions[0] as Dictionary if not actions.is_empty() else {}


func _set_weapon(owner: BattleUnitState, equipment: EquipmentData) -> void:
	owner.character_state.weapon_equipment = equipment
	owner.character_state.weapon_face = 0
	owner.equipment_runtime_states.clear()


func _set_inventory(owner: BattleUnitState, equipment: EquipmentData) -> void:
	owner.character_state.inventory.clear()
	var stack := InventoryStack.new()
	stack.item_data = equipment
	stack.count = 1
	owner.character_state.inventory.append(stack)


func _build_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		return null
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _find_warrior(controller: BattleController) -> BattleUnitState:
	if controller == null:
		return null
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			return unit
	return null


func _prepare(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	warrior.turn_serial = 1
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 4), controller.map_data)


func _reset_enemy(enemy: BattleUnitState) -> void:
	enemy.set_current_health(enemy.get_max_health())
	enemy.statuses.clear()


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
