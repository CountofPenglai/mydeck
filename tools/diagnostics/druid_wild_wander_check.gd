extends Node


var _exit_code := 0


class OccupyLandingOnEntryEffect extends CardEffect:
	var watched: CardData
	var enemy: BattleUnitState
	var landing := BattleHexGrid.INVALID_CELL
	func on_zone_card_entered_special_zone(_owner: BattleUnitState, _zone_card: CardData, entered_card: CardData, zone_name: String, context: Dictionary = {}) -> void:
		if zone_name == "mana" and entered_card == watched and enemy != null:
			var controller := context.get("controller") as BattleController
			if controller != null:
				controller.enqueue_effect(Callable(self, "_occupy_landing"), [], -200, "diagnostic delayed landing occupant")

	func _occupy_landing() -> void:
		if enemy != null:
			enemy.set_hex_cell(landing, enemy.battle_controller.map_data)


class RemoveEnteredFromManaEffect extends CardEffect:
	var watched: CardData
	func on_zone_card_entered_special_zone(owner: BattleUnitState, _zone_card: CardData, entered_card: CardData, zone_name: String, _context: Dictionary = {}) -> void:
		if zone_name == "mana" and entered_card == watched:
			owner.mana_zone.erase(entered_card)
			owner.add_card_to_discard(entered_card)


func _ready() -> void:
	_test_metadata_and_form_exception()
	_test_upright_enters_mana_before_lava_teleport()
	_test_requires_an_empty_elemental_landing_within_seven()
	_test_entry_descendants_revalidate_destination_and_never_resurrect_card()
	_test_zone_effects_are_identity_based_and_stop_on_exit()
	_test_wander_keeps_enemy_origin_negative_statuses_and_adds_earth_to_fire_strike()
	print("DRUID_WILD_WANDER: completed")
	get_tree().quit(_exit_code)


# This must remain an explicit exception: transformed Druids may pay the
# upright one-AP action, but the inverse twin face is never directly playable.
func _test_metadata_and_form_exception() -> void:
	var f := DruidExpansionFixture.make("druid_wild_wander", true)
	_expect(not f.is_empty(), "wild wander fixture is available")
	if f.is_empty():
		return
	var card := f.card as CardData
	_expect(card.upright_play_ignores_form, "wander is the explicit form exception")
	_expect(card.get_twin_spell_face() == CardEnums.DruidOrientation.INVERTED, "twin tag stays on inverse")
	_expect(not card.allow_inverted_play, "inverse remains unavailable as a normal active play")


# The actual controller entry must precede movement: LAVA proves that mana-zone
# protection is already active when the landing surface is processed.
func _test_upright_enters_mana_before_lava_teleport() -> void:
	var f := DruidExpansionFixture.make("druid_wild_wander", true)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var card := f.card as CardData
	_expect(controller.surface_state.get_readable_elements(user.cell).is_empty(), "transformed upright play starts without an element at its origin")
	var landing := _cell_at_distance(controller, user.cell, 7)
	_expect(landing != BattleHexGrid.INVALID_CELL, "fixture has a valid range-seven cell")
	if landing == BattleHexGrid.INVALID_CELL:
		return
	controller.surface_state.create_advanced_surface(landing, BattleSurfaceState.Element.LAVA, 1)
	var health_before := user.get_current_health()
	var mana_before := user.get_available_mana()
	_expect(controller.play_card(user, card, [landing]), "upright controller play accepts a seven-cell elemental landing")
	_expect(user.cell == landing, "controller path teleports to the selected real cell")
	_expect(user.mana_zone.count(card) == 1 and not user.hand.has(card), "entry commits the one card to mana before finalization")
	_expect(user.get_current_health() == health_before, "mana protection is active before lava entry resolves")
	_expect(user.get_available_mana() == mana_before, "mana-zone entry does not generate immediate mana")
	_expect(user.current_ap == 9 and not controller.resolution_runner.has_pending_hand_card_choice(), "paid upright play spends one AP without opening a free twin retrieval")


