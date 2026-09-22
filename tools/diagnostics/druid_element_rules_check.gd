extends Node


var _exit_code: int = 0

class SurfaceProtectionEffect extends CardEffect:
	func grants_elemental_surface_protection(_owner: BattleUnitState) -> bool:
		return true


func _ready() -> void:
	_test_earth_grants_three_armor()
	_test_fire_burns_twice_for_two()
	_test_water_adds_one_ap_to_next_move()
	_test_air_moves_away_once()
	_test_extra_earth_is_independent()
	_test_dual_weapon_strike_resolves_element_once()
	_test_explicit_extra_earth_propagates_through_strike()
	_test_protection_keeps_positive_blaze_and_blocks_negative_surface_modifiers()
	_test_surface_entry_protection_does_not_block_direct_damage()
	print("DRUID_ELEMENT_RULES: completed")
	get_tree().quit(_exit_code)


# Catches an element resolver that omits Earth or gives the old two-armor value.
func _test_earth_grants_three_armor() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	_expect(not f.is_empty(), "element fixture is available")
	if f.is_empty():
		return
	var rules := DruidElementRules.new()
	rules.setup(f.c as BattleController)
	var before: int = (f.u as BattleUnitState).get_armor_stacks()
	rules.resolve_after_strike(f.u as BattleUnitState, f.enemy as BattleUnitState, {
		"druid_element": BattleSurfaceState.Element.EARTH,
	})
	_expect((f.u as BattleUnitState).get_armor_stacks() == before + 3, "earth grants three armor")


func _test_fire_burns_twice_for_two() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var target := f.enemy as BattleUnitState
	var rules := DruidElementRules.new()
	rules.setup(f.c as BattleController)
	rules.resolve_after_strike(f.u as BattleUnitState, target, {"druid_element": BattleSurfaceState.Element.FIRE})
	var burn := target.get_status("ranger_burn") as RangerBurnStatus
	_expect(burn != null and burn.damage_per_turn == 2 and burn.remaining_turns == 2, "fire applies two turns of two burn")
	if burn == null: return
	var health := target.get_current_health()
	burn.on_turn_start(target, {"controller": f.c})
	burn.on_turn_start(target, {"controller": f.c})
	_expect(target.get_current_health() == health - 4 and burn.stacks == 0, "fire burn deals two damage on each of two starts")


func _test_water_adds_one_ap_to_next_move() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var target := f.enemy as BattleUnitState
	var rules := DruidElementRules.new()
	rules.setup(f.c as BattleController)
	var before := target.get_move_ap_cost(1, (f.c as BattleController).config)
	rules.resolve_after_strike(f.u as BattleUnitState, target, {"druid_element": BattleSurfaceState.Element.WATER})
	_expect(target.get_move_ap_cost(1, (f.c as BattleController).config) == before + 1, "water adds one AP to next voluntary move")
	target.notify_move_ap_cost_paid({})
	_expect(target.get_move_ap_cost(1, (f.c as BattleController).config) == before, "water surcharge is consumed after payment")


func _test_air_moves_away_once() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var c := f.c as BattleController
	var unit := f.u as BattleUnitState
	var target := f.enemy as BattleUnitState
	var before := c.map_data.get_distance(unit.cell, target.cell)
	var rules := DruidElementRules.new()
	rules.setup(c)
	rules.resolve_after_strike(unit, target, {"druid_element": BattleSurfaceState.Element.AIR})
	_expect(c.map_data.get_distance(unit.cell, target.cell) == before + 1, "air pushes target one cell away")


func _test_extra_earth_is_independent() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var unit := f.u as BattleUnitState
	var before := unit.get_armor_stacks()
	var rules := DruidElementRules.new()
	rules.setup(f.c as BattleController)
	rules.resolve_after_strike(unit, f.enemy as BattleUnitState, {"druid_element": BattleSurfaceState.Element.EARTH, "druid_extra_earth": true})
	_expect(unit.get_armor_stacks() == before + 6, "extra earth grants a second three armor once")


