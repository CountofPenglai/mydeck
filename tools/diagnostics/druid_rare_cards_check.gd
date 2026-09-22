extends Node

var _exit_code := 0

class KillAfterStrikeStatus extends StatusEffect:
	func _init() -> void:
		status_id = "diagnostic_kill_after_strike"
		display_name = "diagnostic kill"
	func on_after_strike(_unit: BattleUnitState, context: Dictionary = {}) -> void:
		var controller := context.get("controller") as BattleController
		var target := context.get("target") as BattleUnitState
		if controller != null and target != null:
			controller.apply_damage(null, target, 999, "diagnostic attached lethal", {"fixed_damage": true})

class MoveAfterStrikeStatus extends StatusEffect:
	func _init() -> void:
		status_id = "diagnostic_move_after_strike"
		display_name = "diagnostic move"
	func on_after_strike(_unit: BattleUnitState, context: Dictionary = {}) -> void:
		var controller := context.get("controller") as BattleController
		var target := context.get("target") as BattleUnitState
		if controller != null and target != null:
			controller.apply_card_movement_to_cell(target, Vector2i(0, 0), "diagnostic attached move")


func _ready() -> void:
	_test_spirit_pact_armor_option()
	_test_element_invocation_requires_element_choice()
	_test_inverted_invocation_consumes_own_charge_in_card_frame()
	_test_resonance_payment_failure_preserves_ap()
	_test_source_turn_and_death_clear_snapshot_charge()
	_test_automatic_strike_ignores_undeployed_and_out_of_range_units()
	_test_preplay_specs_expose_every_option()
	_test_assist_refresh_preserves_used_turn_opportunity()
	_test_rooted_ally_basic_attack_consumes_assist_once()
	_test_rooted_query_is_global_and_invocation_stays_friendly()
	_test_pact_draw_and_automatic_lifesteal()
	_test_charge_snapshot_persists_after_root_loss_and_latest_overwrites()
	_test_attached_lethal_skips_assist_without_consuming_chance()
	_test_dual_wield_consumes_one_charge_once()
	_test_assist_refreshes_on_next_character_turn()
	_test_surface_lethal_skips_later_invocation_strike()
	_test_attached_move_out_of_range_skips_assist()
	_test_two_sources_each_assist_once_without_recursion()
	_test_spirit_pact_upright_range_is_fixed_while_inverted_uses_weapon_range()
	await _test_preplay_panel_confirm_and_cancel()
	await _test_scene_uses_actual_inverse_face_for_preplay()
	print("DRUID_RARE_CARDS: completed")
	get_tree().quit(_exit_code)


# Catches an upright Spirit Pact implementation that omits the fixed six-armor option.
func _test_spirit_pact_armor_option() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", false)
	_expect(not f.is_empty(), "spirit pact fixture is available")
	if f.is_empty():
		return
	_expect((f.c as BattleController).play_card(f.u, f.card, [f.u], {"choice_indices": [2]}), "pact armor option")
	_expect((f.u as BattleUnitState).get_armor_stacks() == 6, "pact armor equals six")


# Catches an Invocation implementation that accepts no selected base element.
func _test_element_invocation_requires_element_choice() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", false)
	_expect(not f.is_empty(), "element invocation fixture is available")
	if f.is_empty():
		return
	_expect(not (f.c as BattleController).play_card(f.u, f.card, [f.enemy], {"choice_indices": [1]}), "invocation rejects a missing selected element")


# Catches a queued charge hook: the inverted card grants its owner a charge
# before its strike, so its own active card frame must consume it immediately.
func _test_inverted_invocation_consumes_own_charge_in_card_frame() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", true)
	_expect(not f.is_empty(), "inverted invocation fixture is available")
	if f.is_empty():
		return
	var unit := f.u as BattleUnitState
	var target := f.enemy as BattleUnitState
	_expect((f.c as BattleController).play_card(unit, f.card, [target], {"selected_element": BattleSurfaceState.Element.FIRE}), "inverted invocation plays")
	_expect(target.has_status("ranger_burn") and not unit.has_status("druid_element_charge"), "inverted invocation applies and consumes its own fire charge in the active frame")


# Catches optional-resonance validation that spends AP before discovering mana is absent.
func _test_resonance_payment_failure_preserves_ap() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", false)
	if f.is_empty():
		return
	var unit := f.u as BattleUnitState
	var before := unit.current_ap
	_expect(not (f.c as BattleController).play_card(unit, f.card, [unit], {"choice_indices": [0, 2], "pay_resonance": true}), "unpayable pact resonance is rejected")
	_expect(unit.current_ap == before, "unpayable pact resonance consumes no AP")