func _test_requires_an_empty_elemental_landing_within_seven() -> void:
	var f := DruidExpansionFixture.make("druid_wild_wander", false)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var card := f.card as CardData
	var effect := card.effect
	var context := {"controller": controller, "user": user, "card": card, "druid_orientation": CardEnums.DruidOrientation.UPRIGHT}
	var within_seven := _cell_at_distance(controller, user.cell, 7)
	var out_of_range := _cell_at_distance(controller, user.cell, 8)
	_expect(within_seven != BattleHexGrid.INVALID_CELL and out_of_range != BattleHexGrid.INVALID_CELL, "fixture has range-seven and range-eight cells")
	if within_seven == BattleHexGrid.INVALID_CELL or out_of_range == BattleHexGrid.INVALID_CELL:
		return
	controller.apply_base_surface_element(within_seven, BattleSurfaceState.Element.FIRE)
	controller.apply_base_surface_element(out_of_range, BattleSurfaceState.Element.FIRE)
	controller.apply_base_surface_element(user.cell, BattleSurfaceState.Element.FIRE)
	_expect(effect != null and effect.get_area_target_cells(context).has(within_seven), "cell-selection UI exposes a legal elemental landing at range seven")
	_expect(effect != null and not effect.get_area_target_cells(context).has(out_of_range), "cell-selection UI excludes an elemental landing at range eight")
	_expect(effect != null and not effect.get_area_target_cells(context).has(user.cell), "cell-selection UI excludes the occupied origin even when it has an element")
	var ap_before := user.current_ap
	_expect(not controller.play_card(user, card, [out_of_range]), "controller rejects range-eight landing")
	_expect(user.current_ap == ap_before and user.hand.has(card), "rejected range-eight landing spends no AP or card")
	_expect(not controller.play_card(user, card, [user.cell]), "controller rejects the occupied origin as a teleport landing")
	_expect(user.current_ap == ap_before and user.hand.has(card), "occupied origin spends no AP or card")
	var enemy := f.enemy as BattleUnitState
	enemy.set_hex_cell(within_seven, controller.map_data)
	_expect(not controller.play_card(user, card, [within_seven]), "controller rejects an occupied elemental landing")
	_expect(user.current_ap == ap_before and user.hand.has(card), "occupied landing spends no AP or card")


func _test_entry_descendants_revalidate_destination_and_never_resurrect_card() -> void:
	var blocked_fixture := DruidExpansionFixture.make("druid_wild_wander", false)
	if blocked_fixture.is_empty():
		return
	var blocked_controller := blocked_fixture.c as BattleController
	var blocked_user := blocked_fixture.u as BattleUnitState
	var blocked_card := blocked_fixture.card as CardData
	var blocked_landing := _cell_at_distance(blocked_controller, blocked_user.cell, 7)
	blocked_controller.apply_base_surface_element(blocked_landing, BattleSurfaceState.Element.FIRE)
	var blocker := CardData.new()
	var blocker_effect := OccupyLandingOnEntryEffect.new()
	blocker_effect.watched = blocked_card
	blocker_effect.enemy = blocked_fixture.enemy as BattleUnitState
	blocker_effect.landing = blocked_landing
	blocker.effect = blocker_effect
	blocked_user.mana_zone.append(blocker)
	var start := blocked_user.cell
	_expect(blocked_controller.play_card(blocked_user, blocked_card, [blocked_landing]), "entry starts before its queued destination recheck")
	_expect(blocked_user.cell == start and blocked_user.mana_zone.has(blocked_card), "entry descendant occupying the landing cancels teleport without undoing mana entry")

	var relocated_fixture := DruidExpansionFixture.make("druid_wild_wander", false)
	if relocated_fixture.is_empty():
		return
	var relocated_controller := relocated_fixture.c as BattleController
	var relocated_user := relocated_fixture.u as BattleUnitState
	var relocated_card := relocated_fixture.card as CardData
	var relocated_landing := _cell_at_distance(relocated_controller, relocated_user.cell, 7)
	relocated_controller.apply_base_surface_element(relocated_landing, BattleSurfaceState.Element.FIRE)
	var relocator := CardData.new()
	var relocator_effect := RemoveEnteredFromManaEffect.new()
	relocator_effect.watched = relocated_card
	relocator.effect = relocator_effect
	relocated_user.mana_zone.append(relocator)
	_expect(relocated_controller.play_card(relocated_user, relocated_card, [relocated_landing]), "entry starts before a queued source relocation")
	_expect(not relocated_user.mana_zone.has(relocated_card) and relocated_user.discard_pile.has(relocated_card), "finalization neither duplicates nor resurrects a source relocated by its entry descendant")


