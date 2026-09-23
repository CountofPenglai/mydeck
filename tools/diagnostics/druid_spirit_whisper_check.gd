extends Node


var _exit_code := 0


class TargetedResponseProbeEffect extends CardEffect:
	var responses := 0

	func on_zone_owner_targeted(owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> void:
		responses += 1
		owner.gain_armor(5, context)


class DrawProbeStatus extends StatusEffect:
	var draws := 0

	func _init() -> void:
		status_id = "task9_draw_probe"

	func on_card_drawn(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
		draws += 1


func _ready() -> void:
	_test_paid_enemy_implicit_targets_notify_before_effect()
	_test_upright_reveals_without_draw_and_applies_each_classification()
	_test_inverted_mana_response_roots_counts_and_discards_once()
	_test_inverted_card_can_respond_after_reentering_mana()
	print("DRUID_SPIRIT_WHISPER: completed")
	get_tree().quit(_exit_code)


# Removing the paid target-response boundary (or declaring only UI targets)
# must fail this: EXTRA_LIMBS has no explicit target but really hits its target.
func _test_paid_enemy_implicit_targets_notify_before_effect() -> void:
	var f := DruidExpansionFixture.make("druid_wild_wander", false)
	_expect(not f.is_empty(), "fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var target := f.u as BattleUnitState
	var enemy := f.enemy as BattleUnitState
	var enemy_card := (load("res://resources/cards/monster_cards/extra_limbs.tres") as CardData).duplicate(true) as CardData
	var probe_card := CardData.new()
	var probe_effect := TargetedResponseProbeEffect.new()
	probe_card.effect = probe_effect
	target.mana_zone.append(probe_card)
	enemy.hand.append(enemy_card)
	enemy.current_ap = 10
	controller.current_unit = enemy
	_expect(controller.can_preview_card_targets(enemy, enemy_card, []), "implicit monster card can preview without notifying a mana card")
	_expect(probe_effect.responses == 0 and target.get_armor_stacks() == 0, "target preview does not invoke the response")
	_expect(controller.play_card(enemy, enemy_card, []), "paid implicit monster card starts")
	_expect(probe_effect.responses == 1, "paid EXTRA_LIMBS notifies its actual target exactly once despite three damage segments")
	_expect(target.get_armor_stacks() > 0, "the target response armor exists before EXTRA_LIMBS applies its damage")


# Removing upright's discard/reveal implementation, treating printed words as
# metadata, or routing reveals through draw must all fail this real card flow.
func _test_upright_reveals_without_draw_and_applies_each_classification() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not f.is_empty(), "spirit whisper fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var source := f.card as CardData
	var attack := CardData.new()
	attack.card_type = CardEnums.CardType.ATTACK
	var transformation := CardData.new()
	transformation.upright_is_transformation = true
	var twin := CardData.new()
	twin.is_twin_spell = true
	twin.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	var printed_only := CardData.new()
	printed_only.description = "这张牌提到变形，却没有变形元数据。"
	var discarded_cards: Array[CardData] = [CardData.new(), CardData.new(), CardData.new(), CardData.new()]
	user.hand.append_array(discarded_cards)
	user.draw_pile.append_array([attack, transformation, twin, printed_only])
	var draw_probe := DrawProbeStatus.new()
	user.add_status(draw_probe)
	for unit_value in controller.units:
		var unit := unit_value as BattleUnitState
		if unit != null and unit.faction == user.faction:
			unit.set_current_health(unit.get_max_health())
	var ally: BattleUnitState
	for unit_value in controller.player_units:
		var candidate := unit_value as BattleUnitState
		if candidate != null and candidate != user:
			ally = candidate
			break
	_expect(ally != null, "fixture has a second friendly unit for deterministic healing")
	if ally == null:
		return
	ally.is_deployed = true
	ally.set_current_health(10)
	user.set_current_health(10)
	var expected_heal_target := ally if ally.unit_id < user.unit_id else user
	var expected_before := expected_heal_target.get_current_health()
	_expect(not source.upright_play_ignores_form and source.get_twin_spell_face() == CardEnums.DruidOrientation.UPRIGHT and source.allow_twin_face_play, "upright is the two-AP twin exception, not a form exception")
	_expect(controller.play_card(user, source, []), "upright spirit whisper starts its paid action")
	_expect(user.current_ap == 9, "one revealed twin spell grants exactly one AP after the two-AP payment")
	_expect(user.discard_pile.has(discarded_cards[0]) and user.discard_pile.has(source) and not user.discard_pile.has(attack), "starting hand discards and revealed entities stay distinct")
	_expect(user.hand.has(attack) and user.hand.has(transformation) and user.hand.has(twin) and user.hand.has(printed_only), "every directly revealed entity returns to hand")
	_expect(draw_probe.draws == 0, "reveal-to-hand does not emit draw events")
	_expect(expected_heal_target.get_current_health() == expected_before + 4, "transformation metadata heals the deterministic lowest-health injured ally")
	_expect(user.get_status("druid_spirit_whisper_next_strike") != null and user.get_status("druid_spirit_whisper_next_strike").stacks == 4, "only the attack metadata grants the next weapon-strike bonus")


# This catches response reentry per repeated EXTRA_LIMBS segments and verifies
# the required root-then-count ordering with the owner included in the count.
func _test_inverted_mana_response_roots_counts_and_discards_once() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not f.is_empty(), "inverted response fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var owner := f.u as BattleUnitState
	var source_enemy := f.enemy as BattleUnitState
	var second_enemy := controller.enemy_units[1] as BattleUnitState
	second_enemy.is_deployed = true
	second_enemy.set_hex_cell(Vector2i(4, 5), controller.map_data)
	source_enemy.set_hex_cell(Vector2i(5, 4), controller.map_data)
	owner.add_status(preload("res://scripts/status/druid_root_status.gd").new())
	var first_copy := f.card as CardData
	var second_copy := (load("res://resources/cards/druid_spirit_whisper.tres") as CardData).duplicate(true) as CardData
	owner.hand.erase(first_copy)
	owner.mana_zone.append_array([first_copy, second_copy])
	var enemy_card := (load("res://resources/cards/monster_cards/extra_limbs.tres") as CardData).duplicate(true) as CardData
	source_enemy.hand.append(enemy_card)
	source_enemy.current_ap = 10
	controller.current_unit = source_enemy
	_expect(controller.play_card(source_enemy, enemy_card, []), "paid implicit enemy card targets both mana-zone copies")
	_expect(source_enemy.has_status("druid_root") and second_enemy.has_status("druid_root"), "inverted response roots every hostile unit in radius three")
	_expect(owner.get_armor_stacks() == 15, "each physical mana copy adds nine armor from owner plus two rooted enemies before the three one-damage segments consume armor")
	_expect(owner.mana_zone.is_empty() and owner.discard_pile.has(first_copy) and owner.discard_pile.has(second_copy), "each responding physical card leaves mana for discard exactly once")


# Replacing the response lock with a permanent card-instance flag must fail:
# this is the same physical card, newly re-entered into mana, facing a new
# paid enemy action through the real controller.
func _test_inverted_card_can_respond_after_reentering_mana() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not f.is_empty(), "reentry fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var owner := f.u as BattleUnitState
	var enemy := f.enemy as BattleUnitState
	var response := f.card as CardData
	owner.hand.erase(response)
	owner.mana_zone.append(response)
	for _round in range(2):
		var enemy_card := (load("res://resources/cards/monster_cards/extra_limbs.tres") as CardData).duplicate(true) as CardData
		enemy.hand.append(enemy_card)
		enemy.current_ap = 10
		controller.current_unit = enemy
		_expect(controller.play_card(enemy, enemy_card, []), "paid enemy action starts for response reentry")
		_expect(owner.discard_pile.has(response), "response leaves mana after each paid enemy action")
		if _round == 0:
			_expect(owner.move_mana_card_to_hand(response) == false, "responding card is no longer in mana")
			owner.discard_pile.erase(response)
			owner.hand.append(response)
			_expect(owner.move_hand_card_to_mana(response), "same physical response card re-enters mana")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_SPIRIT_WHISPER FAILURE: %s" % message)