# Catches expiry tied to the recipient's turn, or source-bound effects surviving
# their source's actual death.
func _test_source_turn_and_death_clear_snapshot_charge() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", true)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	if ally == null:
		_expect(false, "fixture supplies a second player")
		return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [f.enemy], {"selected_element": BattleSurfaceState.Element.WATER}), "inverted invocation grants an ally snapshot charge")
	_expect(ally.has_status("druid_element_charge"), "rooted ally receives charge")
	controller._resolve_turn_start_action(source)
	_expect(not ally.has_status("druid_element_charge"), "source next turn expires ally charge before turn benefits")
	var charge := DruidElementChargeStatus.new()
	charge.source_unit_id = source.unit_id
	charge.expires_on_source_turn = source.turn_serial + 9
	ally.add_status(charge)
	source.set_current_health(1)
	controller.apply_damage(null, source, 99, "diagnostic lethal", {"fixed_damage": true})
	_expect(not ally.has_status("druid_element_charge"), "source death clears unexpired snapshot charge")


# Catches auto-targeting code that sees undeployed reserve units or returns a
# target which the owner cannot legally strike.
func _test_automatic_strike_ignores_undeployed_and_out_of_range_units() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", false)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var enemy := f.enemy as BattleUnitState
	enemy.is_deployed = false
	_expect(controller.druid_battle_rules.get_automatic_strike(f.u as BattleUnitState).is_empty(), "automatic strike ignores undeployed enemies")
	enemy.is_deployed = true
	enemy.set_hex_cell(Vector2i(0, 0), controller.map_data)
	_expect(controller.druid_battle_rules.get_automatic_strike(f.u as BattleUnitState).is_empty(), "automatic strike returns empty when every enemy is out of range")


# Catches a UI adapter that collapses optional resonance choices back to one
# opaque string and makes legitimate combinations unreachable.
func _test_preplay_specs_expose_every_option() -> void:
	var pact := load("res://resources/cards/druid_spirit_pact.tres") as CardData
	var invocation := load("res://resources/cards/druid_element_invocation.tres") as CardData
	var pact_spec := pact.get_preplay_configuration({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT})
	var invocation_spec := invocation.get_preplay_configuration({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT})
	_expect((pact_spec.get("options", []) as Array).size() == 3 and int(pact_spec.get("maximum", 0)) == 3, "pact preplay exposes all three independently selectable options")
	_expect((invocation_spec.get("options", []) as Array).size() == 2 and bool(invocation_spec.get("requires_element", false)), "invocation preplay exposes both options plus an element selector")


# Catches duplicate 协猎 refreshes which reset an opportunity already spent in
# the current global character turn.
func _test_assist_refresh_preserves_used_turn_opportunity() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	if ally == null:
		_expect(false, "fixture supplies an assist ally")
		return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [f.enemy]), "first assist card plays")
	var original := source.get_status("druid_assist") as DruidAssistStatus
	_expect(original != null, "first assist status exists")
	if original == null:
		return
	original.last_used_active_turn_serial = controller.active_turn_serial
	var duplicate := (f.card as CardData).duplicate(true) as CardData
	source.hand.append(duplicate)
	source.current_ap = 10
	_expect(controller.play_card(source, duplicate, [f.enemy]), "duplicate assist card plays")
	var refreshed := source.get_status("druid_assist") as DruidAssistStatus
	_expect(refreshed != null and refreshed.last_used_active_turn_serial == controller.active_turn_serial, "duplicate assist refresh does not reset used opportunity")


# Catches assist observers that resolve recursively, or consume their once-per-
# character-turn chance before the legal assist has actually resolved.
func _test_rooted_ally_basic_attack_consumes_assist_once() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	var target := f.enemy as BattleUnitState
	if ally == null:
		_expect(false, "fixture supplies rooted assist ally")
		return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	target.set_current_health(target.get_max_health())
	_expect(controller.play_card(source, f.card, [target]), "assist card establishes status")
	var status := source.get_status("druid_assist") as DruidAssistStatus
	if status == null:
		_expect(false, "assist status is installed after initial strike")
		return
	controller.current_unit = ally
	ally.current_ap = 10
	_expect(controller.basic_attack(ally, target), "rooted ally basic attack resolves")
	_expect(status.last_used_active_turn_serial == controller.active_turn_serial, "legal queued assist consumes exactly this character-turn opportunity")


