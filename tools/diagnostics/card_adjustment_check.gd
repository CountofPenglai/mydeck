extends Node

const CHARGE_TARGET_DISTANCE := 7

var _exit_code: int = 0


func _ready() -> void:
	var controller := _build_controller()
	if controller == null:
		get_tree().quit(_exit_code)
		return
	var warrior := _find_player(controller, CardEnums.CardClass.WARRIOR)
	var ranger := _find_player(controller, CardEnums.CardClass.RANGER)
	var enemy := controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if warrior == null or ranger == null or enemy == null:
		_fail("CARD_ADJUST: missing warrior, ranger, or enemy")
		get_tree().quit(_exit_code)
		return

	_prepare_unit(controller, warrior, Vector2i(2, 4))
	_prepare_unit(controller, ranger, Vector2i(2, 3))
	_prepare_enemy(controller, enemy, Vector2i(3, 4))
	_test_slam(controller, warrior, enemy)
	_test_charge(controller, warrior, enemy)
	_test_defensive_stance(controller, warrior, enemy)
	_test_perilous_assault(ranger)
	_test_tri_phase_dissection()

	print("CARD_ADJUST: completed")
	get_tree().quit(_exit_code)


func _test_slam(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.current_unit = warrior
	var card := _card("battle_slam")
	if card == null:
		return
	if card.ap_cost != 2 or not card.description.contains("双手"):
		_fail("CARD_ADJUST: slam resource text or AP is stale")

	var weapon := _make_weapon("诊断双手武器", 3, 1, EquipmentData.EquipCategory.TWO_HAND)
	warrior.character_state.weapon_equipment = weapon
	warrior.character_state.inventory.clear()
	_reset_zones(warrior)
	_reset_enemy(enemy, Vector2i(3, 4), controller)
	var runtime_card := card.duplicate(true) as CardData
	warrior.hand.append(runtime_card)
	warrior.current_ap = 10
	var expected := warrior.build_strike_profile_object("weapon").primary_base_damage \
		+ warrior.build_strike_profile_object("weapon").primary_damage_bonus + 2
	var before := enemy.get_current_health()
	if not controller.play_card(warrior, runtime_card, [enemy], {"equipment_slot": "weapon"}):
		_fail("CARD_ADJUST: slam play failed")
	elif before - enemy.get_current_health() != expected:
		_fail("CARD_ADJUST: two-handed slam did not gain +2 damage")


func _test_charge(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.current_unit = warrior
	var card := _card("battle_charge")
	if card == null:
		return
	if card.target_type != CardEnums.TargetType.SINGLE or card.ap_cost != 2:
		_fail("CARD_ADJUST: charge is not a 2 AP unit-target card")
		return

	warrior.character_state.weapon_equipment = _make_weapon(
		"诊断冲锋武器", 3, 1, EquipmentData.EquipCategory.TWO_HAND
	)
	warrior.character_state.agility_bonus = 5
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	var target_cell := _find_charge_target_cell(controller, warrior)
	if target_cell == BattleHexGrid.INVALID_CELL:
		_fail("CARD_ADJUST: no valid long-distance charge lane")
		return
	_reset_enemy(enemy, target_cell, controller)
	_reset_zones(warrior)
	var runtime_card := card.duplicate(true) as CardData
	warrior.hand.append(runtime_card)
	warrior.current_ap = 10
	var start_cell := warrior.cell
	var expected := warrior.build_strike_profile_object("weapon").primary_base_damage \
		+ warrior.build_strike_profile_object("weapon").primary_damage_bonus + 3
	var before := enemy.get_current_health()
	if not controller.play_card(warrior, runtime_card, [enemy], {"equipment_slot": "weapon"}):
		_fail("CARD_ADJUST: charge play failed")
		return
	var moved := BattleHexGrid.distance(start_cell, warrior.cell)
	if BattleHexGrid.distance(warrior.cell, enemy.cell) != 1:
		_fail("CARD_ADJUST: charge did not stop adjacent to its target")
	if moved <= 5:
		_fail("CARD_ADJUST: charge diagnostic did not exercise long-distance movement")
	if before - enemy.get_current_health() != expected:
		_fail("CARD_ADJUST: long-distance charge did not gain +3 damage")


func _test_defensive_stance(controller: BattleController, warrior: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.current_unit = warrior
	var card := _card("defensive_stance")
	if card == null:
		return
	if card.ap_cost != 1 or not card.has_momentum:
		_fail("CARD_ADJUST: defensive stance AP or momentum setup is stale")
		return
	if not warrior.has_method("record_block_lost"):
		_fail("CARD_ADJUST: warrior cannot record a lost block round")
		return

	var first := _make_weapon("诊断武器甲", 2, 1, EquipmentData.EquipCategory.ONE_HAND)
	var second := _make_weapon("诊断武器乙", 4, 2, EquipmentData.EquipCategory.TWO_HAND)
	warrior.character_state.weapon_equipment = first
	warrior.character_state.inventory.clear()
	warrior.character_state.reserve_weapon_equipment = second
	warrior.character_state.reserve_weapon_face = 0
	var sentinel := InventoryStack.new()
	sentinel.item_data = load("res://resources/items/healing_potion.tres") as ItemData
	sentinel.count = 2
	sentinel.stack_id = "defensive_stance_backpack_sentinel"
	warrior.character_state.inventory.append(sentinel)
	var backpack_before := _inventory_bytes(warrior.character_state)
	_reset_zones(warrior)
	var normal := card.duplicate(true) as CardData
	warrior.hand.append(normal)
	warrior.current_ap = 10
	var choice_context := {
		"controller": controller,
		"user": warrior,
		"card": normal,
		"play_mode": CardEnums.CardPlayMode.NORMAL,
	}
	if normal.requires_inventory_weapon_choice(choice_context) \
			or not normal.get_inventory_weapon_choices(choice_context).is_empty():
		_fail("CARD_ADJUST: defensive stance still requests an inventory weapon choice")
	var switch_events := {
		"started": 0,
		"switched_out": 0,
		"switched_in": 0,
		"state_changed": 0,
	}
	controller.equipment_switch_started.connect(
		func(_context: Dictionary) -> void: switch_events["started"] += 1,
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_out.connect(
		func(_context: Dictionary) -> void: switch_events["switched_out"] += 1,
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_in.connect(
		func(_context: Dictionary) -> void: switch_events["switched_in"] += 1,
		CONNECT_ONE_SHOT
	)
	controller.state_changed.connect(
		func() -> void: switch_events["state_changed"] += 1,
		CONNECT_ONE_SHOT
	)
	if not controller.play_card(warrior, normal, [warrior]):
		_fail("CARD_ADJUST: defensive stance normal play failed")
	if warrior.character_state.weapon_equipment != second:
		_fail("CARD_ADJUST: defensive stance ignored the selected weapon")
	if _inventory_bytes(warrior.character_state) != backpack_before:
		_fail("CARD_ADJUST: defensive stance mutated the backpack")
	if switch_events != {
		"started": 1,
		"switched_out": 1,
		"switched_in": 1,
		"state_changed": 1,
	}:
		_fail("CARD_ADJUST: defensive stance did not pass once through the unified switch pipeline: %s" % switch_events)
	if not warrior.has_status("block"):
		_fail("CARD_ADJUST: defensive stance did not grant block")

	controller.battle_round = 2
	warrior.call("record_block_lost", 1)
	warrior.call("record_block_lost", 2)
	if not warrior.lost_block_in_previous_round(2):
		_fail("CARD_ADJUST: current-round block loss erased the previous-round record")
	_reset_zones(warrior)
	var momentum := card.duplicate(true) as CardData
	warrior.discard_pile.append(momentum)
	warrior.current_ap = 0
	_reset_enemy(enemy, Vector2i(3, 4), controller)
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	var before := enemy.get_current_health()
	if not controller.play_card(warrior, momentum, [warrior], {}, CardEnums.CardPlayMode.MOMENTUM):
		_fail("CARD_ADJUST: free defensive stance momentum play failed")
	elif enemy.get_current_health() >= before:
		_fail("CARD_ADJUST: defensive stance momentum did not strike the nearest enemy")
	if warrior.current_ap != 0:
		_fail("CARD_ADJUST: previous-round block loss did not waive momentum AP")


func _test_perilous_assault(ranger: BattleUnitState) -> void:
	var card := _card("ranger_perilous_assault")
	if card == null:
		return
	if card.ap_cost != 2 or not card.description.contains("支付 1 AP 或弃置 1 张牌"):
		_fail("CARD_ADJUST: perilous assault text or AP is stale")
	var effect := card.effect
	var filler := _card("ranger_shadow_passage")
	if effect == null or filler == null:
		_fail("CARD_ADJUST: perilous assault resources missing")
		return
	var context := {
		"user": ranger,
		"card": card,
		"play_mode": CardEnums.CardPlayMode.COMBO,
	}
	ranger.hand.assign([card, filler])
	ranger.current_ap = 1
	if not card.requires_ordered_discard_choice(context):
		_fail("CARD_ADJUST: perilous assault does not request its alternative cost choice")
	if card.get_ordered_discard_choice_min_count(context) != 0 \
		or card.get_ordered_discard_choice_max_count(context) != 1:
		_fail("CARD_ADJUST: perilous assault AP/discard choice bounds are incorrect")
	if card.combo_conditions.is_empty():
		_fail("CARD_ADJUST: perilous assault alternative condition is missing")
		return
	var condition := card.combo_conditions[0] as CardPlayCondition
	if condition == null:
		_fail("CARD_ADJUST: perilous assault combo condition has the wrong type")
		return
	var ap_context := context.duplicate()
	ap_context["ordered_discard_cards"] = []
	if not condition.pay(ap_context) or ranger.current_ap != 0:
		_fail("CARD_ADJUST: perilous assault did not pay its AP option")

	ranger.hand.assign([card, filler])
	ranger.discard_pile.clear()
	ranger.current_ap = 0
	var discard_context := context.duplicate()
	discard_context["ordered_discard_cards"] = [filler]
	if not condition.pay(discard_context) or not ranger.discard_pile.has(filler):
		_fail("CARD_ADJUST: perilous assault did not pay its discard option")


func _test_tri_phase_dissection() -> void:
	var card := _card("ranger_tri_phase_dissection")
	if card == null:
		return
	if card.ap_cost != 2:
		_fail("CARD_ADJUST: tri-phase dissection AP is not 2")
	if card.combo_conditions.is_empty():
		_fail("CARD_ADJUST: tri-phase dissection combo condition is missing")
		return
	var condition := card.combo_conditions[0] as RangerElementsCollectedCondition
	if condition == null or condition.required_count != 2:
		_fail("CARD_ADJUST: tri-phase dissection combo threshold is not 2")


func _find_charge_target_cell(controller: BattleController, warrior: BattleUnitState) -> Vector2i:
	var max_range := controller.get_ap_movement_distance(warrior, 2) + 3
	for cell: Vector2i in controller.map_data.get_all_cells():
		if BattleHexGrid.distance(warrior.cell, cell) != CHARGE_TARGET_DISTANCE \
				or CHARGE_TARGET_DISTANCE > max_range:
			continue
		if not controller.targeting.has_line_of_sight(warrior.cell, cell):
			continue
		var line := controller.map_data.get_line(warrior.cell, cell)
		if line.size() >= 2 and controller.targeting.is_unit_cell_clear(warrior, line[line.size() - 2], false):
			return cell
	return BattleHexGrid.INVALID_CELL


func _make_weapon(name: String, damage: int, attack_range: int, category: int) -> EquipmentData:
	var weapon := EquipmentData.new()
	weapon.item_name = name
	weapon.base_damage = damage
	weapon.attack_range = attack_range
	weapon.damage_type = CardEnums.DamageType.STRENGTH
	weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	weapon.equip_category = category
	return weapon


func _inventory_bytes(state: CharacterState) -> PackedByteArray:
	var payload: Array[Dictionary] = []
	for stack in state.inventory:
		payload.append({
			"stack_object_id": stack.get_instance_id() if stack != null else 0,
			"item_object_id": stack.item_data.get_instance_id() if stack != null and stack.item_data != null else 0,
			"item_path": stack.item_data.resource_path if stack != null and stack.item_data != null else "",
			"count": stack.count if stack != null else 0,
			"stack_id": stack.stack_id if stack != null else "",
		})
	return var_to_bytes(payload)


func _card(resource_name: String) -> CardData:
	var card := load("res://resources/cards/%s.tres" % resource_name) as CardData
	if card == null:
		_fail("CARD_ADJUST: failed to load %s" % resource_name)
	return card


func _build_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("CARD_ADJUST: scenario missing")
		return null
	var controller := BattleController.new()
	controller.setup(scenario)
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.battle_round = 1
	return controller


func _prepare_unit(controller: BattleController, unit: BattleUnitState, cell: Vector2i) -> void:
	unit.ensure_initialized(controller.config, controller.rng)
	unit.set_hex_cell(cell, controller.map_data)
	unit.is_deployed = true
	unit.turn_serial = 1
	controller.current_unit = unit


func _prepare_enemy(controller: BattleController, enemy: BattleUnitState, cell: Vector2i) -> void:
	enemy.ensure_initialized(controller.config, controller.rng)
	enemy.set_hex_cell(cell, controller.map_data)
	enemy.is_deployed = true


func _reset_zones(unit: BattleUnitState) -> void:
	unit.hand.clear()
	unit.draw_pile.clear()
	unit.discard_pile.clear()
	unit.exiled_pile.clear()
	unit.mana_zone.clear()
	unit.enchant_zone.clear()
	unit.card_runtime_states.clear()
	unit.statuses.clear()


func _reset_enemy(enemy: BattleUnitState, cell: Vector2i, controller: BattleController) -> void:
	enemy.set_current_health(enemy.get_max_health())
	enemy.statuses.clear()
	enemy.set_hex_cell(cell, controller.map_data)
	enemy.is_deployed = true


func _find_player(controller: BattleController, card_class: int) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == card_class:
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
