extends Node


var _exit_code := 0


class DrawStunEffect extends CardEffect:
	func on_self_drawn(owner: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
		var stun := StunStatus.new()
		stun.stacks = 2
		owner.add_status(stun)


class AfterStrikeTargetMutationStatus extends StatusEffect:
	var move_target := false

	func _init() -> void:
		status_id = "diagnostic_after_strike_target_mutation"
		display_name = "diagnostic"

	func on_after_strike(_unit: BattleUnitState, context: Dictionary = {}) -> void:
		var controller := context.get("controller") as BattleController
		var target := context.get("target") as BattleUnitState
		if controller == null or target == null:
			return
		if move_target:
			target.set_hex_cell(Vector2i(9, 4), controller.map_data)
		else:
			controller.lose_life(null, target, target.get_current_health(), "diagnostic after-strike kill")
		stacks = 0


func _ready() -> void:
	_test_binding_and_drain()
	_test_claws_and_canopy_choices()
	_test_covenant_and_graft()
	_test_multiple_mana_zone_copies()
	if _exit_code == 0:
		print("DRUID_REWORK_CARDS: PASS")
	get_tree().quit(_exit_code)


# Catches the old enchantment/hand-size armor and draw-listener drain branches.
func _test_binding_and_drain() -> void:
	var f := _fixture("druid_binding_enchantment", false)
	_add_draws(f.u, 2)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "binding upright is a self skill")
	_expect(f.u.hand.size() == 2 and f.u.get_armor_stacks() == 4, "binding upright draws two and gains four armor")
	_expect(f.u.discard_pile.has(f.card), "binding upright discards")
	f = _fixture("druid_binding_enchantment", true)
	_add_draws(f.u, 1)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "binding inverse is a self skill")
	_expect(f.u.hand.size() == 1 and f.u.get_armor_stacks() == 4 and f.u.mana_zone.has(f.card), "binding inverse draws one, gains four armor, and explicitly enters mana")
	var hand_before: int = f.u.hand.size()
	f.u.draw_pile.append(_dummy_card("binding zone draw"))
	f.card.effect.on_zone_owner_turn_start(f.u, f.card, {"controller": f.c, "zone_name": "mana"})
	_expect(f.u.hand.size() == hand_before + 1, "binding mana-zone effect draws on own turn start")

	f = _fixture("druid_forced_drain", false)
	f.u.character_state.intelligence_bonus = -f.u.character_state.character_data.base_intelligence
	var upright_drain_before: int = f.enemy.get_current_health()
	var upright_bonus: int = f.u.get_damage_bonus({"controller": f.c, "card": f.card, "target": f.enemy, "resolved_damage_type": CardEnums.DamageType.INTELLIGENCE})
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "drain upright is directly playable")
	_expect(upright_drain_before - f.enemy.get_current_health() == 6 + upright_bonus and f.enemy.has_status("druid_root"), "drain upright preserves its six-point intelligence base before legal modifiers (actual %d)" % (upright_drain_before - f.enemy.get_current_health()))
	_expect(f.u.discard_pile.has(f.card) and not f.u.mana_zone.has(f.card), "drain upright discards rather than entering mana")

	f = _fixture("druid_forced_drain", true)
	f.u.character_state.intelligence_bonus = -f.u.character_state.character_data.base_intelligence
	_expect(f.card.damage_type == CardEnums.DamageType.INTELLIGENCE, "drain is marked as an intelligence-damage card")
	var inverse_drain_before: int = f.enemy.get_current_health()
	var inverse_bonus: int = f.u.get_damage_bonus({"controller": f.c, "card": f.card, "target": f.enemy, "resolved_damage_type": CardEnums.DamageType.INTELLIGENCE})
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "drain inverse is directly playable")
	_expect(inverse_drain_before - f.enemy.get_current_health() == 3 + inverse_bonus and f.enemy.has_status("druid_root") and f.u.mana_zone.has(f.card), "drain inverse preserves its three-point intelligence base before legal modifiers, roots, and enters mana (actual %d)" % (inverse_drain_before - f.enemy.get_current_health()))

	f = _fixture("druid_forced_drain", true)
	var root := _root()
	f.enemy.add_status(root)
	f.enemy.gain_armor(99)
	f.enemy.set_current_health(1)
	f.u.set_current_health(maxi(1, f.u.get_max_health() - 3))
	var health_before: int = f.u.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "drain inverse is directly playable for zone-loss test")
	_expect(f.enemy.has_status("druid_root") and f.u.mana_zone.has(f.card), "drain inverse roots and explicitly enters mana")
	f.card.effect.on_zone_owner_turn_start(f.u, f.card, {"controller": f.c, "zone_name": "mana"})
	_expect(not f.enemy.is_alive() and f.u.get_current_health() == health_before + 1, "drain zone effect ignores armor and heals only actual life lost")


