extends Node

const TRAP_AFTER_STRIKE_SURFACE_STATUS = preload("res://tools/diagnostics/trap_after_strike_surface_status.gd")

var _exit_code := 0
var _frame_controller: BattleController
var _frame_owner: BattleUnitState
var _frame_trap: BattleObjectState
var _frame_spread_cell := Vector2i(-1, -1)
var _frame_parent_marker_ran := false
var _frame_parent_marker_saw_spread := false
var _frame_second_action_ran := false
var _frame_second_action_clean := false


func _ready() -> void:
	_test_surface_change_only_resolves_final_state()
	_test_trap_cap_and_attack_notification_contract()
	_test_environment_does_not_trigger_and_cap_is_immediate()
	_test_real_object_strikes_and_owner_persistence()
	_test_lethal_object_strike_waits_for_after_strike_descendants()
	_test_action_attack_scope_preserves_parent_effect_order()
	_test_action_frame_after_callback_does_not_leak_attack_callbacks()
	_test_tactical_planner_prefers_highest_legal_threat()
	_test_tactical_planner_ignores_los_blocked_high_threat_trap()
	_test_legacy_melee_and_ranged_behaviors_damage_farther_high_threat_target()
	_test_legacy_melee_uses_card_only_range_against_highest_threat()
	_test_legacy_melee_attacks_shared_occupied_cell_target()
	_test_legacy_melee_behavior_moves_toward_higher_threat_trap()
	_test_ai_attack_legality_helpers()
	_test_ownerless_trap_constructor()
	print("RANGER_TRAPS_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_surface_change_only_resolves_final_state() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var cell := Vector2i(4, 4)
	var unit: BattleUnitState = controller.player_units[0]
	unit.is_deployed = true
	unit.set_hex_cell(cell, controller.map_data)
	var before := unit.get_current_health()
	controller.apply_advanced_surface(cell, BattleSurfaceState.Element.LAVA)
	if unit.get_current_health() != before - 3:
		_fail("surface change did not immediately resolve the final ground effect")
	var after_first := unit.get_current_health()
	controller.apply_advanced_surface(cell, BattleSurfaceState.Element.LAVA)
	if unit.get_current_health() != after_first:
		_fail("reapplying an identical surface resolved it again")
	controller.apply_advanced_surface(cell, BattleSurfaceState.Element.BLAZE)
	if unit.get_current_health() != after_first - 2:
		_fail("a changed air channel was hidden by the existing ground surface")


func _test_trap_cap_and_attack_notification_contract() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	owner.is_deployed = true
	owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	controller.apply_advanced_surface(Vector2i(3, 2), BattleSurfaceState.Element.ICE)
	var trap: BattleObjectState = controller.place_elemental_trap(owner, Vector2i(3, 2))
	if trap == null or trap.get_threat_level() != 1:
		_fail("elemental trap placement did not retain independent threat")
		return
	if controller.get_trap_limit(owner) != 1 or controller.get_active_trap_count(owner) != 1:
		_fail("trap limit did not dynamically count the owner traps")
	controller.perform_object_strike_with_modifier(owner, trap, null, -999, "零伤害打击")
	controller.resolve_effect_queue()
	if trap.is_active():
		_fail("zero-damage attack notification did not explode the trap")


func _test_environment_does_not_trigger_and_cap_is_immediate() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	owner.is_deployed = true
	owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	controller.apply_advanced_surface(Vector2i(3, 2), BattleSurfaceState.Element.ICE)
	var first: BattleObjectState = controller.place_elemental_trap(owner, Vector2i(3, 2))
	controller.apply_object_damage(null, first, 0, "地表", {"environmental": true})
	controller.resolve_effect_queue()
	if first.trap_explosion_queued:
		_fail("environmental damage scheduled a trap explosion")
	controller.apply_advanced_surface(Vector2i(4, 2), BattleSurfaceState.Element.ICE)
	var excess: BattleObjectState = controller.place_elemental_trap(owner, Vector2i(4, 2))
	if excess != null and excess.is_active():
		_fail("an over-cap trap did not explode synchronously on placement")


func _test_real_object_strikes_and_owner_persistence() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	owner.is_deployed = true
	owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	controller.apply_advanced_surface(Vector2i(3, 2), BattleSurfaceState.Element.ICE)
	var trap: BattleObjectState = controller.place_elemental_trap(owner, Vector2i(3, 2))
	if trap == null:
		_fail("real lethal strike fixture could not place a trap")
		return
	owner.set_current_health(0)
	if controller.get_active_trap_count(owner) != 1:
		_fail("owner death removed a live trap from dynamic counting")
	owner.trap_limit_modifier = -1
	if trap.is_active() == false:
		_fail("lowering the cap retroactively exploded a live trap")
	owner.set_current_health(owner.get_max_health())
	controller.perform_object_strike_with_modifier(owner, trap, null, 999, "致死打击")
	controller.resolve_effect_queue()
	if trap.is_active() or trap.trap_explosion_queued:
		_fail("lethal object strike did not resolve one retained explosion")


func _test_lethal_object_strike_waits_for_after_strike_descendants() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	var trap_cell := Vector2i(3, 2)
	var spread_cell := Vector2i(4, 2)
	owner.is_deployed = true
	owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	controller.apply_advanced_surface(trap_cell, BattleSurfaceState.Element.ICE)
	var trap: BattleObjectState = controller.place_elemental_trap(owner, trap_cell)
	if trap == null:
		_fail("after-strike ordering fixture could not place trap")
		return
	var status := TRAP_AFTER_STRIKE_SURFACE_STATUS.new() as StatusEffect
	status.status_id = "diagnostic_trap_after_strike_surface"
	status.display_name = "诊断陷阱后击地表"
	status.controller = controller
	status.trap = trap
	owner.add_status(status)
	controller.perform_object_strike_with_modifier(owner, trap, null, 999, "致死钩子时序")
	if status.observations != [
		"after_hook_trap_queued=true",
		"queued_descendant_trap_queued=true",
	]:
		_fail("lethal strike did not keep the queued trap explosion behind after-strike callbacks: %s" % str(status.observations))
	if controller.surface_state.get_element(spread_cell) != BattleSurfaceState.Element.LAVA:
		_fail("trap spread did not use the queued after-strike surface LAVA")
	if trap.is_active() or trap.trap_explosion_queued:
		_fail("lethal after-strike trap did not finish its single explosion")


func _test_action_attack_scope_preserves_parent_effect_order() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	_frame_controller = controller
	_frame_owner = controller.player_units[0]
	_frame_owner.is_deployed = true
	_frame_owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	var trap_cell := Vector2i(3, 2)
	_frame_spread_cell = Vector2i(4, 2)
	controller.apply_advanced_surface(trap_cell, BattleSurfaceState.Element.ICE)
	_frame_trap = controller.place_elemental_trap(_frame_owner, trap_cell)
	_frame_parent_marker_ran = false
	_frame_parent_marker_saw_spread = false
	if _frame_trap == null:
		_fail("parent effect ordering fixture could not place trap")
		return
	var frame := BattleActionFrame.create(
		Callable(self, "_frame_enqueue_parent_effect_then_strike"),
		[],
		0,
		"诊断：父队列与对象打击"
	)
	controller.resolution_runner.push_action_frame(frame)
	if not _frame_parent_marker_ran:
		_fail("parent effect marker did not run")
	elif not _frame_parent_marker_saw_spread:
		_fail("attack scope drained an unrelated parent effect before after-strike trap explosion")


func _test_action_frame_after_callback_does_not_leak_attack_callbacks() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	_frame_controller = controller
	_frame_owner = controller.player_units[0]
	_frame_owner.is_deployed = true
	_frame_owner.set_hex_cell(Vector2i(2, 2), controller.map_data)
	var trap_cell := Vector2i(3, 2)
	_frame_spread_cell = Vector2i(4, 2)
	controller.apply_advanced_surface(trap_cell, BattleSurfaceState.Element.LAVA)
	_frame_trap = controller.place_elemental_trap(_frame_owner, trap_cell)
	_frame_second_action_ran = false
	_frame_second_action_clean = false
	if _frame_trap == null:
		_fail("after-callback fixture could not place trap")
		return
	controller.resolution_runner.push_action_frame(BattleActionFrame.create(
		Callable(self, "_frame_noop"), [], 0, "诊断：行动本体", null,
		Callable(self, "_frame_after_callback_strike"), []
	))
	controller.resolution_runner.push_action_frame(BattleActionFrame.create(
		Callable(self, "_frame_second_action_assert_clean"), [], 0, "诊断：后续行动"
	))
	if not _frame_second_action_ran or not _frame_second_action_clean:
		_fail("BattleActionFrame after_callback leaked a trap callback into the next action")


func _frame_enqueue_parent_effect_then_strike() -> void:
	_frame_controller.enqueue_effect(Callable(self, "_frame_parent_effect_marker"), [], 0, "诊断：父级后续效果")
	_frame_controller.perform_object_strike_with_modifier(_frame_owner, _frame_trap, null, 999, "作用域顺序")


func _frame_parent_effect_marker() -> void:
	_frame_parent_marker_ran = true
	_frame_parent_marker_saw_spread = _frame_controller.surface_state.get_element(_frame_spread_cell) == BattleSurfaceState.Element.ICE


func _frame_noop() -> void:
	pass


func _frame_after_callback_strike() -> void:
	_frame_controller.perform_object_strike_with_modifier(_frame_owner, _frame_trap, null, -999, "帧后回调零伤害打击")


func _frame_second_action_assert_clean() -> void:
	_frame_second_action_ran = true
	_frame_second_action_clean = _frame_trap != null and not _frame_trap.trap_explosion_queued \
		and _frame_controller.resolution_runner.attack_after_scopes.is_empty() \
		and _frame_controller.resolution_runner.after_current_effect_queue.is_empty()


func _test_tactical_planner_prefers_highest_legal_threat() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var low: BattleUnitState = controller.player_units[0]
	var high := _add_diagnostic_player(controller, low, 2)
	var enemy := _add_diagnostic_enemy(controller, &"bandit_bow", 90)
	if high == null or enemy == null:
		_fail("tactical threat fixture could not create units")
		return
	low.is_deployed = true
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	low.set_hex_cell(Vector2i(3, 4), controller.map_data)
	high.set_hex_cell(Vector2i(5, 4), controller.map_data)
	high.threat_level_modifier = 2
	enemy.hand.clear()
	var chosen := EnemyIntentPlanner.choose_action(controller, enemy, EnemyIntentCategory.Type.ATTACK, 2)
	if chosen == null or chosen.kind != EnemyIntentAction.Kind.BASIC_ATTACK or chosen.targets[0] != high:
		_fail("Tactical planner chose a nearer lower-threat legal target instead of the high-threat target")


func _test_tactical_planner_ignores_los_blocked_high_threat_trap() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	var enemy := _add_diagnostic_enemy(controller, &"bandit_bow", 91)
	if enemy == null:
		_fail("blocked-trap fixture could not create enemy")
		return
	owner.is_deployed = true
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	owner.set_hex_cell(Vector2i(2, 3), controller.map_data)
	controller.spawn_battle_object(BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(3, 4))
	controller.apply_advanced_surface(Vector2i(5, 4), BattleSurfaceState.Element.ICE)
	var trap := controller.place_elemental_trap(owner, Vector2i(5, 4))
	if trap == null or controller.can_basic_attack_target(enemy, trap):
		_fail("blocked high-threat trap fixture did not establish a non-legal trap")
		return
	enemy.hand.clear()
	var chosen := EnemyIntentPlanner.choose_action(controller, enemy, EnemyIntentCategory.Type.ATTACK, 2)
	if chosen == null or chosen.targets[0] != owner:
		_fail("Tactical planner let an LOS-blocked high-threat trap suppress a legal lower-threat attack")


func _test_legacy_melee_and_ranged_behaviors_damage_farther_high_threat_target() -> void:
	for behavior in [MeleeEnemyBehavior.new(), RangedEnemyBehavior.new()]:
		var controller := _make_controller()
		if controller == null:
			return
		var low: BattleUnitState = controller.player_units[0]
		var high := _add_diagnostic_player(controller, low, 2)
		var enemy := _add_diagnostic_enemy(controller, &"bandit_bow", 92)
		low.is_deployed = true
		enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
		var behavior_label := "legacy melee"
		if behavior is RangedEnemyBehavior:
			behavior_label = "legacy ranged"
			low.set_hex_cell(Vector2i(2, 4), controller.map_data)
			high.set_hex_cell(Vector2i(4, 4), controller.map_data)
		else:
			low.set_hex_cell(Vector2i(3, 4), controller.map_data)
			high.set_hex_cell(Vector2i(5, 4), controller.map_data)
		high.threat_level_modifier = 2
		enemy.hand.clear()
		_prepare_direct_enemy_turn(controller, enemy)
		var high_before := high.get_current_health()
		var low_before := low.get_current_health()
		var result: Dictionary = (behavior as EnemyBehavior).choose_action({"controller": controller}, enemy)
		if not bool(result.get("action_started", false)) or high.get_current_health() >= high_before \
				or low.get_current_health() != low_before:
			_fail("%s did not actually damage the farther high-threat legal target" % behavior_label)


func _test_legacy_melee_uses_card_only_range_against_highest_threat() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var low: BattleUnitState = controller.player_units[0]
	var high := _add_diagnostic_player(controller, low, 96)
	var enemy := _add_diagnostic_enemy(controller, &"bandit_blade", 97)
	var sewage_spit := load("res://resources/cards/monster_cards/sewage_spit.tres") as CardData
	if high == null or enemy == null or sewage_spit == null:
		_fail("legacy melee card-only-range fixture could not create units or load sewage spit")
		return
	low.is_deployed = true
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	low.set_hex_cell(Vector2i(2, 4), controller.map_data)
	high.set_hex_cell(Vector2i(4, 4), controller.map_data)
	high.threat_level_modifier = 2
	enemy.hand = [sewage_spit]
	_prepare_direct_enemy_turn(controller, enemy)
	if controller.can_basic_attack_target(enemy, high) or not controller.can_preview_card_targets(enemy, sewage_spit, [high]):
		_fail("legacy melee card-only-range fixture did not establish basic-illegal and sewage-spit-legal targets")
		return
	var high_before := high.get_current_health()
	var low_before := low.get_current_health()
	var result: Dictionary = MeleeEnemyBehavior.new().choose_action({"controller": controller}, enemy)
	if not bool(result.get("action_started", false)) or high.get_current_health() >= high_before \
			or low.get_current_health() != low_before or enemy.hand.has(sewage_spit):
		_fail("legacy melee did not consume sewage spit to damage the farther high-threat card-only target")


func _test_legacy_melee_attacks_shared_occupied_cell_target() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var enemy := _add_diagnostic_enemy(controller, &"bandit_blade", 98)
	var druid_state := load("res://resources/characters/battle_druid_state.tres") as CharacterState
	var double_slime := load("res://resources/items/druid_double_slime.tres") as EquipmentData
	if enemy == null or druid_state == null or double_slime == null:
		_fail("shared-occupied-cell fixture could not create its melee enemy or double-body druid")
		return
	var druid := BattleUnitState.new()
	druid.setup_player(99, druid_state.duplicate(true) as CharacterState, 24.0)
	druid.battle_controller = controller
	druid.is_deployed = true
	druid.character_state.weapon_equipment = double_slime
	druid.equipment_runtime_states.clear()
	druid.set_hex_cell(Vector2i(4, 4), controller.map_data)
	druid.get_equipment_runtime_state(double_slime).set_data("slime_body_cell", Vector2i(2, 4))
	controller.units.append(druid)
	controller.player_units.append(druid)
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	enemy.hand.clear()
	_prepare_direct_enemy_turn(controller, enemy)
	if not controller.can_basic_attack_target(enemy, druid) \
			or controller.map_data.get_distance(enemy.cell, druid.cell) <= controller.get_effective_attack_range_at_cell(enemy, druid.cell):
		_fail("shared-occupied-cell fixture did not establish helper-legal but root-cell-out-of-range geometry")
		return
	var druid_before := druid.get_current_health()
	var enemy_before := enemy.cell
	var result: Dictionary = MeleeEnemyBehavior.new().choose_action({"controller": controller}, enemy)
	if not bool(result.get("action_started", false)) or druid.get_current_health() >= druid_before \
			or enemy.cell != enemy_before:
		_fail("legacy melee did not attack the helper-legal shared occupied cell instead of moving")


func _test_legacy_melee_behavior_moves_toward_higher_threat_trap() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	var enemy := _add_diagnostic_enemy(controller, &"bandit_blade", 93)
	owner.is_deployed = true
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	owner.set_hex_cell(Vector2i(3, 2), controller.map_data)
	owner.threat_level_modifier = -1
	controller.apply_advanced_surface(Vector2i(5, 4), BattleSurfaceState.Element.ICE)
	var trap := controller.place_elemental_trap(owner, Vector2i(5, 4))
	if trap == null:
		_fail("legacy movement fixture could not place high-threat trap")
		return
	enemy.hand.clear()
	_prepare_direct_enemy_turn(controller, enemy)
	var result := MeleeEnemyBehavior.new().choose_action({"controller": controller}, enemy)
	if not bool(result.get("action_started", false)):
		_fail("legacy melee behavior did not start a movement action toward a hostile target")
	elif enemy.cell != Vector2i(3, 4):
		_fail("legacy melee behavior moved to %s instead of literal high-threat-trap approach cell (3, 4)" % str(enemy.cell))


func _add_diagnostic_player(controller: BattleController, source: BattleUnitState, unit_id: int) -> BattleUnitState:
	if controller == null or source == null or source.character_state == null:
		return null
	var unit := BattleUnitState.new()
	unit.setup_player(unit_id, source.character_state.duplicate(true) as CharacterState, 24.0)
	unit.battle_controller = controller
	unit.is_deployed = true
	unit.set_current_health(unit.get_max_health())
	controller.units.append(unit)
	controller.player_units.append(unit)
	return unit


func _add_diagnostic_enemy(controller: BattleController, archetype: StringName, unit_id: int) -> BattleUnitState:
	if controller == null:
		return null
	var unit := BattleUnitState.new()
	unit.setup_enemy(unit_id, ChapterOneEnemyCatalog.create_enemy(archetype, unit_id), 24.0)
	unit.battle_controller = controller
	unit.set_current_health(unit.get_max_health())
	unit.current_ap = 2
	controller.units.append(unit)
	controller.enemy_units.append(unit)
	return unit


func _prepare_direct_enemy_turn(controller: BattleController, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = enemy
	enemy.current_ap = 2


func _test_ai_attack_legality_helpers() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var owner: BattleUnitState = controller.player_units[0]
	owner.is_deployed = true
	owner.set_hex_cell(Vector2i(4, 4), controller.map_data)
	var enemy := BattleUnitState.new()
	enemy.setup_enemy(99, ChapterOneEnemyCatalog.create_enemy(&"bandit_bow", 99), 24.0)
	enemy.is_deployed = true
	enemy.set_hex_cell(Vector2i(1, 4), controller.map_data)
	controller.units.append(enemy)
	controller.enemy_units.append(enemy)
	var trap_cell := Vector2i(-1, -1)
	for cell in controller.map_data.get_all_cells():
		if controller.get_unit_at_cell(cell) == null and controller.map_data.get_distance(enemy.cell, cell) > controller.get_effective_attack_range_at_cell(enemy, cell):
			trap_cell = cell
			break
	if trap_cell.x < 0:
		_fail("AI legality fixture found no out-of-range cell")
		return
	controller.apply_advanced_surface(trap_cell, BattleSurfaceState.Element.ICE)
	var trap: BattleObjectState = controller.place_elemental_trap(owner, trap_cell)
	if controller.can_basic_attack_target(enemy, trap):
		_fail("blocked or out-of-range trap incorrectly passed basic-attack legality")
	if controller.get_nearest_hostile_target(enemy) == null:
		_fail("legacy hostile target helper discarded all candidates before movement")


func _test_ownerless_trap_constructor() -> void:
	var controller := _make_controller()
	if controller == null:
		return
	var cell := Vector2i(4, 2)
	controller.apply_advanced_surface(cell, BattleSurfaceState.Element.ICE)
	var trap := controller.spawn_battle_object(BattleObjectDefinition.Kind.ELEMENTAL_TRAP, cell)
	if trap == null or not trap.is_trap or trap.get_threat_level() != 1 or trap.owner != null:
		_fail("ownerless elemental-trap constructor did not retain trap identity/threat")
		return
	var attacker: BattleUnitState = controller.player_units[0]
	attacker.is_deployed = true
	attacker.set_hex_cell(Vector2i(3, 2), controller.map_data)
	controller.perform_object_strike_with_modifier(attacker, trap, null, 999, "无主陷阱打击")
	if trap.is_active():
		_fail("ownerless trap did not explode after a real attack")


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("RANGER_TRAPS_DIAG: " + message)


func _make_controller() -> BattleController:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		_fail("missing sample battle scenario")
		return null
	var scenario := template.duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	scenario.players.append(load("res://resources/characters/battle_ranger_state.tres") as CharacterState)
	scenario.enemies.clear()
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller
