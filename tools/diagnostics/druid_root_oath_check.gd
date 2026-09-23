extends Node


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")

var _exit_code := 0


class RescueBeforeDeathStatus extends StatusEffect:
	func _init() -> void:
		status_id = "root_oath_diagnostic_rescue"

	func get_lethal_health_floor(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
		return 1


func _ready() -> void:
	_test_upright_snapshots_and_refreshes_team_benefits()
	_test_upright_source_turn_and_death_clear_team_status()
	_test_inverse_dynamic_values_and_nonweapon_isolation()
	_test_inverse_actual_single_and_dual_weapon_damage()
	_test_inverse_actual_object_weapon_damage_and_preview_nonconsumption()
	_test_oath_weapon_profiles_exclude_unarmed_and_restore_on_equip()
	_test_inverse_regular_mana_entry_has_no_incarnation_effect()
	_test_inverse_deduplicates_and_stops_on_enchant_departure()
	print("DRUID_ROOT_OATH: completed")
	get_tree().quit(_exit_code)


# Removing the root -> transform -> snapshot ordering, or turning this into a
# live root watcher, must fail these observed card-play outcomes.
func _test_upright_snapshots_and_refreshes_team_benefits() -> void:
	var f := DruidExpansionFixture.make("druid_root_oath", false)
	_expect(not f.is_empty(), "root oath fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var ally := _other_player(controller, user)
	_expect(ally != null, "fixture provides another friendly recipient")
	if ally == null:
		return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(ROOT_STATUS.new())
	var user_armor := user.get_armor_stacks()
	var ally_armor := ally.get_armor_stacks()
	_expect(controller.play_card(user, f.card as CardData, []), "upright root oath plays")
	_expect(user.has_status("druid_root") and user.druid_transformed, "upright first roots and transforms its owner")
	_expect(user.get_armor_stacks() == user_armor + 4 and ally.get_armor_stacks() == ally_armor + 4, "owner and existing rooted friendly each gain four armor")
	_expect(user.has_status("druid_root_oath") and ally.has_status("druid_root_oath"), "rooted recipients hold the source-bound +2 weapon status")
	var late_ally := _other_player_excluding(controller, [user, ally])
	if late_ally != null:
		late_ally.is_deployed = true
		late_ally.add_status(ROOT_STATUS.new())
		_expect(not late_ally.has_status("druid_root_oath"), "a friendly rooted after resolution does not receive the snapshot benefit")
	user.remove_status("druid_root")
	_expect(user.has_status("druid_root_oath"), "losing root later does not revoke an already-issued upright status")
	var duplicate := (load("res://resources/cards/druid_root_oath.tres") as CardData).duplicate(true) as CardData
	user.set_druid_transformed(false)
	user.hand.append(duplicate)
	user.current_ap = 10
	var before_refresh_armor := user.get_armor_stacks()
	_expect(controller.play_card(user, duplicate, []), "duplicate upright oath plays")
	var active_status := user.get_status("druid_root_oath") as DruidRootOathStatus
	_expect(user.get_armor_stacks() == before_refresh_armor + 4 and active_status != null and active_status.stacks == 2, "same-name oath refreshes +2 rather than stacking while still granting armor")


# Deleting the source-relative lifecycle handling must fail both the actual
# source next-turn expiry and actual post-rescue lethal cleanup boundary.
func _test_upright_source_turn_and_death_clear_team_status() -> void:
	var f := DruidExpansionFixture.make("druid_root_oath", false)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var ally := _other_player(controller, user)
	if ally == null:
		_expect(false, "fixture provides an expiry recipient")
		return
	ally.is_deployed = true
	ally.add_status(ROOT_STATUS.new())
	_expect(controller.play_card(user, f.card as CardData, []), "upright oath establishes source status")
	_expect(ally.has_status("druid_root_oath"), "rooted ally received a source status")
	controller._resolve_turn_start_action(user)
	_expect(not ally.has_status("druid_root_oath"), "source next turn expires ally benefit before turn effects")
	var persistent := DruidRootOathStatus.new()
	persistent.source_unit_id = user.unit_id
	persistent.expires_on_source_turn = user.turn_serial + 9
	ally.add_status(persistent)
	var rescue := RescueBeforeDeathStatus.new()
	user.add_status(rescue)
	user.set_current_health(1)
	controller.apply_damage(null, user, 99, "root oath diagnostic rescued lethal", {"fixed_damage": true})
	_expect(user.is_alive() and ally.has_status("druid_root_oath"), "rescue before death leaves source and its team status intact")
	user.remove_status(rescue.status_id)
	controller.apply_damage(null, user, 99, "root oath diagnostic lethal", {"fixed_damage": true})
	_expect(not ally.has_status("druid_root_oath"), "actual source death clears unexpired team benefit")


# Replacing dynamic root reads with an entry snapshot, applying the bonus to
# non-strike damage, or reducing fixed damage must fail these literal values.
func _test_inverse_dynamic_values_and_nonweapon_isolation() -> void:
	var f := _inverse_fixture()
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var effect := (f.card as CardData).effect as DruidRootOathCardEffect
	_expect(effect != null and user.enchant_zone.has(f.card as CardData), "inverse play enters the enchant zone")
	# The fixture starts transformed to select the inverse face; restore form so
	# these incoming-damage literals isolate incarnation from base form reduction.
	user.set_druid_transformed(false)
	_expect(effect.get_incarnation_bonus(user, {"strike": true}) == 4 and effect.get_incarnation_bonus(user, {}) == 0, "no self root is +4 only for a strike")
	_expect(_incoming_damage(controller, f.enemy as BattleUnitState, user, false) == 10, "without self root inverse grants no reduction")
	for wanted_count in [1, 3, 5]:
		_set_root_count(controller, user, wanted_count)
		_expect(effect.get_incarnation_bonus(user, {"strike": true}) == 4 + wanted_count * 2, "root count %d yields its literal dynamic incarnation bonus" % wanted_count)
		_expect(_incoming_damage(controller, f.enemy as BattleUnitState, user, false) == 7, "rooted incarnation reduces ordinary damage by three at count %d" % wanted_count)
		_expect(_incoming_damage(controller, f.enemy as BattleUnitState, user, true) == 10, "rooted incarnation never reduces fixed damage at count %d" % wanted_count)
	_set_root_count(controller, user, 3)
	var target := f.enemy as BattleUnitState
	var before := target.get_current_health()
	controller.apply_damage(user, target, 5, "nonweapon diagnostic", {"resolved_damage_type": CardEnums.DamageType.INTELLIGENCE, "ignore_armor": true})
	_expect(before - target.get_current_health() == 5, "nonweapon card damage does not receive incarnation strike bonus")
	user.remove_status("druid_root")
	_expect(effect.get_incarnation_bonus(user, {"strike": true}) == 4, "removing self root immediately drops conditional bonus")


# This uses real controller hit resolution rather than a helper calculation;
# applying zone bonus per resolver segment would overstate either delta.
func _test_inverse_actual_single_and_dual_weapon_damage() -> void:
	var baseline := DruidExpansionFixture.make("druid_root_oath", true)
	var boosted := _inverse_fixture()
	if baseline.is_empty() or boosted.is_empty():
		return
	var normal := _weapon_damage(baseline, false)
	var enhanced := _weapon_damage(boosted, false)
	_expect(normal > 0 and enhanced - normal == 4, "real single weapon hit gains exactly base +4 without self root")
	var dual_baseline := DruidExpansionFixture.make("druid_root_oath", true)
	var dual_boosted := _inverse_fixture()
	if dual_baseline.is_empty() or dual_boosted.is_empty():
		return
	(dual_baseline.u as BattleUnitState).character_state.weapon_equipment = load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	(dual_boosted.u as BattleUnitState).character_state.weapon_equipment = load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	var dual_normal := _weapon_damage(dual_baseline, true)
	var dual_enhanced := _weapon_damage(dual_boosted, true)
	_expect(dual_normal > 0 and dual_enhanced - dual_normal == 8, "real dual weapon hit gains +4 once per existing weapon segment")


# Object strikes use the same profile bridge as units, while a profile preview
# must remain pure and leave existing next-strike state untouched.
func _test_inverse_actual_object_weapon_damage_and_preview_nonconsumption() -> void:
	var baseline := DruidExpansionFixture.make("druid_root_oath", true)
	var boosted := _inverse_fixture()
	if baseline.is_empty() or boosted.is_empty():
		return
	_expect(_object_weapon_damage(boosted) - _object_weapon_damage(baseline) == 4, "real object weapon hit receives exactly one incarnation base bonus")
	var user := boosted.u as BattleUnitState
	var charge := DruidElementChargeStatus.new()
	charge.element = BattleSurfaceState.Element.EARTH
	user.add_status(charge)
	var profile := user.build_strike_profile_object("weapon", {"controller": boosted.c})
	_expect(profile.primary_damage_bonus >= 4 and user.get_status("druid_element_charge") == charge and charge.stacks == 1, "weapon profile preview includes incarnation without consuming next-strike state")


# Both upright's granted status and inverse's enchant are weapon-only.  These
# execute real unit/object strikes unarmed first, then restore the same weapon
# and demand the durable profile bonus reappear.
func _test_oath_weapon_profiles_exclude_unarmed_and_restore_on_equip() -> void:
	_assert_unarmed_then_equipped_unit_delta(
		DruidExpansionFixture.make("druid_root_oath", true),
		_status_oath_fixture(),
		2,
		"upright oath status"
	)
	_assert_unarmed_then_equipped_object_delta(
		DruidExpansionFixture.make("druid_root_oath", true),
		_status_oath_fixture(),
		2,
		"upright oath status"
	)
	_assert_unarmed_then_equipped_unit_delta(
		DruidExpansionFixture.make("druid_root_oath", true),
		_inverse_fixture(),
		4,
		"inverse incarnation"
	)
	_assert_unarmed_then_equipped_object_delta(
		DruidExpansionFixture.make("druid_root_oath", true),
		_inverse_fixture(),
		4,
		"inverse incarnation"
	)


func _status_oath_fixture() -> Dictionary:
	var f := DruidExpansionFixture.make("druid_root_oath", true)
	if f.is_empty():
		return f
	var user := f.u as BattleUnitState
	var status := DruidRootOathStatus.new()
	status.source_unit_id = user.unit_id
	status.expires_on_source_turn = user.turn_serial + 9
	user.add_status(status)
	return f


func _assert_unarmed_then_equipped_unit_delta(baseline: Dictionary, boosted: Dictionary, expected_delta: int, label: String) -> void:
	if baseline.is_empty() or boosted.is_empty():
		return
	var baseline_user := baseline.u as BattleUnitState
	var boosted_user := boosted.u as BattleUnitState
	var baseline_weapon := baseline_user.character_state.weapon_equipment
	var boosted_weapon := boosted_user.character_state.weapon_equipment
	baseline_user.character_state.weapon_equipment = null
	boosted_user.character_state.weapon_equipment = null
	_expect(_weapon_damage(boosted, false) - _weapon_damage(baseline, false) == 0, "%s gives no real unarmed unit-strike bonus" % label)
	baseline_user.character_state.weapon_equipment = baseline_weapon
	boosted_user.character_state.weapon_equipment = boosted_weapon
	_expect(_weapon_damage(boosted, false) - _weapon_damage(baseline, false) == expected_delta, "%s restores its unit weapon-strike bonus after equipping" % label)


func _assert_unarmed_then_equipped_object_delta(baseline: Dictionary, boosted: Dictionary, expected_delta: int, label: String) -> void:
	if baseline.is_empty() or boosted.is_empty():
		return
	var baseline_user := baseline.u as BattleUnitState
	var boosted_user := boosted.u as BattleUnitState
	var baseline_weapon := baseline_user.character_state.weapon_equipment
	var boosted_weapon := boosted_user.character_state.weapon_equipment
	baseline_user.character_state.weapon_equipment = null
	boosted_user.character_state.weapon_equipment = null
	_expect(_object_weapon_damage(boosted) - _object_weapon_damage(baseline) == 0, "%s gives no real unarmed object-strike bonus" % label)
	baseline_user.character_state.weapon_equipment = baseline_weapon
	boosted_user.character_state.weapon_equipment = boosted_weapon
	_expect(_object_weapon_damage(boosted) - _object_weapon_damage(baseline) == expected_delta, "%s restores its object weapon-strike bonus after equipping" % label)


# The dual face can enter mana through normal preparation, but 荒野化身 is
# explicitly an enchantment.  A mana copy must neither apply it nor reserve
# its same-name deduplication key before a real enchantment is queried.
func _test_inverse_regular_mana_entry_has_no_incarnation_effect() -> void:
	var f := DruidExpansionFixture.make("druid_root_oath", true)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var mana_copy := f.card as CardData
	_expect(user.move_hand_card_to_mana(mana_copy), "ordinary preparation can move the inverse card to mana")
	user.set_druid_transformed(false)
	_expect(user.get_zone_damage_bonus(_weapon_strike_context(user)) == 0 and _incoming_damage(controller, f.enemy as BattleUnitState, user, false) == 10, "mana-zone root oath is not an incarnation enchantment")
	var enchant_copy := (load("res://resources/cards/druid_root_oath.tres") as CardData).duplicate(true) as CardData
	user.add_card_to_enchant_zone(enchant_copy)
	_expect(user.get_zone_damage_bonus(_weapon_strike_context(user)) == 4, "a real enchantment still grants one bonus beside same-name mana copy")


# Distinct duplicated Resources must deduplicate by card identity/name, and a
# card leaving enchant must stop its live query immediately.
func _test_inverse_deduplicates_and_stops_on_enchant_departure() -> void:
	var f := _inverse_fixture()
	if f.is_empty():
		return
	var user := f.u as BattleUnitState
	var card := f.card as CardData
	var duplicate := (load("res://resources/cards/druid_root_oath.tres") as CardData).duplicate(true) as CardData
	user.enchant_zone.append(duplicate)
	_expect(user.get_zone_damage_bonus(_weapon_strike_context(user)) == 4, "duplicated same-name incarnation enchantment does not stack")
	_expect(user.move_enchant_card_to_discard(card), "original incarnation leaves enchant")
	_expect(user.get_zone_damage_bonus(_weapon_strike_context(user)) == 4, "one remaining same-name enchantment still grants one bonus")
	_expect(user.move_enchant_card_to_discard(duplicate), "duplicate incarnation leaves enchant")
	_expect(user.get_zone_damage_bonus(_weapon_strike_context(user)) == 0, "incarnation effect disappears immediately after all copies leave enchant")


func _inverse_fixture() -> Dictionary:
	var f := DruidExpansionFixture.make("druid_root_oath", true)
	if f.is_empty():
		return f
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	_expect(controller.play_card(user, f.card as CardData, []), "inverse root oath plays")
	return f


func _weapon_strike_context(user: BattleUnitState) -> Dictionary:
	return {
		"strike": true,
		"equipment": user.character_state.get_active_weapon_equipment(),
	}


func _set_root_count(controller: BattleController, user: BattleUnitState, count: int) -> void:
	var cells := [Vector2i(4, 4), Vector2i(4, 3), Vector2i(3, 4), Vector2i(5, 4), Vector2i(4, 5)]
	for index in range(controller.units.size()):
		var unit := controller.units[index] as BattleUnitState
		if unit == null:
			continue
		unit.remove_status("druid_root")
		unit.is_deployed = true
		if index < cells.size():
			unit.set_hex_cell(cells[index] as Vector2i, controller.map_data)
	if count <= 0:
		return
	user.add_status(ROOT_STATUS.new())
	var added := 1
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate != user and added < count:
			candidate.add_status(ROOT_STATUS.new())
			added += 1


func _weapon_damage(f: Dictionary, paired: bool) -> int:
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var target := f.enemy as BattleUnitState
	target.enemy_state.fixed_max_health_override = 1000
	target.set_current_health(target.get_max_health())
	if paired:
		user.character_state.weapon_face = 0
	target.set_current_health(target.get_max_health())
	var before := target.get_current_health()
	controller.perform_strike(user, target, null, "root oath weapon", "weapon")
	return before - target.get_current_health()


func _object_weapon_damage(f: Dictionary) -> int:
	var controller := f.c as BattleController
	var target := BattleObjectState.create(991, BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(5, 4))
	target.definition.max_health = 1000
	target.current_health = 1000
	controller.battle_objects.append(target)
	controller.perform_object_strike_with_modifier(f.u as BattleUnitState, target, null, 0, "root oath object", "weapon")
	return 1000 - target.current_health


func _incoming_damage(controller: BattleController, source: BattleUnitState, target: BattleUnitState, fixed: bool) -> int:
	target.set_current_health(target.get_max_health())
	var before := target.get_current_health()
	controller.apply_damage(source, target, 10, "root oath incoming", {"fixed_damage": fixed, "ignore_armor": true})
	return before - target.get_current_health()


func _other_player(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for candidate_value in controller.player_units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate != excluded:
			return candidate
	return null


func _other_player_excluding(controller: BattleController, excluded: Array[BattleUnitState]) -> BattleUnitState:
	for candidate_value in controller.player_units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and not excluded.has(candidate):
			return candidate
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_ROOT_OATH FAILURE: %s" % message)