# Catches choosing before drawing, selecting the source card, and canopy's obsolete discard/shelter branch.
func _test_claws_and_canopy_choices() -> void:
	var f := _fixture("druid_channeling_claws", false)
	var old_hand := _dummy_card("old hand")
	var drawn := _dummy_card("new draw")
	f.u.hand.append(old_hand)
	f.u.draw_pile.append(drawn)
	f.u.draw_pile.append(_dummy_card("second draw"))
	_expect(f.c.play_card(f.u, f.card, []), "claws upright starts")
	_expect(f.c.resolution_runner.has_pending_hand_card_choice(), "claws asks after its two draws")
	var claws_selection: Array[CardData] = [drawn]
	_expect(f.c.resolution_runner.submit_hand_card_choice(claws_selection), "claws accepts a newly drawn other card")
	_expect(f.u.mana_zone.has(drawn) and not f.u.mana_zone.has(f.card), "claws moves selected hand card only")
	_test_claws_waits_for_draw_triggers_before_choice()
	f = _fixture("druid_channeling_claws", true)
	f.u.set_current_health(maxi(1, f.u.get_max_health() - 8))
	var claws_health_before: int = f.u.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "claws inverse strikes in extended weapon range")
	_expect(f.u.get_current_health() > claws_health_before, "claws inverse heals its actual strike life loss")
	_expect(f.u.get_available_mana() == 1 and f.u.mana_zone.has(f.card), "claws inverse gains one mana then explicitly enters mana")

	f = _fixture("druid_channeling_claws", false)
	_expect(f.c.play_card(f.u, f.card, []), "claws upright resolves with no draw pile")
	_expect(not f.c.resolution_runner.has_pending_hand_card_choice() and f.u.discard_pile.has(f.card) and not f.u.mana_zone.has(f.card), "claws with no drawn or other hand card ends without a choice or self fallback")


# Catches asking before draw triggers settle, which would expose a stale hand and split the AP action.
func _test_claws_waits_for_draw_triggers_before_choice() -> void:
	var f := _fixture("druid_channeling_claws", false)
	var selected := _dummy_card("claws selection")
	var trigger_card := _dummy_card("draw stun")
	trigger_card.effect = DrawStunEffect.new()
	f.u.hand.append(selected)
	f.u.draw_pile.append(_dummy_card("second draw"))
	f.u.draw_pile.append(trigger_card)
	_expect(f.c.play_card(f.u, f.card, []), "claws starts the post-draw trigger fixture")
	_expect(f.u.get_status("stun") != null and f.u.get_status("stun").stacks == 2, "draw trigger resolves before claws exposes its hand choice")
	var selection: Array[CardData] = [selected]
	_expect(f.c.resolution_runner.submit_hand_card_choice(selection), "claws selection resumes the original AP action")
	_expect(not f.u.has_status("stun") and f.u.current_ap == 8, "the resumed same action spends two AP and removes the two drawn stun stacks")

	f = _fixture("druid_canopy_cycle", false)
	var first := _dummy_card("canopy first")
	var second := _dummy_card("canopy second")
	f.u.hand.append(first)
	f.u.hand.append(second)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "canopy upright starts")
	_expect(f.c.resolution_runner.has_pending_hand_card_choice(), "canopy asks before drawing")
	var canopy_selection: Array[CardData] = [first, second]
	_expect(f.c.resolution_runner.submit_hand_card_choice(canopy_selection), "canopy accepts zero to two other cards")
	_expect(f.u.mana_zone.has(first) and f.u.mana_zone.has(second) and f.u.is_druid_transformed(), "canopy moves selection then transforms")
	f = _fixture("druid_canopy_cycle", true)
	f.u.add_card_to_mana_zone(_dummy_card("existing mana"), {"controller": f.c})
	_add_draws(f.u, 1)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "canopy inverse is a self skill without discard")
	_expect(f.u.get_armor_stacks() == 5 and f.u.mana_zone.has(f.card), "canopy inverse counts existing mana cards, draws, and enters mana")
	f = _fixture("druid_canopy_cycle", false)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "canopy upright permits zero selections with no other hand cards")
	_expect(not f.c.resolution_runner.has_pending_hand_card_choice() and f.u.is_druid_transformed() and f.u.mana_zone.is_empty(), "canopy zero selection transforms without moving itself to mana (transformed %s, mana %d)" % [f.u.is_druid_transformed(), f.u.mana_zone.size()])


# Catches current-mana covenant values, root use, global graft production, and the old two-strike graft shortcut.
func _test_covenant_and_graft() -> void:
	var f := _fixture("druid_bloodwood_covenant", false)
	var ally := _ally(f.c, f.u)
	f.u.gain_mana(3, {"controller": f.c})
	_expect(ally != null and f.c.play_card(f.u, f.card, [ally]), "covenant can target another ally")
	_expect(ally.get_status_damage_bonus() == 3 and ally.has_status("druid_root"), "covenant grants current-mana bonus and roots ally")
	f = _fixture("druid_bloodwood_covenant", true)
	f.u.add_status(_root())
	f.enemy.add_status(_root())
	var before: int = f.enemy.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "covenant inverse strikes")
	_expect(f.enemy.get_current_health() <= before - 8, "covenant inverse snapshots four bonus per rooted in-range character")
	_expect(f.u.discard_pile.has(f.card), "covenant inverse does not enter mana")

	f = _fixture("druid_overgrowth_graft", false)
	f.enemy.add_status(_root())
	_expect(f.c.play_card(f.u, f.card, [f.u]), "graft upright can target self")
	_expect(f.u.has_status("druid_root") and f.u.mana_zone.has(f.card), "graft roots target and explicitly enters owner's mana")
	_expect(f.card.effect.get_mana_production(f.u, f.card, {"controller": f.c}) == 2, "graft replaces default production with global living-root count")
	_test_graft_follow_up_boundaries()
	_test_graft_descendant_and_root_boundaries()


