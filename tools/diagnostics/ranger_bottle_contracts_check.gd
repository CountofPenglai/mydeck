extends Node

const BOTTLE_PATH := "res://resources/cards/ranger_exotic_bottle.tres"
const OBSERVER := preload("res://tools/diagnostics/ranger_bottle_contracts_observer.gd")

var _exit_code := 0

class DamageDescendantStatus extends StatusEffect:
	var controller: BattleController
	var center := Vector2i(-1, -1)
	var runs := 0
	var all_saw_pre_payload := true

	func on_after_damage_dealt(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
		if controller == null:
			return
		controller.enqueue_effect(Callable(self, "_observe_payload_boundary"), [], 0, "爆瓶诊断：伤害后代")

	func _observe_payload_boundary() -> void:
		runs += 1
		all_saw_pre_payload = all_saw_pre_payload and controller.surface_state.get_element(center) == BattleSurfaceState.Element.NONE

func _ready() -> void:
	_test_1_stealth_damage_and_descendant_boundary()
	_test_2_lethal_trap_reads_final_surface()
	_test_3_unit_damage_is_not_weapon_strike_but_collection_hooks_run()
	_test_4_paired_range_cooldown_and_payload_rejections()
	print("RANGER_BOTTLE_CONTRACTS: completed")
	get_tree().quit(_exit_code)

func _test_1_stealth_damage_and_descendant_boundary() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var adjacent: BattleUnitState = f.c.enemy_units[1]
	adjacent.is_deployed = true
	adjacent.set_hex_cell(Vector2i(5, 3), f.c.map_data)
	adjacent.set_current_health(adjacent.get_max_health())
	_seed_residue(f.c, f.r.cell, BattleSurfaceState.Element.FIRE)
	var descendant := DamageDescendantStatus.new()
	descendant.status_id = "ranger_bottle_damage_descendant"
	descendant.controller = f.c
	descendant.center = f.e.cell
	f.r.add_status(descendant)
	var agility_bonus: int = f.r.get_damage_bonus({"controller": f.c, "resolved_damage_type": CardEnums.DamageType.AGILITY})
	var center_before: int = f.e.get_current_health()
	var adjacent_before: int = adjacent.get_current_health()
	if not f.c.enter_ranger_stealth(f.r, "爆瓶合同诊断"):
		_fail("1 stealth: could not enter real stealth")
		return
	if not f.c.play_card(f.r, _hand_card(f.r), [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("1 stealth: actual controller play rejected")
		return
	var multiplier := 1.5
	var expected_center := ceili(float(8 + agility_bonus) * multiplier)
	var expected_adjacent := ceili(float(4 + agility_bonus) * multiplier)
	if center_before - f.e.get_current_health() != expected_center or adjacent_before - adjacent.get_current_health() != expected_adjacent:
		_fail("1 stealth: center=%d/%d adjacent=%d/%d" % [center_before - f.e.get_current_health(), expected_center, adjacent_before - adjacent.get_current_health(), expected_adjacent])
	if descendant.runs <= 0 or not descendant.all_saw_pre_payload:
		_fail("1 boundary: queued after-damage descendants ran=%d before_payload=%s" % [descendant.runs, str(descendant.all_saw_pre_payload)])

func _test_2_lethal_trap_reads_final_surface() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var bottle_center := Vector2i(3, 3)
	var trap_cell := Vector2i(4, 3)
	var exterior_cell := Vector2i(5, 3)
	f.e.set_hex_cell(Vector2i(6, 3), f.c.map_data)
	_seed_residue(f.c, f.r.cell, BattleSurfaceState.Element.WATER)
	f.c.apply_base_surface_element(trap_cell, BattleSurfaceState.Element.FIRE, {"diagnostic": "bottle trap old surface"})
	var trap: BattleObjectState = f.c.place_elemental_trap(f.r, trap_cell)
	if trap == null:
		_fail("2 trap: fixture could not place elemental trap")
		return
	trap.current_health = 1
	if not f.c.play_card(f.r, _hand_card(f.r), [bottle_center], {"bottle_payload": [BattleSurfaceState.Element.WATER]}, CardEnums.CardPlayMode.NORMAL):
		_fail("2 trap: actual controller play rejected")
		return
	var final_surface: int = f.c.surface_state.get_element(trap_cell)
	if trap.is_active() or final_surface == BattleSurfaceState.Element.FIRE:
		_fail("2 trap: lethal trap did not finish after payload active=%s final=%d" % [str(trap.is_active()), final_surface])
	if final_surface != BattleSurfaceState.Element.STEAM or f.c.surface_state.get_element(exterior_cell) != BattleSurfaceState.Element.STEAM:
		_fail("2 trap: exterior trap-only ring was not final STEAM exterior=%d final=%d" % [f.c.surface_state.get_element(exterior_cell), final_surface])

func _test_3_unit_damage_is_not_weapon_strike_but_collection_hooks_run() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var observer := OBSERVER.new() as RangerBottleContractsObserver
	var weapon := f.r.character_state.weapon_equipment.duplicate(true) as EquipmentData
	weapon.passive_effects.append(observer)
	f.r.character_state.weapon_equipment = weapon
	f.r.equipment_runtime_states.clear()
	_seed_residue(f.c, f.r.cell, BattleSurfaceState.Element.FIRE)
	if not f.c.play_card(f.r, _hand_card(f.r), [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("3 hooks: actual controller play rejected")
		return
	if observer.after_strike_calls != 0 or observer.weapon_strike_metadata_calls != 0:
		_fail("3 hooks: bottle dispatched weapon semantics after_strike=%d strike_metadata=%d" % [observer.after_strike_calls, observer.weapon_strike_metadata_calls])
	if observer.after_damage_calls <= 0 or observer.collection_modifier_calls <= 0 or observer.collection_notifications <= 0 or observer.collected_amount != 2 or int(f.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.FIRE, 0)) != 1:
		_fail("3 hooks: damage=%d modifier=%d notifications=%d collected=%d leftover=%d" % [observer.after_damage_calls, observer.collection_modifier_calls, observer.collection_notifications, observer.collected_amount, int(f.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.FIRE, 0))])

func _test_4_paired_range_cooldown_and_payload_rejections() -> void:
	var heavy := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_set_weapon(heavy.r, "ranger_sea_dragon_pair")
	_seed_residue(heavy.c, heavy.r.cell, BattleSurfaceState.Element.FIRE)
	heavy.c.perform_strike(heavy.r, heavy.e, null, "爆瓶合同：重弩冷却", "paired")
	if heavy.r.can_use_attack_mode("paired"):
		_fail("4 cooldown: heavy ranged weapon did not enter cooldown")
	var heavy_card := _hand_card(heavy.r)
	var displayed_range := heavy_card.get_effective_range(heavy.r, "paired")
	var target_range: int = heavy.c.get_effective_targeting_range_at_cell(heavy.r, heavy.e.cell, "paired", heavy.e)
	if displayed_range != target_range:
		_fail("4 cooldown: card range display=%d did not match bottle targeting range=%d" % [displayed_range, target_range])
	var heavy_ap: int = heavy.r.current_ap
	if not heavy.c.play_card(heavy.r, heavy_card, [heavy.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL) or heavy.r.current_ap != heavy_ap - 2:
		_fail("4 cooldown: bottle could not use paired range during weapon cooldown")
	var no_paired := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_seed_residue(no_paired.c, no_paired.r.cell, BattleSurfaceState.Element.FIRE)
	no_paired.r.character_state.weapon_equipment.paired_component = null
	_assert_rejected_without_mutation(no_paired, [BattleSurfaceState.Element.FIRE], "no paired")
	var wrong_paired := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_seed_residue(wrong_paired.c, wrong_paired.r.cell, BattleSurfaceState.Element.FIRE)
	wrong_paired.r.character_state.weapon_equipment.paired_component = EquipmentData.new()
	_assert_rejected_without_mutation(wrong_paired, [BattleSurfaceState.Element.FIRE], "wrong paired")
	for payload in [[], [BattleSurfaceState.Element.FIRE, BattleSurfaceState.Element.FIRE], [BattleSurfaceState.Element.ICE]]:
		var invalid := _fixture(Vector2i(1, 3), Vector2i(4, 3))
		_seed_residue(invalid.c, invalid.r.cell, BattleSurfaceState.Element.FIRE)
		_assert_rejected_without_mutation(invalid, payload, "invalid payload %s" % str(payload))
	var old_only := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	old_only.r.ranger_state.add_element(BattleSurfaceState.Element.FIRE)
	_assert_rejected_without_mutation(old_only, [BattleSurfaceState.Element.FIRE], "old inventory only")

func _assert_rejected_without_mutation(f: Dictionary, payload: Array, label: String) -> void:
	var card := _hand_card(f.r)
	var ap: int = f.r.current_ap
	var source_entries: int = f.c.surface_state.get_collectible_entries(f.r.cell, "unit:%d" % f.r.unit_id).size()
	if f.c.play_card(f.r, card, [f.e.cell], {"bottle_payload": payload}, CardEnums.CardPlayMode.NORMAL) or f.r.current_ap != ap or not f.r.hand.has(card) or f.c.surface_state.get_collectible_entries(f.r.cell, "unit:%d" % f.r.unit_id).size() != source_entries:
		_fail("4 rejection: %s mutated AP/card/source" % label)

func _fixture(ranger_cell: Vector2i, enemy_cell: Vector2i) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var ranger := _find_ranger(controller)
	var enemy: BattleUnitState = controller.enemy_units[0]
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.current_ap = 9
	ranger.turn_serial = 1
	ranger.is_deployed = true
	enemy.is_deployed = true
	ranger.set_hex_cell(ranger_cell, controller.map_data)
	enemy.set_hex_cell(enemy_cell, controller.map_data)
	_set_weapon(ranger, "ranger_dagger_crossbow")
	return {"c": controller, "r": ranger, "e": enemy}

func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit.is_ranger():
			return unit
	return null

func _hand_card(ranger: BattleUnitState) -> CardData:
	var card := (load(BOTTLE_PATH) as CardData).duplicate(true) as CardData
	ranger.hand.append(card)
	return card

func _seed_residue(controller: BattleController, cell: Vector2i, element: int) -> void:
	controller.surface_state.add_residue(cell, element, controller.battle_round)

func _set_weapon(ranger: BattleUnitState, name: String) -> void:
	ranger.character_state.weapon_equipment = (load("res://resources/items/%s.tres" % name) as EquipmentData).duplicate(true) as EquipmentData
	ranger.character_state.weapon_face = 0
	ranger.equipment_runtime_states.clear()

func _fail(message: String) -> void:
	_exit_code = 1
	push_error("RANGER_BOTTLE_CONTRACTS: " + message)
	print("ERROR: " + message)