func _test_dual_weapon_strike_resolves_element_once() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var c := f.c as BattleController
	var unit := f.u as BattleUnitState
	unit.character_state.weapon_equipment = load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	unit.character_state.weapon_face = 0
	unit.equipment_runtime_states.clear()
	var before := unit.get_armor_stacks()
	c.perform_strike_with_options(unit, f.enemy as BattleUnitState, null, 0, 1.0, "dual earth", "weapon", {"druid_element": BattleSurfaceState.Element.EARTH})
	_expect(unit.get_armor_stacks() == before + 3, "dual weapon strike resolves earth once across both damage segments")


func _test_explicit_extra_earth_propagates_through_strike() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var c := f.c as BattleController
	var unit := f.u as BattleUnitState
	var before := unit.get_armor_stacks()
	c.perform_strike_with_options(unit, f.enemy as BattleUnitState, null, 0, 1.0, "explicit extra earth", "weapon", {
		"druid_element": BattleSurfaceState.Element.EARTH,
		"druid_extra_earth": true,
	})
	_expect(unit.get_armor_stacks() == before + 6, "explicit extra earth survives strike context snapshot")


func _test_protection_keeps_positive_blaze_and_blocks_negative_surface_modifiers() -> void:
	var f := DruidExpansionFixture.make("druid_wild_shape", false)
	if f.is_empty(): return
	var c := f.c as BattleController
	var unit := f.u as BattleUnitState
	var wander := CardData.new()
	wander.effect = SurfaceProtectionEffect.new()
	unit.mana_zone.append(wander)
	c.surface_state.create_advanced_surface(unit.cell, BattleSurfaceState.Element.POISON_BOG, 1)
	c.surface_state.create_advanced_surface(unit.cell, BattleSurfaceState.Element.BLAZE, 1)
	_expect(c.get_surface_damage_bonus(unit) == 2, "protection blocks poison penalty but keeps blaze bonus")
	c.surface_state.create_advanced_surface(unit.cell, BattleSurfaceState.Element.ICE, 1)
	c.surface_state.create_advanced_surface(unit.cell, BattleSurfaceState.Element.STEAM, 1)
	_expect(c.get_surface_damage_reduction(unit, {"damage_context": _ranged_damage_context(c, unit)}) == 1, "protection skips ice penalty but keeps steam bonus")


func _ranged_damage_context(controller: BattleController, unit: BattleUnitState) -> DamageContext:
	var context := DamageContext.create(controller, null, unit, 1, "diagnostic")
	context.metadata["range_type"] = EquipmentData.WeaponRangeType.RANGED
	return context


func _test_surface_entry_protection_does_not_block_direct_damage() -> void:
	var protected_fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	var ordinary_fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	if protected_fixture.is_empty() or ordinary_fixture.is_empty(): return
	var protected_controller := protected_fixture.c as BattleController
	var protected_unit := protected_fixture.u as BattleUnitState
	var ordinary_controller := ordinary_fixture.c as BattleController
	var ordinary_unit := ordinary_fixture.u as BattleUnitState
	var wander := CardData.new()
	wander.effect = SurfaceProtectionEffect.new()
	protected_unit.mana_zone.append(wander)
	var next := Vector2i(3, 4)
	protected_controller.surface_state.create_advanced_surface(next, BattleSurfaceState.Element.LAVA, 1)
	ordinary_controller.surface_state.create_advanced_surface(next, BattleSurfaceState.Element.LAVA, 1)
	var protected_before := protected_unit.get_current_health()
	var ordinary_before := ordinary_unit.get_current_health()
	protected_controller.process_surface_entry(protected_unit, next)
	ordinary_controller.process_surface_entry(ordinary_unit, next)
	_expect(protected_unit.get_current_health() == protected_before, "protection blocks lava surface entry damage")
	_expect(ordinary_unit.get_current_health() == ordinary_before - 3, "ordinary unit takes lava surface entry damage")
	protected_controller.surface_state.create_advanced_surface(next, BattleSurfaceState.Element.ICE, 1)
	_expect(not protected_controller.process_surface_entry(protected_unit, next), "protection ignores ice stopping entry")
	protected_before = protected_unit.get_current_health()
	protected_controller.apply_damage(null, protected_unit, 2, "direct fixed", {"environmental": true, "fixed_damage": true})
	_expect(protected_unit.get_current_health() == protected_before - 2, "protection does not block direct environmental fixed damage")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_ELEMENT_RULES FAILURE: %s" % message)