func _test_rooted_query_is_global_and_invocation_stays_friendly() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var enemy := f.enemy as BattleUnitState
	enemy.add_status(DruidRootStatus.new())
	var roots := controller.druid_battle_rules.get_rooted_units(f.u as BattleUnitState)
	_expect(roots.has(enemy), "shared rooted query includes deployed rooted enemies")
	_expect(controller.play_card(f.u, f.card, [enemy], {"selected_element": BattleSurfaceState.Element.FIRE}), "inverted invocation plays for friendly snapshot check")
	_expect(not enemy.has_status("druid_element_charge"), "invocation filters global rooted query to friendly beneficiaries")


func _test_pact_draw_and_automatic_lifesteal() -> void:
	var draw_fixture := DruidExpansionFixture.make("druid_spirit_pact", false)
	if draw_fixture.is_empty(): return
	var draw_unit := draw_fixture.u as BattleUnitState
	var first := CardData.new()
	var second := CardData.new()
	draw_unit.draw_pile.append_array([first, second])
	_expect((draw_fixture.c as BattleController).play_card(draw_unit, draw_fixture.card, [draw_unit], {"choice_indices": [0]}), "pact draw option plays")
	_expect(draw_unit.hand.has(first) and draw_unit.hand.has(second), "pact draw option draws exactly the live top cards")
	var life_fixture := DruidExpansionFixture.make("druid_spirit_pact", false)
	if life_fixture.is_empty(): return
	var life_unit := life_fixture.u as BattleUnitState
	life_unit.set_current_health(life_unit.get_max_health() - 6)
	var before := life_unit.get_current_health()
	_expect((life_fixture.c as BattleController).play_card(life_unit, life_fixture.card, [life_unit], {"choice_indices": [1]}), "pact automatic lifesteal option plays")
	_expect(life_unit.get_current_health() > before, "pact automatic lifesteal restores the actual striker")


func _test_charge_snapshot_persists_after_root_loss_and_latest_overwrites() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	if ally == null: return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [f.enemy], {"selected_element": BattleSurfaceState.Element.FIRE}), "first snapshot charge plays")
	ally.remove_status("druid_root")
	_expect(ally.has_status("druid_element_charge"), "snapshot charge survives later root loss")
	var late_root := _other_player(controller, ally)
	if late_root != null and late_root != source:
		late_root.is_deployed = true
		late_root.add_status(DruidRootStatus.new())
		_expect(not late_root.has_status("druid_element_charge"), "later root gain does not receive an old snapshot")
	var duplicate := (f.card as CardData).duplicate(true) as CardData
	source.hand.append(duplicate)
	source.current_ap = 10
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, duplicate, [f.enemy], {"selected_element": BattleSurfaceState.Element.WATER}), "latest invocation plays")
	var charge := ally.get_status("druid_element_charge") as DruidElementChargeStatus
	_expect(charge != null and charge.element == BattleSurfaceState.Element.WATER, "latest charge replaces prior element rather than stacking")


func _test_attached_lethal_skips_assist_without_consuming_chance() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	var target := f.enemy as BattleUnitState
	if ally == null: return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [target]), "assist source card plays before attached lethal")
	var assist := source.get_status("druid_assist") as DruidAssistStatus
	target.set_current_health(target.get_max_health())
	ally.add_status(KillAfterStrikeStatus.new())
	controller.current_unit = ally
	ally.current_ap = 10
	_expect(controller.basic_attack(ally, target), "ally strike with queued attached lethal plays")
	_expect(not target.is_alive() and assist != null and assist.last_used_active_turn_serial != controller.active_turn_serial, "target killed by attached effect skips assist without consuming chance")


func _test_dual_wield_consumes_one_charge_once() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", false)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var unit := f.u as BattleUnitState
	unit.character_state.weapon_equipment = load("res://resources/items/iron_rock_pair.tres") as EquipmentData
	unit.character_state.weapon_face = 0
	unit.equipment_runtime_states.clear()
	var charge := DruidElementChargeStatus.new()
	charge.source_unit_id = unit.unit_id
	charge.expires_on_source_turn = unit.turn_serial + 1
	charge.element = BattleSurfaceState.Element.EARTH
	unit.add_status(charge)
	var before := unit.get_armor_stacks()
	controller.perform_strike(unit, f.enemy as BattleUnitState, null, "dual charge")
	_expect(unit.get_armor_stacks() == before + 3 and not unit.has_status("druid_element_charge"), "dual wield consumes one earth charge and resolves its element once")


