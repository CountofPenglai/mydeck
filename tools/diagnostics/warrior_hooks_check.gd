extends Node

const BREACH_STATUS_SCRIPT := preload("res://scripts/status/breach_status.gd")
const DIAGNOSTIC_DISCARD_STATUS_SCRIPT := preload("res://tools/diagnostics/diagnostic_discard_status.gd")


class DiagnosticSwitchEquipmentEffect:
	extends EquipmentEffect

	var events: Array[String] = []
	var record_before_out: bool = false
	var record_switched_out: bool = false
	var record_switched_in: bool = false

	func on_before_switch_out(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> void:
		if record_before_out:
			events.append("before_out")

	func on_switched_out(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> void:
		if record_switched_out:
			events.append("switched_out")

	func on_switched_in(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> void:
		if record_switched_in:
			events.append("switched_in")


class DiagnosticSwitchZoneEffect:
	extends CardEffect

	var events: Array[String] = []

	func on_zone_owner_equipment_switched(
		_owner: BattleUnitState,
		_zone_card: CardData,
		_switch_result: Dictionary,
		_context: Dictionary = {}
	) -> void:
		events.append("zone_hook")


class PreparedSwitchPaymentCondition:
	extends CardPlayCondition

	func can_pay(context: Dictionary = {}) -> bool:
		var user := _get_user(context)
		return user != null \
			and user.character_state != null \
			and user.character_state.reserve_weapon_equipment != null

	func pay(context: Dictionary = {}) -> bool:
		var user := _get_user(context)
		if user == null or user.character_state == null:
			return false
		var result := CharacterEquipmentModel.swap_active_and_reserve_weapons(user.character_state)
		return bool(result.get("success", false))


var _exit_code: int = 0
var _outer_limit_count: int = 0
var _nested_limit_count: int = 0


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
	_test_prepared_switch_pipeline(controller, warrior)
	_test_empty_reserve_switch_is_atomic(controller, warrior)
	_test_bloodied_battle(controller, warrior, enemy)
	_test_stand_immovable(controller, warrior, enemy)
	_test_rehearsal(controller, warrior, enemy)
	_test_playability_guards(controller, warrior)
	_test_payment_rollback(controller, warrior)
	_test_full_inventory_weapon_switch(controller)
	_test_nested_action_limit(controller)

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

	var status: BreachStatus = BREACH_STATUS_SCRIPT.new()
	status.status_id = breach_id
	status.applied_by = warrior
	status.expires_on_source_turn = warrior.turn_serial + 1
	enemy.add_status(status)
	enemy.gain_armor(20, {"controller": controller})
	actual = controller.apply_damage(ally, enemy, 4, "破绽护甲诊断")
	if actual != 0:
		_fail("WARRIOR_HOOK: armor did not absorb the breach-amplified segment")
	if enemy.has_status(breach_id):
		_fail("WARRIOR_HOOK: fully absorbed positive damage did not consume breach")
	enemy.clear_armor({"controller": controller})

	status = BREACH_STATUS_SCRIPT.new()
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
	_set_test_weapon_pair(warrior)
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


func _test_prepared_switch_pipeline(controller: BattleController, warrior: BattleUnitState) -> void:
	var events: Array[String] = []
	var old_weapon := EquipmentData.new()
	old_weapon.item_name = "diagnostic active weapon"
	old_weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	var old_effect := DiagnosticSwitchEquipmentEffect.new()
	old_effect.events = events
	old_effect.record_before_out = true
	old_effect.record_switched_out = true
	old_weapon.trigger_effects.assign([old_effect])
	var new_weapon := EquipmentData.new()
	new_weapon.item_name = "diagnostic reserve weapon"
	new_weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	var new_effect := DiagnosticSwitchEquipmentEffect.new()
	new_effect.events = events
	new_effect.record_switched_in = true
	new_weapon.trigger_effects.assign([new_effect])

	warrior.enchant_zone.clear()
	var zone_card := CardData.new()
	zone_card.card_name = "diagnostic switch observer"
	var zone_effect := DiagnosticSwitchZoneEffect.new()
	zone_effect.events = events
	zone_card.effect = zone_effect
	warrior.enchant_zone.append(zone_card)
	warrior.equipment_runtime_states.clear()
	warrior.character_state.weapon_equipment = old_weapon
	warrior.character_state.weapon_face = 1
	warrior.character_state.reserve_weapon_equipment = new_weapon
	warrior.character_state.reserve_weapon_face = 0
	warrior.character_state.equipment_instance_ids = {
		CharacterEquipmentModel.SLOT_WEAPON: "hook_active_id",
		CharacterEquipmentModel.SLOT_RESERVE_WEAPON: "hook_reserve_id",
	}
	warrior.character_state.inventory.clear()
	var sentinel := InventoryStack.new()
	sentinel.item_data = load("res://resources/items/healing_potion.tres") as ItemData
	sentinel.count = 2
	sentinel.stack_id = "hook_backpack_sentinel"
	warrior.character_state.inventory.append(sentinel)
	var backpack_before := _inventory_bytes(warrior.character_state)

	controller.equipment_switch_started.connect(
		func(_context: Dictionary) -> void: events.append("started"),
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_out.connect(
		func(_context: Dictionary) -> void: events.append("switched_out_signal"),
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_in.connect(
		func(_context: Dictionary) -> void: events.append("switched_in_signal"),
		CONNECT_ONE_SHOT
	)
	controller.state_changed.connect(
		func() -> void: events.append("state_changed"),
		CONNECT_ONE_SHOT
	)
	var result := controller.switch_weapon_from_inventory(warrior)
	var expected_order: Array[String] = [
		"started",
		"before_out",
		"switched_out",
		"switched_in",
		"switched_out_signal",
		"switched_in_signal",
		"zone_hook",
		"state_changed",
	]
	if not bool(result.get("success", false)) \
			or result.get("old_equipment") != old_weapon \
			or int(result.get("old_face", -1)) != 1 \
			or str(result.get("old_instance_id", "")) != "hook_active_id" \
			or result.get("new_equipment") != new_weapon \
			or int(result.get("new_face", -1)) != 0 \
			or str(result.get("new_instance_id", "")) != "hook_reserve_id" \
			or warrior.character_state.weapon_equipment != new_weapon \
			or warrior.character_state.reserve_weapon_equipment != old_weapon \
			or _inventory_bytes(warrior.character_state) != backpack_before:
		_fail("WARRIOR_HOOK: prepared switch result or atomic slot/backpack state is incorrect")
	if events != expected_order:
		_fail("WARRIOR_HOOK: prepared switch order expected %s, got %s" % [expected_order, events])


func _test_empty_reserve_switch_is_atomic(controller: BattleController, warrior: BattleUnitState) -> void:
	var events: Array[String] = []
	var active := EquipmentData.new()
	active.item_name = "empty reserve active"
	active.equip_slot = EquipmentData.EquipSlot.WEAPON
	var active_effect := DiagnosticSwitchEquipmentEffect.new()
	active_effect.events = events
	active_effect.record_before_out = true
	active_effect.record_switched_out = true
	active.trigger_effects.assign([active_effect])
	warrior.enchant_zone.clear()
	warrior.equipment_runtime_states.clear()
	warrior.character_state.weapon_equipment = active
	warrior.character_state.weapon_face = 1
	warrior.character_state.reserve_weapon_equipment = null
	warrior.character_state.reserve_weapon_face = 1
	warrior.character_state.equipment_instance_ids = {
		CharacterEquipmentModel.SLOT_WEAPON: "empty_active_id",
		"armor": "empty_armor_id",
		"custom": {"all": [1, 2]},
	}
	warrior.character_state.inventory.clear()
	var inventory_weapon := InventoryStack.new()
	inventory_weapon.item_data = load("res://resources/items/heavy_greatsword.tres") as EquipmentData
	inventory_weapon.count = 1
	inventory_weapon.stack_id = "must_not_be_read"
	warrior.character_state.inventory.append(inventory_weapon)
	var backpack_before := _inventory_bytes(warrior.character_state)
	var ids_before := warrior.character_state.equipment_instance_ids.duplicate(true)

	controller.equipment_switch_started.connect(
		func(_context: Dictionary) -> void: events.append("started"),
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_out.connect(
		func(_context: Dictionary) -> void: events.append("switched_out_signal"),
		CONNECT_ONE_SHOT
	)
	controller.equipment_switched_in.connect(
		func(_context: Dictionary) -> void: events.append("switched_in_signal"),
		CONNECT_ONE_SHOT
	)
	controller.state_changed.connect(
		func() -> void: events.append("state_changed"),
		CONNECT_ONE_SHOT
	)
	var result := controller.switch_weapon_from_inventory(warrior)
	if bool(result.get("success", false)) \
			or controller.can_switch_weapon_from_inventory(warrior) \
			or warrior.character_state.weapon_equipment != active \
			or warrior.character_state.weapon_face != 1 \
			or warrior.character_state.reserve_weapon_equipment != null \
			or warrior.character_state.reserve_weapon_face != 1 \
			or warrior.character_state.equipment_instance_ids != ids_before \
			or _inventory_bytes(warrior.character_state) != backpack_before \
			or not events.is_empty():
		_fail("WARRIOR_HOOK: empty reserve switch mutated state or emitted success hooks")


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
	_set_test_weapon_pair(warrior)
	var diagnostic_armor := EquipmentData.new()
	diagnostic_armor.item_name = "诊断护甲"
	diagnostic_armor.equip_slot = EquipmentData.EquipSlot.ARMOR
	diagnostic_armor.damage_reduction = 1
	warrior.character_state.armor_equipment = diagnostic_armor
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
	var selected := (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData
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

	var unplayed := (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData
	warrior.discard_pile.append(unplayed)
	warrior.move_discard_card_to_hand(unplayed)
	warrior.mark_temporary_card(unplayed, -2, true, true)
	warrior.exile_expiring_temporary_cards(controller)
	if warrior.exiled_pile.find(unplayed) < 0:
		_fail("WARRIOR_HOOK: unplayed rehearsed card did not exile at turn end")


func _test_playability_guards(controller: BattleController, warrior: BattleUnitState) -> void:
	var rehearsal := (load("res://resources/cards/rehearsal.tres") as CardData).duplicate() as CardData
	var bulwark := (load("res://resources/cards/wound_forged_bulwark.tres") as CardData).duplicate() as CardData
	var other := (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData
	if rehearsal == null or bulwark == null or other == null:
		_fail("WARRIOR_HOOK: playability guard resources missing")
		return
	controller.current_unit = warrior
	warrior.current_ap = 10
	warrior.clear_armor({"controller": controller})
	warrior.discard_pile.assign([bulwark])
	if controller.can_play_card_with_mode(warrior, bulwark, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_HOOK: bulwark momentum enabled without armor")
	warrior.discard_pile.assign([rehearsal])
	if controller.can_play_card_with_mode(warrior, rehearsal, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_HOOK: rehearsal momentum enabled without another discard card")
	warrior.discard_pile.append(other)
	if not controller.can_play_card_with_mode(warrior, rehearsal, CardEnums.CardPlayMode.MOMENTUM):
		_fail("WARRIOR_HOOK: rehearsal momentum stayed disabled with a valid choice")


func _test_nested_action_limit(controller: BattleController) -> void:
	_outer_limit_count = 0
	_nested_limit_count = 0
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_queue_outer_limit_effects"),
		[controller]
	))
	if _nested_limit_count != 31:
		_fail("WARRIOR_HOOK: nested action effect count expected 31, got %d" % _nested_limit_count)
	if _outer_limit_count != 31:
		_fail("WARRIOR_HOOK: outer action limit was not restored after nested action; got %d" % _outer_limit_count)


func _test_payment_rollback(controller: BattleController, warrior: BattleUnitState) -> void:
	var test_card := CardData.new()
	test_card.card_name = "支付回滚诊断"
	test_card.ap_cost = 1
	test_card.has_combo = true
	var first_condition := DiscardHandCondition.new()
	var second_condition := DiscardHandCondition.new()
	var switch_condition := PreparedSwitchPaymentCondition.new()
	test_card.combo_conditions.assign([switch_condition, first_condition, second_condition])
	var payment_card := (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData
	var discard_marker := {"count": 0}
	var discard_listener: StatusEffect = DIAGNOSTIC_DISCARD_STATUS_SCRIPT.new()
	discard_listener.set("marker", discard_marker)
	warrior.statuses.clear()
	warrior.add_status(discard_listener)
	warrior.hand.assign([test_card, payment_card])
	warrior.discard_pile.clear()
	warrior.current_ap = 5
	var active := load("res://resources/items/training_sword.tres") as EquipmentData
	var reserve := load("res://resources/items/heavy_greatsword.tres") as EquipmentData
	warrior.character_state.weapon_equipment = active
	warrior.character_state.weapon_face = 1
	warrior.character_state.reserve_weapon_equipment = reserve
	warrior.character_state.reserve_weapon_face = 0
	warrior.character_state.equipment_instance_ids = {
		CharacterEquipmentModel.SLOT_WEAPON: "payment_active_id",
		CharacterEquipmentModel.SLOT_RESERVE_WEAPON: "payment_reserve_id",
		"armor": "payment_armor_id",
		"custom": {"nested": ["a", "b"]},
	}
	var equipment_ids_before := warrior.character_state.equipment_instance_ids.duplicate(true)
	if controller.play_card(warrior, test_card, [], {}, CardEnums.CardPlayMode.COMBO):
		_fail("WARRIOR_HOOK: intentionally failing payment chain unexpectedly succeeded")
	if warrior.current_ap != 5 or warrior.hand != [test_card, payment_card] or not warrior.discard_pile.is_empty():
		_fail("WARRIOR_HOOK: failed special payment did not restore AP and card zones")
	if int(discard_marker.get("count", 0)) != 0:
		_fail("WARRIOR_HOOK: rolled-back payment still executed a discard hook")
	if warrior.character_state.weapon_equipment != active \
			or warrior.character_state.weapon_face != 1 \
			or warrior.character_state.reserve_weapon_equipment != reserve \
			or warrior.character_state.reserve_weapon_face != 0 \
			or warrior.character_state.equipment_instance_ids != equipment_ids_before:
		_fail("WARRIOR_HOOK: failed payment did not restore both weapon slots, faces, and full instance IDs")
	if controller.resolution_runner.queue_scopes.size() != 1 \
		or not (controller.resolution_runner.queue_scopes[0] as Array).is_empty():
		_fail("WARRIOR_HOOK: failed payment left effects in the base queue")


func _test_full_inventory_weapon_switch(controller: BattleController) -> void:
	var state := CharacterState.new()
	var old_weapon := load("res://resources/items/training_sword.tres") as EquipmentData
	var new_weapon := load("res://resources/items/heavy_greatsword.tres") as EquipmentData
	var filler := load("res://resources/items/healing_potion.tres") as ItemData
	if old_weapon == null or new_weapon == null or filler == null:
		_fail("WARRIOR_HOOK: equipment switch diagnostic resources missing")
		return
	state.weapon_equipment = old_weapon
	var source_stack := InventoryStack.new()
	source_stack.item_data = new_weapon
	source_stack.count = 2
	state.inventory.append(source_stack)
	for _i in range(CharacterState.INVENTORY_LIMIT - 1):
		var filler_stack := InventoryStack.new()
		filler_stack.item_data = filler
		filler_stack.count = 1
		state.inventory.append(filler_stack)
	var blocked := CharacterEquipmentModel.switch_equipment_from_inventory(state, new_weapon)
	if bool(blocked.get("success", false)) or state.weapon_equipment != old_weapon or source_stack.count != 2:
		_fail("WARRIOR_HOOK: full inventory switch did not fail atomically")
	source_stack.count = 1
	var switched := CharacterEquipmentModel.switch_equipment_from_inventory(state, new_weapon)
	if not bool(switched.get("success", false)) or state.weapon_equipment != new_weapon or state.inventory.size() != CharacterState.INVENTORY_LIMIT:
		_fail("WARRIOR_HOOK: switch should succeed when consuming the source stack frees one slot")

	var mage_state := CharacterState.new()
	mage_state.character_data = CharacterData.new()
	mage_state.character_data.character_class = CardEnums.CardClass.MAGE
	var generic_old := EquipmentData.new()
	generic_old.item_name = "non-warrior old weapon"
	generic_old.equip_slot = EquipmentData.EquipSlot.WEAPON
	var generic_new := EquipmentData.new()
	generic_new.item_name = "non-warrior inventory weapon"
	generic_new.equip_slot = EquipmentData.EquipSlot.WEAPON
	mage_state.weapon_equipment = generic_old
	var mage_stack := InventoryStack.new()
	mage_stack.item_data = generic_new
	mage_stack.count = 1
	mage_stack.stack_id = "non_warrior_inventory_weapon"
	mage_state.inventory.append(mage_stack)
	var mage := BattleUnitState.new()
	mage.character_state = mage_state
	var generic_result := controller.switch_weapon_from_inventory(mage)
	if not bool(generic_result.get("success", false)) \
			or mage_state.weapon_equipment != generic_new \
			or mage_state.reserve_weapon_equipment != null \
			or mage_state.inventory.size() != 1 \
			or mage_state.inventory[0].item_data != generic_old:
		_fail("WARRIOR_HOOK: non-warrior controller inventory switching no longer uses the generic path")

	var warrior_state := CharacterState.new()
	warrior_state.character_data = CharacterData.new()
	warrior_state.character_data.character_class = CardEnums.CardClass.WARRIOR
	warrior_state.weapon_equipment = generic_old
	warrior_state.reserve_weapon_equipment = generic_new
	var armor := EquipmentData.new()
	armor.item_name = "warrior inventory armor"
	armor.equip_slot = EquipmentData.EquipSlot.ARMOR
	var armor_stack := InventoryStack.new()
	armor_stack.item_data = armor
	armor_stack.count = 1
	armor_stack.stack_id = "warrior_inventory_armor"
	warrior_state.inventory.append(armor_stack)
	var warrior := BattleUnitState.new()
	warrior.character_state = warrior_state
	var armor_result := controller.switch_equipment_from_inventory(warrior, armor)
	if not bool(armor_result.get("success", false)) \
			or warrior_state.armor_equipment != armor \
			or warrior_state.weapon_equipment != generic_old \
			or warrior_state.reserve_weapon_equipment != generic_new:
		_fail("WARRIOR_HOOK: prepared weapon delegation intercepted explicit non-weapon equipment")

	var explicit_weapon := EquipmentData.new()
	explicit_weapon.item_name = "explicit warrior inventory weapon"
	explicit_weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	var explicit_weapon_stack := InventoryStack.new()
	explicit_weapon_stack.item_data = explicit_weapon
	explicit_weapon_stack.count = 1
	explicit_weapon_stack.stack_id = "explicit_warrior_inventory_weapon"
	warrior_state.inventory.append(explicit_weapon_stack)
	var explicit_weapon_result := controller.switch_equipment_from_inventory(warrior, explicit_weapon)
	if not bool(explicit_weapon_result.get("success", false)) \
			or warrior_state.weapon_equipment != explicit_weapon \
			or warrior_state.reserve_weapon_equipment != generic_new:
		_fail("WARRIOR_HOOK: generic equipment API ignored an explicit Warrior inventory weapon")


func _set_test_weapon_pair(warrior: BattleUnitState) -> void:
	var training := load("res://resources/items/training_sword.tres") as EquipmentData
	var heavy := load("res://resources/items/heavy_greatsword.tres") as EquipmentData
	warrior.character_state.weapon_equipment = training
	warrior.character_state.weapon_face = 0
	warrior.character_state.reserve_weapon_equipment = heavy
	warrior.character_state.reserve_weapon_face = 0
	warrior.character_state.inventory.clear()
	warrior.equipment_runtime_states.clear()


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


func _queue_outer_limit_effects(controller: BattleController) -> void:
	for _i in range(32):
		controller.enqueue_effect(Callable(self, "_count_limit_effect").bind(false))
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_queue_nested_limit_effects"),
		[controller]
	))


func _queue_nested_limit_effects(controller: BattleController) -> void:
	for _i in range(31):
		controller.enqueue_effect(Callable(self, "_count_limit_effect").bind(true))


func _count_limit_effect(nested: bool) -> void:
	if nested:
		_nested_limit_count += 1
	else:
		_outer_limit_count += 1


func _deal_twice(controller: BattleController, source: BattleUnitState, target: BattleUnitState) -> void:
	controller.apply_damage(source, target, 1, "浴血诊断一")
	controller.apply_damage(source, target, 1, "浴血诊断二")


func _prepare(controller: BattleController, warrior: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = warrior
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	warrior.turn_serial = 1
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	ally.set_hex_cell(Vector2i(2, 5), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 4), controller.map_data)


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
