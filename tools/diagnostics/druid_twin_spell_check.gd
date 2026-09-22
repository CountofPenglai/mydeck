extends Node


var _exit_code: int = 0


class CandidateRemovalEffect extends CardEffect:
	var candidate: CardData
	func on_zone_card_entered_special_zone(owner: BattleUnitState, _zone_card: CardData, _entered_card: CardData, zone_name: String, _context: Dictionary = {}) -> void:
		if zone_name == "mana" and candidate != null:
			owner.discard_pile.erase(candidate)


func _ready() -> void:
	var service_script := load("res://scripts/druid/druid_twin_spell_service.gd")
	_expect(service_script != null, "twin spell service exists")
	if service_script != null:
		_test_free_cross_zone_entry(service_script.new())
		_test_candidates_are_face_based(service_script.new())
		_test_guards_and_empty_entry(service_script.new())
		_test_entry_trigger_revalidates_candidate()
		_test_rng_and_cancel_boundaries(service_script.new())
	print("DRUID_TWIN_SPELL: completed")
	get_tree().quit(_exit_code)


# Catches a free-entry implementation that spends AP/mana, copies the selected
# resource, or fixes pairing to a same-name card instead of the opposite face.
func _test_free_cross_zone_entry(service) -> void:
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	_expect(not fixture.is_empty(), "twin fixture is available")
	if fixture.is_empty():
		return
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var source: CardData = fixture["card"] as CardData
	source.is_twin_spell = true
	source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	var opposite := CardData.new()
	opposite.card_name = "inverse candidate"
	opposite.is_twin_spell = true
	opposite.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	owner.discard_pile.append(opposite)
	var ap_before: int = owner.current_ap
	var mana_before: int = owner.get_available_mana()
	_expect(service.execute(owner, source, opposite, false), "twin action succeeds")
	_expect(owner.mana_zone.has(source) and not owner.hand.has(source), "source moves once")
	_expect(owner.hand.has(opposite) and not owner.discard_pile.has(opposite), "retrieved entity moves once")
	_expect(owner.current_ap == ap_before and owner.get_available_mana() == mana_before, "no AP fee or immediate mana")


func _test_candidates_are_face_based(service) -> void:
	var fixture := DruidExpansionFixture.make("druid_wild_shape", true)
	if fixture.is_empty():
		return
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var source: CardData = fixture["card"] as CardData
	source.is_twin_spell = true
	source.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	var upright := CardData.new()
	upright.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	var same_face := CardData.new()
	same_face.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	owner.draw_pile.append(upright)
	owner.discard_pile.append(same_face)
	_expect(service.get_candidates(owner, source) == [upright], "opposite keyword face is found across zones regardless of form")


func _test_guards_and_empty_entry(service) -> void:
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	if fixture.is_empty():
		return
	var controller: BattleController = fixture["c"] as BattleController
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var source: CardData = fixture["card"] as CardData
	source.is_twin_spell = true
	source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	service.setup(controller)
	_expect(service.can_begin(owner, source), "active druid may begin a free twin entry")
	controller.action_resolution_active = true
	_expect(not service.can_begin(owner, source), "busy resolution rejects a second free entry")
	controller.action_resolution_active = false
	owner.hand.erase(source)
	_expect(not service.execute(owner, source), "source leaving hand rejects commit")
	owner.hand.append(source)
	_expect(service.execute(owner, source), "no-candidate entry still succeeds")
	_expect(owner.mana_zone.has(source), "empty search does not roll back free entry")


func _test_entry_trigger_revalidates_candidate() -> void:
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	if fixture.is_empty():
		return
	var controller: BattleController = fixture["c"] as BattleController
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var source: CardData = fixture["card"] as CardData
	source.is_twin_spell = true
	source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	var candidate := CardData.new()
	candidate.is_twin_spell = true
	candidate.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	owner.discard_pile.append(candidate)
	var unmarked := CardData.new()
	owner.discard_pile.append(unmarked)
	var same_face := CardData.new()
	same_face.is_twin_spell = true
	same_face.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	owner.draw_pile.append(same_face)
	var watcher := CardData.new()
	var removal := CandidateRemovalEffect.new()
	removal.candidate = candidate
	watcher.effect = removal
	owner.mana_zone.append(watcher)
	_expect(controller.use_druid_twin_spell_entry(owner, source), "controller starts twin entry transaction")
	_expect(controller.resolution_runner.has_pending_hand_card_choice(), "controller waits for reciprocal selection")
	var choice = controller.resolution_runner.get_pending_hand_card_choice()
	_expect(choice.get_live_cards() == [candidate], "two-zone picker exposes only live opposite-face candidates")
	var invalid: Array[CardData] = [unmarked]
	_expect(not controller.resolution_runner.submit_hand_card_choice(invalid), "runner rejects unmarked candidate even if UI is bypassed")
	var selected: Array[CardData] = [candidate]
	_expect(controller.resolution_runner.submit_hand_card_choice(selected), "live candidate submission is accepted")
	_expect(owner.mana_zone.has(source), "entry source remains after queued trigger")
	_expect(not owner.hand.has(candidate) and not owner.discard_pile.has(candidate), "queued entry trigger removes candidate before retrieval without a copy")