func _test_assist_refreshes_on_next_character_turn() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	var target := f.enemy as BattleUnitState
	if ally == null: return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [target]), "assist setup plays for turn refresh")
	var assist := source.get_status("druid_assist") as DruidAssistStatus
	controller.current_unit = ally
	ally.current_ap = 10
	_expect(controller.basic_attack(ally, target), "first character turn attack plays")
	var used_serial := assist.last_used_active_turn_serial if assist != null else -1
	controller.active_turn_serial += 1
	target.set_current_health(target.get_max_health())
	ally.current_ap = 10
	_expect(controller.basic_attack(ally, target), "next character turn attack plays")
	_expect(assist != null and assist.last_used_active_turn_serial == used_serial + 1, "any new character turn refreshes assist opportunity without extending duration")


func _test_surface_lethal_skips_later_invocation_strike() -> void:
	var f := DruidExpansionFixture.make("druid_element_invocation", false)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var target := f.enemy as BattleUnitState
	target.set_current_health(3)
	user.gain_mana(1)
	controller.surface_state.set_base_element(target.cell, BattleSurfaceState.Element.FIRE)
	var armor_before := user.get_armor_stacks()
	_expect(controller.play_card(user, f.card, [target], {"choice_indices": [0, 1], "pay_resonance": true, "selected_element": BattleSurfaceState.Element.EARTH, "selected_cell": target.cell}), "resonant invocation surface-plus-strike submits")
	_expect(not target.is_alive() and user.get_armor_stacks() == armor_before, "surface lava kills target before the later earth strike is attempted")


func _test_attached_move_out_of_range_skips_assist() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var source := f.u as BattleUnitState
	var ally := _other_player(controller, source)
	var target := f.enemy as BattleUnitState
	if ally == null: return
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(4, 3), controller.map_data)
	ally.add_status(DruidRootStatus.new())
	_expect(controller.play_card(source, f.card, [target]), "assist setup plays for attached move")
	var assist := source.get_status("druid_assist") as DruidAssistStatus
	target.set_current_health(target.get_max_health())
	ally.add_status(MoveAfterStrikeStatus.new())
	controller.current_unit = ally
	ally.current_ap = 10
	_expect(controller.basic_attack(ally, target), "ally strike with queued attached move plays")
	_expect(target.cell == Vector2i(0, 0) and assist != null and assist.last_used_active_turn_serial != controller.active_turn_serial, "attached movement out of range skips assist without consuming chance")


func _test_two_sources_each_assist_once_without_recursion() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", true)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var first := f.u as BattleUnitState
	var second := _other_player(controller, first)
	var trigger: BattleUnitState = null
	for candidate_value in controller.player_units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate != first and candidate != second:
			trigger = candidate
	if second == null or trigger == null: return
	second.is_deployed = true
	second.set_hex_cell(Vector2i(5, 3), controller.map_data)
	trigger.is_deployed = true
	trigger.set_hex_cell(Vector2i(4, 3), controller.map_data)
	trigger.add_status(DruidRootStatus.new())
	_expect(controller.play_card(first, f.card, [f.enemy]), "first assist source plays")
	var first_status := first.get_status("druid_assist") as DruidAssistStatus
	var second_status := DruidAssistStatus.new()
	second_status.source_unit_id = second.unit_id
	second_status.expires_on_source_turn = second.turn_serial + 1
	second.add_status(second_status)
	controller.active_turn_serial += 1
	controller.current_unit = trigger
	trigger.current_ap = 10
	(f.enemy as BattleUnitState).set_current_health((f.enemy as BattleUnitState).get_max_health())
	_expect(controller.basic_attack(trigger, f.enemy as BattleUnitState), "rooted trigger attacks for two sources")
	_expect(first_status != null and first_status.last_used_active_turn_serial == controller.active_turn_serial and second_status.last_used_active_turn_serial == controller.active_turn_serial, "different assist sources each resolve once while assist contexts do not recurse")


