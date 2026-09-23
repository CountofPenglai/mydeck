extends Node


var _exit_code := 0
var _selected_target: BattleUnitState
var _successor_runner: BattleResolutionRunner
var _successor_owner: BattleUnitState
var _successor_source: CardData
var _successor_target: BattleUnitState


class DrawExtraOnceStatus extends StatusEffect:
	func _init() -> void:
		status_id = "task8_draw_extra_once"
		display_name = "task8 draw extra once"

	func on_card_drawn(unit: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
		if stacks <= 0:
			return
		stacks = 0
		var controller := context.get("controller") as BattleController
		if controller != null:
			unit.draw_cards(1, controller.rng, context)


class DrawDiscardAndManaStatus extends StatusEffect:
	func _init() -> void:
		status_id = "task8_draw_discard_and_mana"
		display_name = "task8 draw discard and mana"

	func on_card_drawn(unit: BattleUnitState, card: CardData, context: Dictionary = {}) -> void:
		if stacks <= 0:
			return
		stacks = 0
		unit.discard_card(card, context)
		unit.gain_mana(4, context)


class MoveStrikeTargetAfterHitStatus extends StatusEffect:
	func _init() -> void:
		status_id = "task8_move_strike_target_after_hit"
		display_name = "task8 move strike target after hit"

	func on_after_strike(_unit: BattleUnitState, context: Dictionary = {}) -> void:
		if stacks <= 0:
			return
		stacks = 0
		var controller := context.get("controller") as BattleController
		var target := context.get("target") as BattleUnitState
		if controller != null and target != null and target.is_alive():
			target.set_hex_cell(Vector2i(9, 4), controller.map_data)


func _ready() -> void:
	_test_orientation_weapon_choice_contract()
	_test_upright_recovery_boundaries()
	_test_upright_runner_cancellation_preserves_guaranteed_mana()
	_test_inverse_direct_draw_event_boundaries()
	_test_inverse_strike_boundaries()
	_test_inverse_rechecks_line_of_sight()
	_test_inverse_stun_spans_whole_action()
	_test_typed_unit_choice_contract()
	_test_upright_recovery_and_inverse_fixed_draw_count()
	await _test_mounted_unit_choice_successor_and_navigation()
	await _test_mounted_unit_choice_rejects_dead_target_and_recovers()
	await _test_mounted_unit_choice_escape_finalizes()
	await _test_mounted_unit_choice_popup_hide_finalizes()
	await _test_mounted_unit_choice_teardown_clears_pending_action()
	await _test_mounted_wellspring_recovery_teardown_preserves_guaranteed_mana()
	print("DRUID_WELLSPRING_RETURN: completed")
	get_tree().quit(_exit_code)


# Catches inverse being routed as an ordinary no-weapon skill, which silently
# loses the player's selected weapon mode before any target is chosen.
func _test_orientation_weapon_choice_contract() -> void:
	var upright := (load("res://resources/cards/druid_wellspring_return.tres") as CardData).duplicate(true) as CardData
	var inverse := upright.duplicate(true) as CardData
	_expect(not upright.requires_weapon_choice({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}), "upright recovery never asks for a weapon mode")
	_expect(inverse.requires_weapon_choice({"druid_orientation": CardEnums.DruidOrientation.INVERTED}), "inverse requests the normal weapon-mode choice before selecting strike targets")
	var f := DruidExpansionFixture.make("druid_wellspring_return", true)
	var primary := EquipmentData.new()
	primary.base_damage = 1
	primary.attack_range = 1
	var paired := EquipmentData.new()
	paired.base_damage = 7
	paired.attack_range = 1
	primary.paired_component = paired
	primary.paired_attack_mode = EquipmentData.PairedAttackMode.SELECT_ONE
	f.u.character_state.weapon_equipment = primary
	f.u.gain_mana(1, {"controller": f.c})
	f.u.draw_pile.append(CardData.new())
	var health_before: int = (f.enemy as BattleUnitState).get_current_health()
	_expect(f.u.needs_weapon_choice() and f.c.play_card(f.u, f.card, [], {"equipment_slot": "paired"}), "selected paired weapon mode reaches inverse play instead of being dropped")
	_expect(f.c.resolution_runner.submit_unit_target_choice(f.enemy), "paired-mode inverse accepts a legal selected target")
	_expect(f.enemy.get_current_health() <= health_before - 7, "selected paired mode carries through the unit-choice route into actual strike damage")


# Catches count-only recovery, accepting six cards, and leaving mana-zone
# benefits attached after the specific card has been recovered.
func _test_upright_recovery_boundaries() -> void:
	var empty := DruidExpansionFixture.make("druid_wellspring_return", false)
	_expect(empty.c.play_card(empty.u, empty.card, []), "upright with no mana cards still starts its paid action")
	_expect(empty.u.get_available_mana() == 3 and empty.u.current_ap == 7 and empty.u.discard_pile.has(empty.card), "upright zero-card recovery grants exactly three mana and finalizes only after the action")

	var f := DruidExpansionFixture.make("druid_wellspring_return", false)
	var mana_cards: Array[CardData] = []
	for index in range(6):
		var mana_card := CardData.new()
		mana_card.card_name = "recovery entity %d" % index
		f.u.mana_zone.append(mana_card)
		mana_cards.append(mana_card)
	_expect(f.c.play_card(f.u, f.card, []), "upright opens a live choice for six mana-zone entities")
	_expect(not f.c.resolution_runner.submit_hand_card_choice(mana_cards) and f.c.resolution_runner.has_pending_hand_card_choice(), "six recovery entities are rejected while the optional choice remains available")
	var five: Array[CardData] = mana_cards.slice(0, 5)
	_expect(f.c.resolution_runner.submit_hand_card_choice(five), "five real recovery entities are accepted")
	_expect(f.u.hand.has(five[0]) and f.u.hand.has(five[4]) and f.u.mana_zone.size() == 1 and f.u.get_available_mana() == 3, "recovery moves exactly the selected entity instances before its guaranteed mana")
	var copies := DruidExpansionFixture.make("druid_wellspring_return", false)
	var template := load("res://resources/cards/druid_wild_wander.tres") as CardData
	var first_copy := template.duplicate(true) as CardData
	var second_copy := template.duplicate(true) as CardData
	copies.u.mana_zone.append_array([first_copy, second_copy])
	_expect(first_copy != second_copy and copies.c.play_card(copies.u, copies.card, []), "two distinct instances from the same resource can be selected")
	var copies_selection: Array[CardData] = [first_copy, second_copy]
	_expect(copies.c.resolution_runner.submit_hand_card_choice(copies_selection) and copies.u.hand.has(first_copy) and copies.u.hand.has(second_copy), "recovery preserves identity for same-resource distinct card instances")

	var protection := DruidExpansionFixture.make("druid_wellspring_return", false)
	var wander := (load("res://resources/cards/druid_wild_wander.tres") as CardData).duplicate(true) as CardData
	protection.u.mana_zone.append(wander)
	_expect(protection.c.druid_element_rules.is_surface_protected(protection.u), "Wild Wander protects while it remains in mana")
	_expect(protection.c.play_card(protection.u, protection.card, []), "upright can recover the mana card supplying protection")
	var wander_selection: Array[CardData] = [wander]
	_expect(protection.c.resolution_runner.submit_hand_card_choice(wander_selection), "upright accepts Wild Wander as a real mana-zone entity")
	_expect(not protection.c.druid_element_rules.is_surface_protected(protection.u) and protection.u.get_available_mana() == 3, "leaving mana immediately removes Wild Wander protection before the three-mana grant")

	var skipped := DruidExpansionFixture.make("druid_wellspring_return", false)
	skipped.u.mana_zone.append(CardData.new())
	_expect(skipped.c.play_card(skipped.u, skipped.card, []), "upright skip fixture starts")
	var none: Array[CardData] = []
	_expect(skipped.c.resolution_runner.submit_hand_card_choice(none), "upright may explicitly skip its optional recovery after paying")
	_expect(skipped.u.get_available_mana() == 3 and skipped.u.current_ap == 7 and skipped.u.discard_pile.has(skipped.card), "explicitly skipping recovery still grants exactly three mana within the same three-AP action")


# Catches runner-level cancellation bypassing the opt-in empty-selection
# continuation and silently dropping upright's already-paid guaranteed mana.
func _test_upright_runner_cancellation_preserves_guaranteed_mana() -> void:
	var f := DruidExpansionFixture.make("druid_wellspring_return", false)
	f.u.mana_zone.append(CardData.new())
	_expect(f.c.play_card(f.u, f.card, []), "runner-cancellation fixture starts a paid upright recovery")
	_expect(f.c.resolution_runner.has_pending_hand_card_choice(), "upright recovery is pending before direct runner cancellation")
	f.c.resolution_runner.cancel_pending_hand_card_choice()
	_expect(not f.c.resolution_runner.has_pending_hand_card_choice() and f.u.get_available_mana() == 3 and f.u.current_ap == 7 and f.u.discard_pile.has(f.card), "direct runner cancellation submits an empty recovery and preserves paid AP, guaranteed mana, and source finalization")


# Catches deriving strikes from a final hand difference or recomputing after
# real draw listeners mutate the hand and mana.
func _test_inverse_direct_draw_event_boundaries() -> void:
	var nested := DruidExpansionFixture.make("druid_wellspring_return", true)
	nested.u.gain_mana(2, {"controller": nested.c})
	var nested_draw := CardData.new()
	var direct_second := CardData.new()
	var trigger_draw := CardData.new()
	nested.u.draw_pile.append_array([nested_draw, direct_second, trigger_draw])
	nested.u.add_status(DrawExtraOnceStatus.new())
	_expect(nested.c.play_card(nested.u, nested.card, []), "inverse begins the nested draw-listener fixture")
	var nested_effect = nested.card.effect
	_expect(nested_effect.direct_draw_count == 2 and nested_effect.strikes_remaining == 2 and nested.u.hand.has(nested_draw), "a real draw-triggered extra draw settles but does not add a direct card or strike")
	_expect(nested.c.resolution_runner.submit_unit_target_choice(null), "nested draw fixture may stop its optional strikes")

	var mutation := DruidExpansionFixture.make("druid_wellspring_return", true)
	mutation.u.gain_mana(2, {"controller": mutation.c})
	mutation.u.draw_pile.append_array([CardData.new(), CardData.new()])
	mutation.u.add_status(DrawDiscardAndManaStatus.new())
	_expect(mutation.c.play_card(mutation.u, mutation.card, []), "inverse begins the draw-discard-and-mana listener fixture")
	var mutation_effect = mutation.card.effect
	_expect(mutation_effect.direct_draw_count == 2 and mutation_effect.strikes_remaining == 2 and mutation.u.get_available_mana() == 6, "a draw listener that discards and gains mana cannot recompute the fixed direct draw or strike count")
	_expect(mutation.c.resolution_runner.submit_unit_target_choice(null), "mutation fixture may stop after listener descendants settle")


# Catches source-in-flight reshuffle, target death/successor selection, and
# next-choice timing after all attack descendants have settled.
func _test_inverse_strike_boundaries() -> void:
	var empty_deck := DruidExpansionFixture.make("druid_wellspring_return", true)
	empty_deck.u.gain_mana(2, {"controller": empty_deck.c})
	_expect(empty_deck.c.play_card(empty_deck.u, empty_deck.card, []), "inverse with an empty deck starts")
	var empty_effect = empty_deck.card.effect
	_expect(empty_effect.direct_draw_count == 0 and not empty_deck.c.resolution_runner.has_pending_unit_target_choice() and empty_deck.u.discard_pile.has(empty_deck.card), "empty deck produces zero strikes and completes cleanly")
	var short_deck := DruidExpansionFixture.make("druid_wellspring_return", true)
	short_deck.u.gain_mana(3, {"controller": short_deck.c})
	short_deck.u.draw_pile.append(CardData.new())
	_expect(short_deck.c.play_card(short_deck.u, short_deck.card, []), "inverse with a short deck starts")
	var short_effect = short_deck.card.effect
	_expect(short_effect.direct_draw_count == 1 and short_effect.strikes_remaining == 1 and short_deck.c.resolution_runner.has_pending_unit_target_choice(), "short deck produces only its one actual direct card and one optional strike")
	_expect(short_deck.c.resolution_runner.submit_unit_target_choice(null), "short deck strike option ends cleanly")

	var reshuffle := DruidExpansionFixture.make("druid_wellspring_return", true)
	reshuffle.u.gain_mana(2, {"controller": reshuffle.c})
	var discard_a := CardData.new()
	var discard_b := CardData.new()
	reshuffle.u.discard_pile.append_array([discard_a, discard_b])
	_expect(reshuffle.c.play_card(reshuffle.u, reshuffle.card, []), "inverse reshuffles ordinary discard cards when its draw pile is empty")
	var reshuffle_effect = reshuffle.card.effect
	_expect(reshuffle_effect.direct_draw_count == 2 and reshuffle.u.hand.has(discard_a) and reshuffle.u.hand.has(discard_b) and not reshuffle.u.discard_pile.has(reshuffle.card), "the resolving source stays in flight and out of reshuffle until the optional strikes finish")
	_expect(reshuffle.c.resolution_runner.submit_unit_target_choice(null) and reshuffle.u.discard_pile.has(reshuffle.card), "source discards only after the completed inverse action")

	var sequence := DruidExpansionFixture.make("druid_wellspring_return", true)
	sequence.u.gain_mana(2, {"controller": sequence.c})
	sequence.u.draw_pile.append_array([CardData.new(), CardData.new()])
	var first := sequence.enemy as BattleUnitState
	var second := sequence.c.enemy_units[1] as BattleUnitState
	first.set_hex_cell(Vector2i(5, 4), sequence.c.map_data)
	first.set_current_health(1)
	second.is_deployed = true
	second.set_hex_cell(Vector2i(4, 5), sequence.c.map_data)
	_expect(sequence.c.play_card(sequence.u, sequence.card, []), "inverse sequence starts with two direct draws")
	_expect(sequence.c.resolution_runner.submit_unit_target_choice(first), "inverse can strike and kill its first selected target")
	_expect(not first.is_alive() and sequence.c.resolution_runner.has_pending_unit_target_choice(), "after a completed killing strike inverse asks for another live target")
	_expect(sequence.c.resolution_runner.submit_unit_target_choice(second), "inverse may choose a different live target for the next strike")
	_expect(not sequence.c.resolution_runner.has_pending_unit_target_choice() and sequence.u.current_ap == 7 and sequence.u.get_available_mana() == 2 and sequence.u.discard_pile.has(sequence.card), "two strikes consume no extra AP or mana and preserve the original action finalization")

	var moved := DruidExpansionFixture.make("druid_wellspring_return", true)
	moved.u.gain_mana(2, {"controller": moved.c})
	moved.u.draw_pile.append_array([CardData.new(), CardData.new()])
	var moved_target := moved.enemy as BattleUnitState
	moved_target.set_hex_cell(Vector2i(5, 4), moved.c.map_data)
	for other_value in moved.c.enemy_units:
		var other := other_value as BattleUnitState
		if other != moved_target:
			other.is_deployed = false
	moved.u.add_status(MoveStrikeTargetAfterHitStatus.new())
	_expect(moved.c.play_card(moved.u, moved.card, []), "inverse descendant-mutation fixture starts")
	_expect(moved.c.resolution_runner.submit_unit_target_choice(moved_target), "inverse accepts its initial legal target before the descendant moves it")
	_expect(not moved.c.resolution_runner.has_pending_unit_target_choice() and moved.u.current_ap == 7, "after-strike descendants settle before successor targeting and a moved-out target is not offered again")


# Catches the old attack-range-only candidate filter: ranged attacks must not
# offer a target through a live line-of-sight blocker.
func _test_inverse_rechecks_line_of_sight() -> void:
	var f := DruidExpansionFixture.make("druid_wellspring_return", true)
	f.u.character_state.weapon_equipment = (load("res://resources/items/druid_rise_eagle.tres") as EquipmentData).duplicate(true) as EquipmentData
	f.u.gain_mana(1, {"controller": f.c})
	f.u.draw_pile.append(CardData.new())
	var target := f.enemy as BattleUnitState
	target.set_hex_cell(Vector2i(6, 4), f.c.map_data)
	for other_value in f.c.enemy_units:
		var other := other_value as BattleUnitState
		if other != target:
			other.is_deployed = false
	_expect(f.c.spawn_battle_object(BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(5, 4)) != null, "line-of-sight fixture places a real blocking battlefield object")
	var health_before: int = target.get_current_health()
	_expect(f.c.play_card(f.u, f.card, []), "inverse begins with a ranged transformed weapon mode")
	_expect(not f.c.resolution_runner.has_pending_unit_target_choice() and target.get_current_health() == health_before and f.u.discard_pile.has(f.card), "a blocked ranged target is not offered and inverse ends without an illegal strike")


# Catches finalizing AP/stun at draw time or after an intermediate strike rather
# than after the optional action and every attack descendant has resolved.
func _test_inverse_stun_spans_whole_action() -> void:
	var f := DruidExpansionFixture.make("druid_wellspring_return", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.draw_pile.append_array([CardData.new(), CardData.new()])
	var stun := StunStatus.new()
	stun.stacks = 3
	f.u.add_status(stun)
	var first := f.enemy as BattleUnitState
	var second := f.c.enemy_units[1] as BattleUnitState
	first.set_hex_cell(Vector2i(5, 4), f.c.map_data)
	second.is_deployed = true
	second.set_hex_cell(Vector2i(4, 5), f.c.map_data)
	_expect(f.c.play_card(f.u, f.card, []), "stunned inverse starts one paid three-AP action")
	_expect(f.u.get_status("stun") != null and f.u.get_status("stun").stacks == 3, "stun survives all direct draws while target choice is pending")
	_expect(f.c.resolution_runner.submit_unit_target_choice(first), "stunned inverse completes its first strike")
	_expect(f.c.resolution_runner.has_pending_unit_target_choice() and f.u.get_status("stun") != null and f.u.get_status("stun").stacks == 3, "stun survives an intermediate strike and successor choice")
	_expect(f.c.resolution_runner.submit_unit_target_choice(second), "stunned inverse completes its final strike")
	_expect(f.u.get_status("stun") == null and f.u.current_ap == 7, "stun loses exactly the original three AP only after the whole inverse action completes")


func _test_typed_unit_choice_contract() -> void:
	var controller := BattleController.new()
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	if fixture.is_empty():
		_expect(false, "fixture creates live units for typed target selection")
		return
	controller = fixture.c as BattleController
	var runner := controller.resolution_runner
	var owner := fixture.u as BattleUnitState
	var target := fixture.enemy as BattleUnitState
	var source := fixture.card as CardData
	_selected_target = null
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice"), [runner, owner, source, target]))
	_expect(runner.has_pending_unit_target_choice() and runner.action_active, "typed target choice suspends its owning action")
	_expect(BattleNavigationGuard.check(controller, false).get("ok", true) == false, "pending unit choice blocks navigation")
	_expect(runner.submit_unit_target_choice(target), "live unit submission resumes the suspended action")
	_expect(_selected_target == target and not runner.has_pending_unit_target_choice() and not controller.is_resolving_actions(), "submitted unit stays typed and completes the original action")


func _request_unit_choice(runner, owner: BattleUnitState, source: CardData, target: BattleUnitState) -> void:
	runner.request_unit_target_choice(owner, source, "diagnostic unit", Callable(self, "_record_target"), [target])


func _record_target(target: BattleUnitState) -> void:
	_selected_target = target


func _test_upright_recovery_and_inverse_fixed_draw_count() -> void:
	var upright := DruidExpansionFixture.make("druid_wellspring_return", false)
	_expect(not upright.is_empty(), "wellspring resource is available for upright recovery")
	if upright.is_empty():
		return
	var controller: BattleController = upright.c as BattleController
	var owner: BattleUnitState = upright.u as BattleUnitState
	var card: CardData = upright.card as CardData
	var recovered: Array[CardData] = []
	for index in range(6):
		var mana_card := CardData.new()
		mana_card.card_name = "mana %d" % index
		owner.mana_zone.append(mana_card)
		recovered.append(mana_card)
	_expect(controller.play_card(owner, card, []), "upright spends its normal AP and opens an optional mana-zone selection")
	_expect(controller.resolution_runner.has_pending_hand_card_choice(), "upright selection remains attached to the paid action")
	var selected: Array[CardData] = recovered.slice(0, 5)
	_expect(controller.resolution_runner.submit_hand_card_choice(selected), "upright accepts five live mana cards")
	var all_recovered := true
	for selected_card in selected:
		all_recovered = all_recovered and owner.hand.has(selected_card)
	_expect(all_recovered and owner.mana_zone.size() == 1 and owner.get_available_mana() == 3, "upright returns at most five entities then gains exactly three mana")
	_expect(owner.current_ap == 7 and owner.discard_pile.has(card), "upright consumes exactly three AP and completes normally")

	var inverse := DruidExpansionFixture.make("druid_wellspring_return", true)
	_expect(not inverse.is_empty(), "wellspring resource is available for inverse draw and strikes")
	if inverse.is_empty():
		return
	controller = inverse.c as BattleController
	owner = inverse.u as BattleUnitState
	card = inverse.card as CardData
	owner.hand.append_array([CardData.new(), CardData.new(), CardData.new()])
	for _index in range(5):
		owner.draw_pile.append(CardData.new())
	owner.gain_mana(8, {"controller": controller})
	_expect(controller.play_card(owner, card, []), "inverse begins without selecting a card-play target")
	var effect = card.effect
	_expect(effect.direct_draw_count == 5 and effect.strikes_remaining == 5, "inverse fixes its strike count from five direct draws")
	_expect(controller.resolution_runner.has_pending_unit_target_choice(), "inverse opens a real target choice after draws settle")
	var first_target: BattleUnitState = inverse.enemy as BattleUnitState
	_expect(controller.resolution_runner.submit_unit_target_choice(first_target), "inverse accepts its first chosen legal enemy")
	_expect(controller.resolution_runner.has_pending_unit_target_choice() and effect.strikes_remaining == 4, "after one completed strike, inverse offers another live target choice")
	var ap_before := owner.current_ap
	_expect(controller.resolution_runner.submit_unit_target_choice(null), "inverse may stop after payment without auto-targeting")
	_expect(owner.current_ap == ap_before and owner.current_ap == 7 and owner.get_available_mana() == 8, "inverse adds no AP or mana cost beyond its three-AP action")


func _test_mounted_unit_choice_successor_and_navigation() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var first_target: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	var successor_target: BattleUnitState = controller.enemy_units[1] as BattleUnitState
	var source := CardData.new()
	owner.hand.append(source)
	_selected_target = null
	_successor_runner = controller.resolution_runner
	_successor_owner = owner
	_successor_source = source
	_successor_target = successor_target
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice_with_successor"), [controller.resolution_runner, owner, source, first_target]))
	scene.call("_refresh")
	var popup = scene.get("_unit_target_picker")
	_expect(popup != null and popup.visible, "mounted scene displays the first pending unit-target choice")
	if popup != null:
		popup.call("_submit", first_target)
	_expect(_selected_target == first_target, "mounted target submit executes the selected continuation")
	_expect(controller.resolution_runner.has_pending_unit_target_choice() and popup != null and popup.visible, "synchronous successor choice remains visible after target submit")
	_expect(BattleNavigationGuard.check(controller, false).get("ok", true) == false, "navigation stays blocked while a successor target choice is pending")
	if popup != null:
		popup.call("_submit", null)
	await get_tree().process_frame
	_expect(not controller.resolution_runner.has_pending_unit_target_choice() and not controller.is_resolving_actions(), "stopping the successor choice completes its action")
	_expect(BattleNavigationGuard.check(controller, false).get("ok", false), "navigation unblocks only after all target choices and action finalization finish")
	scene.queue_free()
	await get_tree().process_frame


func _request_unit_choice_with_successor(runner, owner: BattleUnitState, source: CardData, target: BattleUnitState) -> void:
	runner.request_unit_target_choice(owner, source, "first mounted target", Callable(self, "_record_target_then_request_successor"), [target])


func _record_target_then_request_successor(target: BattleUnitState) -> void:
	_selected_target = target
	_successor_runner.request_unit_target_choice(
		_successor_owner,
		_successor_source,
		"successor mounted target",
		Callable(self, "_record_target"),
		[_successor_target]
	)


func _test_mounted_unit_choice_rejects_dead_target_and_recovers() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var target: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	var source := CardData.new()
	owner.hand.append(source)
	_selected_target = null
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice"), [controller.resolution_runner, owner, source, target]))
	scene.call("_refresh")
	var popup = scene.get("_unit_target_picker")
	target.set_current_health(0)
	if popup != null:
		popup.call("_submit", target)
	_expect(_selected_target == null and controller.resolution_runner.has_pending_unit_target_choice(), "a target that dies before submit is rejected without resolving its action")
	scene.call("_refresh")
	_expect(popup != null and popup.visible, "refresh keeps the optional target choice recoverable after stale target rejection")
	if popup != null:
		popup.call("_submit", null)
	await get_tree().process_frame
	_expect(not controller.resolution_runner.has_pending_unit_target_choice() and not controller.is_resolving_actions(), "stop remains available after a stale target rejection")
	scene.queue_free()
	await get_tree().process_frame


func _test_mounted_unit_choice_popup_hide_finalizes() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var target: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	var source := CardData.new()
	owner.hand.append(source)
	_selected_target = null
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice"), [controller.resolution_runner, owner, source, target]))
	scene.call("_refresh")
	var popup = scene.get("_unit_target_picker")
	if popup != null:
		popup.hide()
	await get_tree().process_frame
	_expect(_selected_target == null and not controller.resolution_runner.has_pending_unit_target_choice() and not controller.is_resolving_actions(), "popup hide stops an optional target choice and finalizes its action")
	scene.queue_free()
	await get_tree().process_frame


func _test_mounted_unit_choice_escape_finalizes() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var target: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	var source := CardData.new()
	owner.hand.append(source)
	_selected_target = null
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice"), [controller.resolution_runner, owner, source, target]))
	scene.call("_refresh")
	var popup = scene.get("_unit_target_picker")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	_expect(popup != null and not popup.visible and _selected_target == null and not controller.resolution_runner.has_pending_unit_target_choice() and not controller.is_resolving_actions(), "Escape closes the mounted target popup and finalizes its optional action")
	scene.queue_free()
	await get_tree().process_frame


func _test_mounted_unit_choice_teardown_clears_pending_action() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var runner: BattleResolutionRunner = controller.resolution_runner
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var target: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	var source := CardData.new()
	owner.hand.append(source)
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_unit_choice"), [runner, owner, source, target]))
	scene.call("_refresh")
	_expect(runner.has_pending_unit_target_choice(), "teardown fixture begins with a real pending target action")
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not runner.has_pending_unit_target_choice() and not runner.action_active and runner.action_queue.is_empty() and not controller.is_resolving_actions(), "scene teardown leaves no stale target callback or pending action")


# Catches scene teardown routing an opt-in recovery cancellation through the
# legacy discard path instead of the same empty selection as an explicit skip.
func _test_mounted_wellspring_recovery_teardown_preserves_guaranteed_mana() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = null
	for unit_value in controller.player_units:
		var unit := unit_value as BattleUnitState
		if unit != null and unit.is_druid():
			owner = unit
	_expect(owner != null, "mounted recovery teardown fixture finds the druid owner")
	if owner == null:
		scene.queue_free()
		return
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = owner
	owner.current_ap = 10
	owner.hand.clear()
	owner.mana_zone.clear()
	owner.clear_mana()
	owner.set_druid_transformed(false)
	var card := (load("res://resources/cards/druid_wellspring_return.tres") as CardData).duplicate(true) as CardData
	owner.hand.append(card)
	owner.mana_zone.append(CardData.new())
	_expect(controller.play_card(owner, card, []), "mounted teardown starts a real paid Wellspring recovery")
	_expect(controller.resolution_runner.has_pending_hand_card_choice(), "mounted teardown begins with a real pending Wellspring recovery")
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not controller.resolution_runner.has_pending_hand_card_choice() and owner.get_available_mana() == 3 and owner.current_ap == 7 and owner.discard_pile.has(card), "mounted teardown submits empty Wellspring recovery and retains its paid AP, guaranteed mana, and source finalization")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_WELLSPRING_RETURN: %s" % message)