func _test_rng_and_cancel_boundaries(service) -> void:
	# Discard-only retrieval must not consume RNG; a draw entity must force a
	# shuffle even if its caller omits the searched-deck flag.
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	if fixture.is_empty():
		return
	var controller: BattleController = fixture["c"] as BattleController
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var source: CardData = fixture["card"] as CardData
	source.is_twin_spell = true
	source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	controller.rng.seed = 24680
	service.setup(controller)
	var discard_target := _inverse_twin()
	owner.discard_pile.append(discard_target)
	_add_deck_padding(owner)
	var discard_rng_before: int = controller.rng.state
	_expect(service.execute(owner, source, discard_target, false), "discard-only free entry commits")
	_expect(controller.rng.state == discard_rng_before, "discard-only retrieval does not shuffle or advance RNG")

	var draw_fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	var draw_controller: BattleController = draw_fixture["c"] as BattleController
	var draw_owner: BattleUnitState = draw_fixture["u"] as BattleUnitState
	var draw_source: CardData = draw_fixture["card"] as CardData
	draw_source.is_twin_spell = true
	draw_source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	draw_controller.rng.seed = 24680
	service.setup(draw_controller)
	var draw_target := _inverse_twin()
	draw_owner.draw_pile.append(draw_target)
	_add_deck_padding(draw_owner)
	var draw_rng_before: int = draw_controller.rng.state
	_expect(service.execute(draw_owner, draw_source, draw_target, false), "draw target free entry commits with omitted search flag")
	_expect(draw_controller.rng.state != draw_rng_before, "selected draw entity forces shuffle despite omitted search flag")

	var browse_fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	var browse_controller: BattleController = browse_fixture["c"] as BattleController
	var browse_owner: BattleUnitState = browse_fixture["u"] as BattleUnitState
	var browse_source: CardData = browse_fixture["card"] as CardData
	browse_source.is_twin_spell = true
	browse_source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	browse_controller.rng.seed = 24680
	service.setup(browse_controller)
	var browse_target := _inverse_twin()
	browse_owner.discard_pile.append(browse_target)
	_add_deck_padding(browse_owner)
	var browse_rng_before: int = browse_controller.rng.state
	_expect(service.execute(browse_owner, browse_source, browse_target, true), "deck-viewed discard selection commits")
	_expect(browse_controller.rng.state != browse_rng_before, "deck view then discard selection shuffles")

	var cancel_fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	var cancel_controller: BattleController = cancel_fixture["c"] as BattleController
	var cancel_owner: BattleUnitState = cancel_fixture["u"] as BattleUnitState
	var cancel_source: CardData = cancel_fixture["card"] as CardData
	cancel_source.is_twin_spell = true
	cancel_source.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	cancel_controller.rng.seed = 24680
	cancel_owner.discard_pile.append(_inverse_twin())
	_add_deck_padding(cancel_owner)
	var cancel_rng_before: int = cancel_controller.rng.state
	var cancel_ap_before: int = cancel_owner.current_ap
	var cancel_mana_before: int = cancel_owner.get_available_mana()
	_expect(cancel_controller.use_druid_twin_spell_entry(cancel_owner, cancel_source), "controller opens cancellable twin transaction")
	cancel_controller.mark_druid_twin_spell_deck_viewed(cancel_source)
	cancel_controller.cancel_druid_twin_spell_entry(cancel_source)
	cancel_controller.resolution_runner.cancel_pending_hand_card_choice()
	_expect(cancel_owner.hand.has(cancel_source) and not cancel_owner.mana_zone.has(cancel_source), "cancel keeps source in hand")
	_expect(cancel_controller.rng.state == cancel_rng_before and cancel_owner.current_ap == cancel_ap_before and cancel_owner.get_available_mana() == cancel_mana_before, "cancel changes neither RNG nor AP/mana")
	_expect(not cancel_owner.druid_prepare_used and not cancel_controller.is_resolving_actions(), "free entry cancel neither consumes prepare nor leaves busy state")


func _inverse_twin() -> CardData:
	var card := CardData.new()
	card.is_twin_spell = true
	card.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	return card


func _add_deck_padding(owner: BattleUnitState) -> void:
	while owner.draw_pile.size() < 3:
		owner.draw_pile.append(CardData.new())


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_TWIN_SPELL FAILURE: %s" % message)