# Catches upright Pact inheriting a long weapon's range rather than its printed
# range 2, while ensuring inverted Pact still uses that weapon range.
func _test_spirit_pact_upright_range_is_fixed_while_inverted_uses_weapon_range() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_pact", false)
	if f.is_empty(): return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var ally := _other_player(controller, user)
	if ally == null: return
	user.character_state.weapon_equipment = load("res://resources/items/druid_star_firefly.tres") as EquipmentData
	user.equipment_runtime_states.clear()
	ally.is_deployed = true
	ally.set_hex_cell(Vector2i(1, 4), controller.map_data)
	var ap_before := user.current_ap
	_expect(not controller.play_card(user, f.card, [ally], {"choice_indices": [2]}), "upright pact rejects a friendly target at distance three despite long weapon")
	_expect(user.current_ap == ap_before and user.hand.has(f.card), "upright out-of-range rejection consumes neither AP nor card")
	var near := DruidExpansionFixture.make("druid_spirit_pact", false)
	if near.is_empty(): return
	var near_user := near.u as BattleUnitState
	var near_ally := _other_player(near.c as BattleController, near_user)
	if near_ally == null: return
	near_user.character_state.weapon_equipment = load("res://resources/items/druid_star_firefly.tres") as EquipmentData
	near_user.equipment_runtime_states.clear()
	near_ally.is_deployed = true
	near_ally.set_hex_cell(Vector2i(2, 4), (near.c as BattleController).map_data)
	_expect((near.c as BattleController).play_card(near_user, near.card, [near_ally], {"choice_indices": [2]}), "upright pact accepts a friendly target at fixed distance two")
	var inverted := DruidExpansionFixture.make("druid_spirit_pact", true)
	if inverted.is_empty(): return
	var inverted_user := inverted.u as BattleUnitState
	inverted_user.character_state.weapon_equipment = load("res://resources/items/druid_star_firefly.tres") as EquipmentData
	inverted_user.equipment_runtime_states.clear()
	(inverted.enemy as BattleUnitState).set_hex_cell(Vector2i(1, 4), (inverted.c as BattleController).map_data)
	_expect((inverted.c as BattleController).play_card(inverted_user, inverted.card, [inverted.enemy]), "inverted pact still accepts distance three through its weapon range")


func _test_preplay_panel_confirm_and_cancel() -> void:
	var panel := BattlePreplayPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var observed := {"confirmed": {}, "cancelled": false}
	panel.configuration_confirmed.connect(func(configuration: Dictionary) -> void: observed["confirmed"] = configuration)
	panel.configuration_cancelled.connect(func() -> void: observed["cancelled"] = true)
	panel.show_configuration({"title": "diagnostic", "options": ["one", "two"], "minimum": 1, "maximum": 2, "resonance_cost": 1, "requires_element": true})
	panel._on_option_toggled(true, 0)
	panel._on_option_toggled(true, 1)
	panel._resonance = true
	panel._element = BattleSurfaceState.Element.EARTH
	panel._submit()
	var confirmed: Dictionary = observed["confirmed"] as Dictionary
	_expect(confirmed.get("choice_indices", []) == [0, 1] and int(confirmed.get("selected_element", -1)) == BattleSurfaceState.Element.EARTH and bool(confirmed.get("pay_resonance", false)), "preplay panel emits independent multi-option, element, and resonance values")
	panel.show_configuration({"title": "cancel", "options": [], "minimum": 0, "maximum": 0})
	panel._cancel()
	_expect(bool(observed["cancelled"]), "preplay panel exposes a cancel signal without submitting configuration")
	panel.queue_free()


func _test_scene_uses_actual_inverse_face_for_preplay() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var user: BattleUnitState = null
	for value in scene.controller.player_units:
		var candidate := value as BattleUnitState
		if candidate != null and candidate.is_druid(): user = candidate
	_expect(user != null, "scene supplies a druid for inverse preplay")
	if user == null:
		scene.queue_free()
		return
	scene.controller.current_unit = user
	user.set_druid_transformed(true)
	var pact := load("res://resources/cards/druid_spirit_pact.tres") as CardData
	var invocation := load("res://resources/cards/druid_element_invocation.tres") as CardData
	_expect(not scene._needs_preplay_configuration(pact, CardEnums.CardPlayMode.NORMAL), "inverse pact does not open upright configuration")
	_expect(scene._needs_preplay_configuration(invocation, CardEnums.CardPlayMode.NORMAL), "inverse invocation opens element configuration")
	scene._show_preplay_configuration(invocation, CardEnums.CardPlayMode.NORMAL)
	_expect(_find_label(scene._preplay_panel, "赋灵") != null, "inverse invocation renders inverse configuration")
	scene.queue_free()


func _find_label(root: Node, text_fragment: String) -> Label:
	if root is Label and (root as Label).text.contains(text_fragment): return root as Label
	for child in root.get_children():
		var found := _find_label(child, text_fragment)
		if found != null: return found
	return null


func _other_player(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for candidate_value in controller.player_units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate != excluded:
			return candidate
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_RARE_CARDS FAILURE: %s" % message)