func _test_zone_effects_are_identity_based_and_stop_on_exit() -> void:
	var f := DruidExpansionFixture.make("druid_wild_wander", false)
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var first := f.card as CardData
	var second := first.duplicate(true) as CardData
	user.hand.append(second)
	_expect(user.move_hand_card_to_mana(first, {"controller": controller}), "first wander enters mana")
	_expect(user.move_hand_card_to_mana(second, {"controller": controller}), "second wander enters mana")
	_expect(controller.druid_element_rules.is_surface_protected(user), "one or more matching mana effects protect against negative surfaces")
	var armor_before := user.get_armor_stacks()
	controller.perform_strike_with_options(user, f.enemy as BattleUnitState, null, 0, 1.0, "wander earth", "weapon", {"druid_element": BattleSurfaceState.Element.NONE})
	_expect(user.get_armor_stacks() == armor_before + 3, "two same-name mana copies grant one extra earth trigger")
	var mana_before := user.get_available_mana()
	_expect(DruidTurnRules.resolve_turn_start(user, {"controller": controller}) == 2 and user.get_available_mana() == mana_before + 2, "each same-name mana card still produces ordinary mana independently")
	user.mana_zone.erase(first)
	user.mana_zone.erase(second)
	_expect(not controller.druid_element_rules.is_surface_protected(user), "protection stops immediately when the effect cards leave mana")
	var beast_fixture := DruidExpansionFixture.make("druid_wild_wander", true)
	if beast_fixture.is_empty():
		return
	var beast := beast_fixture.u as BattleUnitState
	var beast_card := beast_fixture.card as CardData
	_expect(beast.move_hand_card_to_mana(beast_card), "beast-form copy enters mana")
	_expect((beast_fixture.c as BattleController).druid_element_rules.is_surface_protected(beast) and (beast_fixture.c as BattleController).druid_element_rules.has_extra_earth(beast), "protection and extra earth work in beast form")


func _test_wander_keeps_enemy_origin_negative_statuses_and_adds_earth_to_fire_strike() -> void:
	var status_fixture := DruidExpansionFixture.make("druid_wild_wander", false)
	if status_fixture.is_empty():
		return
	var status_controller := status_fixture.c as BattleController
	var protected_user := status_fixture.u as BattleUnitState
	var enemy := status_fixture.enemy as BattleUnitState
	_expect(protected_user.move_hand_card_to_mana(status_fixture.card as CardData, {"controller": status_controller}), "wander enters mana before enemy status regression")
	status_controller.druid_element_rules.resolve_after_strike(enemy, protected_user, {"druid_element": BattleSurfaceState.Element.FIRE})
	_expect(protected_user.has_status("ranger_burn"), "enemy-origin fire still applies burn through wander protection")
	status_controller.druid_element_rules.resolve_after_strike(enemy, protected_user, {"druid_element": BattleSurfaceState.Element.WATER})
	_expect(protected_user.has_status("ranger_burn") and protected_user.has_status("ranger_move_surcharge"), "enemy-origin freeze applies without purging the existing burn")

	var strike_fixture := DruidExpansionFixture.make("druid_wild_wander", false)
	if strike_fixture.is_empty():
		return
	var strike_controller := strike_fixture.c as BattleController
	var striker := strike_fixture.u as BattleUnitState
	var target := strike_fixture.enemy as BattleUnitState
	_expect(striker.move_hand_card_to_mana(strike_fixture.card as CardData, {"controller": strike_controller}), "wander enters mana before real fire strike")
	var armor_before := striker.get_armor_stacks()
	strike_controller.perform_strike_with_options(striker, target, null, 0, 1.0, "wander fire", "weapon", {"druid_element": BattleSurfaceState.Element.FIRE})
	_expect(target.has_status("ranger_burn") and striker.get_armor_stacks() == armor_before + 3, "actual wander fire strike applies fire and one extra earth armor")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_WILD_WANDER FAILURE: %s" % message)


func _cell_at_distance(controller: BattleController, origin: Vector2i, distance: int) -> Vector2i:
	for cell in controller.map_data.get_all_cells():
		if controller.map_data.get_distance(origin, cell) == distance:
			return cell
	return BattleHexGrid.INVALID_CELL
