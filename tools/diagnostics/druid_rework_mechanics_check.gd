extends Node


class ProductionProbeEffect extends CardEffect:
	var production: int = 1
	var mana_seen_at_turn_start: int = -1

	func get_mana_production(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> int:
		return production

	func on_zone_owner_turn_start(owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
		mana_seen_at_turn_start = owner.get_available_mana()


class FailingManaCostEffect extends CardEffect:
	func pay_play_cost(context: Dictionary = {}) -> bool:
		var user := context.get("user") as BattleUnitState
		if user != null:
			user.pay_mana(2, {"controller": context.get("controller"), "reason": "diagnostic_failed_cost"})
		return false


class MarkManaEffect extends CardEffect:
	func play(context: Dictionary = {}, _targets: Array = []) -> void:
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.mark_played_card_to_mana(context)


class EndTurnManaDescendantEffect extends CardEffect:
	func on_zone_owner_turn_end(owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> void:
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.resolution_runner.enqueue_after_current_effect_queue(
				Callable(self, "_grant_after_zone_end"),
				[owner],
				"diagnostic end-turn mana descendant"
			)

	func _grant_after_zone_end(owner: BattleUnitState) -> void:
		owner.gain_mana(1, {"reason": "diagnostic_end_turn_descendant"})


class PreventForcedRevertEffect extends EquipmentEffect:
	func can_replace_druid_form_change(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		target_transformed: bool,
		_context: Dictionary = {}
	) -> bool:
		return not target_transformed

	func try_replace_druid_form_change(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_target_transformed: bool,
		_context: Dictionary = {}
	) -> Dictionary:
		return {"handled": true, "success": true}


var _exit_code := 0


func _ready() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		get_tree().quit(1)
		return
	var controller := fixture.controller as BattleController
	var druid := fixture.druid as BattleUnitState
	var enemy := fixture.enemy as BattleUnitState
	if not _foundation_is_available(druid):
		get_tree().quit(_exit_code)
		return
	_test_mana_is_stored_and_zone_entry_is_not_a_gain(controller, druid)
	_test_human_production_precedes_zone_turn_start(controller, druid)
	_test_transformed_upkeep_retains_or_exits_at_turn_end(controller, druid)
	_test_upkeep_waits_for_end_turn_descendants_and_forces_revert(controller, druid)
	_test_failed_cost_rollback_restores_stored_mana(controller, druid)
	_test_inverted_cards_discard_unless_explicitly_marked(controller, druid)
	_test_root_is_binary_persistent_and_inert(druid, enemy)
	print("DRUID_REWORK_MECHANICS: completed")
	get_tree().quit(_exit_code)


func _test_mana_is_stored_and_zone_entry_is_not_a_gain(_controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	druid.gain_mana(2, {"reason": "diagnostic_seed"})
	var zone_card := _card("zone-entry", CardEffect.new())
	druid.add_card_to_mana_zone(zone_card, {"reason": "diagnostic_entry"})
	if druid.get_available_mana() != 2:
		_fail("stored mana: entering the mana zone changed the current balance")
	if not druid.remove_card_from_mana_zone(zone_card) or druid.get_available_mana() != 2:
		_fail("stored mana: removing a mana-zone card reduced already stored mana")


func _test_human_production_precedes_zone_turn_start(controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	var probe := ProductionProbeEffect.new()
	probe.production = 3
	druid.add_card_to_mana_zone(_card("production-probe", probe), {"reason": "diagnostic_setup"})
	_run_turn_start(controller, druid)
	if druid.get_available_mana() != 3:
		_fail("turn start: human druid did not receive the probe's production")
	if probe.mana_seen_at_turn_start != 3:
		_fail("turn start: zone benefits ran before mana-zone production")


func _test_transformed_upkeep_retains_or_exits_at_turn_end(controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	druid.gain_mana(2, {"reason": "diagnostic_seed"})
	druid.add_card_to_mana_zone(_card("suppressed-production", CardEffect.new()), {"reason": "diagnostic_setup"})
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	_run_turn_start(controller, druid)
	if druid.get_available_mana() != 2:
		_fail("transformed start: mana-zone production was not suppressed")
	_run_turn_end(controller, druid)
	if not druid.is_druid_transformed() or druid.get_available_mana() != 1:
		_fail("upkeep: paying one of two mana did not retain transformed form and one mana")
	_reset_druid(druid)
	druid.gain_mana(1, {"reason": "diagnostic_seed"})
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	_run_turn_end(controller, druid)
	if not druid.is_druid_transformed() or druid.get_available_mana() != 0:
		_fail("upkeep: paying the last mana incorrectly ended transformed form")
	_reset_druid(druid)
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	_run_turn_end(controller, druid)
	if druid.is_druid_transformed():
		_fail("upkeep: unaffordable transformed upkeep did not return to human form")


func _test_failed_cost_rollback_restores_stored_mana(controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	druid.gain_mana(2, {"reason": "diagnostic_seed"})
	var card := _card("failing-cost", FailingManaCostEffect.new())
	druid.hand.append(card)
	druid.current_ap = 3
	if controller.play_card(druid, card, []):
		_fail("rollback: a card whose paid cost failed resolved successfully")
	if druid.get_available_mana() != 2 or not druid.hand.has(card):
		_fail("rollback: cancelled card payment did not restore stored mana and hand")


func _test_upkeep_waits_for_end_turn_descendants_and_forces_revert(controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	druid.add_card_to_mana_zone(_card("end-turn-descendant", EndTurnManaDescendantEffect.new()), {"reason": "diagnostic_setup"})
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	_run_turn_end(controller, druid)
	if not druid.is_druid_transformed() or druid.get_available_mana() != 0:
		_fail("upkeep ordering: deferred zone-end descendant did not resolve before upkeep")
	_reset_druid(druid)
	var replacement_weapon := EquipmentData.new()
	replacement_weapon.passive_effects.append(PreventForcedRevertEffect.new())
	var original_weapon := druid.character_state.weapon_equipment
	druid.character_state.weapon_equipment = replacement_weapon
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	_run_turn_end(controller, druid)
	druid.character_state.weapon_equipment = original_weapon
	if druid.is_druid_transformed():
		_fail("upkeep reversion: unaffordable upkeep allowed an equipment replacement to block forced reversion")


func _test_inverted_cards_discard_unless_explicitly_marked(controller: BattleController, druid: BattleUnitState) -> void:
	_reset_druid(druid)
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	var ordinary := _card("inverted-default", CardEffect.new(), true)
	druid.hand.append(ordinary)
	druid.current_ap = 3
	if not controller.play_card(druid, ordinary, []) or not druid.discard_pile.has(ordinary) or druid.mana_zone.has(ordinary):
		_fail("inverted destination: default inverted card did not discard")
	var marked := _card("inverted-marked", MarkManaEffect.new(), true)
	druid.hand.append(marked)
	druid.current_ap = 3
	if not controller.play_card(druid, marked, []) or not druid.mana_zone.has(marked):
		_fail("inverted destination: explicit mana mark was not honored")


func _test_root_is_binary_persistent_and_inert(druid: BattleUnitState, enemy: BattleUnitState) -> void:
	enemy.statuses.clear()
	var base_reduction := enemy.get_damage_reduction()
	var root_script := load("res://scripts/status/druid_root_status.gd") as GDScript
	if root_script == null:
		_fail("root: druid_root status script is missing")
		return
	var root := root_script.new() as StatusEffect
	enemy.add_status(root)
	var duplicate := root_script.new() as StatusEffect
	enemy.add_status(duplicate)
	var applied := enemy.get_status("druid_root")
	if applied == null or applied.stacks != 1:
		_fail("root: repeated application stacked instead of staying binary")
	if enemy.get_damage_reduction() != base_reduction or not enemy.can_start_voluntary_movement():
		_fail("root: root applied an intrinsic combat or movement effect")
	enemy.turn_serial += 5
	if not enemy.has_status("druid_root") or enemy.has_status("ranger_rooted"):
		_fail("root: root expired automatically or reused ranger rooted identity")


func _fixture() -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	if scenario == null:
		_fail("fixture: missing sample battle scenario")
		return {}
	var controller := BattleController.new()
	controller.setup(scenario)
	var druid := _find_druid(controller)
	var enemy: BattleUnitState = controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if druid == null or enemy == null:
		_fail("fixture: missing druid or enemy")
		return {}
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = druid
	druid.is_deployed = true
	druid.set_hex_cell(Vector2i(2, 2), controller.map_data)
	enemy.is_deployed = true
	enemy.set_hex_cell(Vector2i(3, 2), controller.map_data)
	return {"controller": controller, "druid": druid, "enemy": enemy}


func _reset_druid(druid: BattleUnitState) -> void:
	druid.hand.clear()
	druid.discard_pile.clear()
	druid.exiled_pile.clear()
	druid.mana_zone.clear()
	druid.enchant_zone.clear()
	druid.statuses.clear()
	druid.druid_state.reset_for_battle()
	druid.set_druid_transformed(false)
	druid.current_ap = 3


func _run_turn_start(controller: BattleController, druid: BattleUnitState) -> void:
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.push_action_frame(BattleActionFrame.create(
		Callable(controller, "_resolve_turn_start_action"),
		[druid],
		0,
		"druid diagnostic turn start",
		{"unit": druid},
		Callable(controller, "_finish_turn_start_action"),
		[druid]
	))


func _run_turn_end(controller: BattleController, druid: BattleUnitState) -> void:
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.end_current_turn()


func _card(name: String, effect: CardEffect, dual: bool = false) -> CardData:
	var card := CardData.new()
	card.card_name = name
	card.effect = effect
	card.ap_cost = 0
	card.target_type = CardEnums.TargetType.NONE
	card.is_druid_dual_card = dual
	card.allow_upright_play = true
	card.allow_inverted_play = true
	return card


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit
	return null


func _foundation_is_available(druid: BattleUnitState) -> bool:
	if druid == null or not druid.has_method("gain_mana"):
		_fail("foundation: BattleUnitState is missing stored-mana gain_mana API")
		return false
	if load("res://scripts/status/druid_root_status.gd") == null:
		_fail("foundation: DruidRootStatus is missing")
		return false
	return true


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("DRUID_REWORK_MECHANICS: " + message)
	print("ERROR: DRUID_REWORK_MECHANICS: " + message)