# Catches charging mana after a target dies and bypassing the required rooted third strike.
func _test_graft_follow_up_boundaries() -> void:
	var f := _fixture("druid_overgrowth_graft", true)
	f.u.character_state.flat_damage_bonus = 0
	f.u.character_state.strength_bonus = -f.u.character_state.character_data.base_strength
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	f.u.set_current_health(maxi(1, f.u.get_max_health() - 12))
	var ordinary_profile: StrikeProfile = f.u.build_strike_profile_object()
	var ordinary_strike: int = ordinary_profile.primary_base_damage + ordinary_profile.primary_damage_bonus
	var ordinary_target_before: int = f.enemy.get_current_health()
	var ordinary_health_before: int = f.u.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft full three-strike ordinary weapon fixture resolves")
	_expect(ordinary_target_before - f.enemy.get_current_health() == ordinary_strike * 3, "graft deals exactly three ordinary weapon strikes with no attribute bonus (expected %d actual %d)" % [ordinary_strike * 3, ordinary_target_before - f.enemy.get_current_health()])
	_expect(f.u.get_current_health() - ordinary_health_before == ordinary_strike, "graft heals exactly the third strike's actual damage, not all three strikes (expected %d actual %d)" % [ordinary_strike, f.u.get_current_health() - ordinary_health_before])

	f = _fixture("druid_overgrowth_graft", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	f.u.set_current_health(maxi(1, f.u.get_max_health() - 10))
	var health_before: int = f.u.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft inverse starts its chained strikes")
	_expect(f.u.get_available_mana() == 0 and not f.u.has_status("druid_root"), "graft pays exactly two mana then consumes the nearest root")
	_expect(f.u.get_current_health() > health_before and f.u.discard_pile.has(f.card), "only the completed third strike lifesteals and inverse graft discards")

	f = _fixture("druid_overgrowth_graft", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	f.enemy.set_current_health(1)
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft may kill on its first strike")
	_expect(f.u.get_available_mana() == 2 and f.u.has_status("druid_root"), "a dead target prevents later mana payment and root consumption")


func _test_graft_descendant_and_root_boundaries() -> void:
	var f := _fixture("druid_overgrowth_graft", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	var killer := AfterStrikeTargetMutationStatus.new()
	f.u.add_status(killer)
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft starts when a post-strike descendant kills target")
	_expect(f.u.get_available_mana() == 2 and f.u.has_status("druid_root"), "after-strike death settles before graft can pay or consume root")

	f = _fixture("druid_overgrowth_graft", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	var mover := AfterStrikeTargetMutationStatus.new()
	mover.move_target = true
	f.u.add_status(mover)
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft starts when a post-strike descendant moves target")
	_expect(f.u.get_available_mana() == 2 and f.u.has_status("druid_root"), "after-strike movement outside range stops later graft costs")

	f = _fixture("druid_overgrowth_graft", true)
	f.u.gain_mana(2, {"controller": f.c})
	f.u.add_status(_root())
	f.enemy.gain_armor(999)
	f.u.set_current_health(maxi(1, f.u.get_max_health() - 8))
	var armored_health_before: int = f.u.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft continues through fully armored strikes")
	_expect(f.u.get_available_mana() == 0 and not f.u.has_status("druid_root") and f.u.get_current_health() == armored_health_before, "graft charges and consumes root despite zero damage; only actual third damage heals")

	f = _fixture("druid_overgrowth_graft", true)
	if f.c.enemy_units.size() < 2:
		_expect(false, "graft tie fixture needs two enemies")
		return
	var tied := f.c.enemy_units[1] as BattleUnitState
	tied.is_deployed = true
	tied.set_hex_cell(Vector2i(4, 5), f.c.map_data)
	tied.statuses.clear()
	f.enemy.add_status(_root())
	tied.add_status(_root())
	f.u.gain_mana(2, {"controller": f.c})
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "graft resolves deterministic equal-distance roots")
	var expected_removed: BattleUnitState = f.enemy if f.enemy.unit_id < tied.unit_id else tied
	var expected_kept: BattleUnitState = tied if expected_removed == f.enemy else f.enemy
	_expect(not expected_removed.has_status("druid_root") and expected_kept.has_status("druid_root"), "graft consumes the lowest unit ID among equally near roots")


func _test_multiple_mana_zone_copies() -> void:
	var f := _fixture("druid_binding_enchantment", false)
	var copy := (load("res://resources/cards/druid_binding_enchantment.tres") as CardData).duplicate(true) as CardData
	f.u.mana_zone.assign([f.card, copy])
	_add_draws(f.u, 2)
	f.u.notify_zone_turn_start({"controller": f.c, "zone_name": "mana"})
	_expect(f.u.hand.size() == 3, "each binding mana-zone copy draws once on its owner's turn start")


func _fixture(card_id: String, inverted: bool) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var druid: BattleUnitState = null
	for unit in controller.player_units:
		if unit.is_druid():
			druid = unit
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = druid
	druid.is_deployed = true
	druid.set_hex_cell(Vector2i(4, 4), controller.map_data)
	druid.current_ap = 10
	druid.hand.clear()
	druid.draw_pile.clear()
	druid.discard_pile.clear()
	druid.mana_zone.clear()
	druid.statuses.clear()
	druid.clear_mana()
	druid.set_druid_transformed(inverted)
	var card := (load("res://resources/cards/%s.tres" % card_id) as CardData).duplicate(true) as CardData
	druid.hand.append(card)
	var enemy: BattleUnitState = controller.enemy_units[0]
	enemy.statuses.clear()
	enemy.set_hex_cell(Vector2i(5, 4), controller.map_data)
	enemy.set_current_health(enemy.get_max_health())
	return {"c": controller, "u": druid, "card": card, "enemy": enemy}


func _add_draws(unit: BattleUnitState, count: int) -> void:
	for index in range(count):
		unit.draw_pile.append(_dummy_card("draw%d" % index))


func _dummy_card(label: String) -> CardData:
	var card := CardData.new()
	card.card_name = label
	return card


func _root() -> StatusEffect:
	return (load("res://scripts/status/druid_root_status.gd") as GDScript).new() as StatusEffect


func _ally(controller: BattleController, owner: BattleUnitState) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != owner:
			unit.is_deployed = true
			unit.set_hex_cell(Vector2i(4, 5), controller.map_data)
			return unit
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_REWORK_CARDS: " + message)
