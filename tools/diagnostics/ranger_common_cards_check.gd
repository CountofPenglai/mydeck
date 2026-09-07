extends Node

class PursuitAfterStrikeSourceStatus extends StatusEffect:
	var controller: BattleController
	var cell: Vector2i
	var combo_during_hook: int = -1
	func on_after_strike(unit: BattleUnitState, _context: Dictionary = {}) -> void:
		combo_during_hook = unit.ranger_state.combo_points
		controller.surface_state.remove_residue(cell, BattleSurfaceState.Element.FIRE)
		controller.surface_state.add_residue(cell, BattleSurfaceState.Element.WATER, controller.battle_round)


class PreparationHandHooks extends StatusEffect:
	var preparation_discards := 0
	var preparation_draws := 0

	func on_card_discarded(_unit: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
		if str(context.get("reason", "")) == "ranger_stealth_preparation":
			preparation_discards += 1

	func on_card_drawn(_unit: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
		if str(context.get("reason", "")) == "ranger_stealth_preparation":
			preparation_draws += 1

const FARTHEST_PATH := "res://resources/cards/ranger_farthest_arrow.tres"
const PURSUIT_PATH := "res://resources/cards/ranger_surface_pursuit.tres"
const PREPARATION_PATH := "res://resources/cards/ranger_stealth_preparation.tres"
const PREPARATION_STACK_PATH := "res://resources/cards/ranger_stealth_preparation_stack.tres"

var _exit_code := 0


func _ready() -> void:
	_test_resources()
	_test_farthest_actual_target_modes()
	_test_farthest_paid_distance_two_damage()
	_test_surface_pursuit_modes_and_collection()
	_test_farthest_selected_target_and_universal_preview()
	_test_wind_range_and_object_strikes()
	_test_object_only_targetless_combo_availability()
	_test_fixed_component_payment_rejections()
	_test_pursuit_after_strike_source_order_and_combo_finish()
	_test_lethal_cistern_final_cell_evidence()
	await _test_live_scene_combo_targeting()
	_test_pursuit_advanced_zero_and_kill_collection()
	_test_stealth_preparation_resource()
	_test_stealth_preparation_actual_discards_and_next_turn_ap()
	await _test_live_stealth_preparation_ordered_discard_buttons()
	print("RANGER_COMMON_CARDS: completed")
	get_tree().quit(_exit_code)


func _test_resources() -> void:
	var farthest := load(FARTHEST_PATH) as CardData
	var pursuit := load(PURSUIT_PATH) as CardData
	_expect(farthest != null, "farthest arrow resource is missing")
	_expect(pursuit != null, "surface pursuit resource is missing")
	if farthest != null:
		_expect(farthest.card_name == "尽程一矢", "farthest arrow name")
		_expect(farthest.rarity == CardEnums.Rarity.COMMON and farthest.ap_cost == 2, "farthest arrow common 2 AP")
		_expect(farthest.card_text == "连击：目标与你的距离等于远程配件对该目标的实际射程。使用远程配件进行1次获得+X伤害加值的武器打击，X等于你与目标的距离-1，最高为+3。", "farthest arrow text")
	if pursuit != null:
		_expect(pursuit.card_name == "踏境追刃", "surface pursuit name")
		_expect(pursuit.rarity == CardEnums.Rarity.COMMON and pursuit.ap_cost == 2, "surface pursuit common 2 AP")
		_expect(pursuit.card_text == "连击：你位于元素地表。使用近战配件进行1次武器打击，然后额外采集你所在格中的元素。", "surface pursuit text")


func _test_stealth_preparation_resource() -> void:
	var preparation := load(PREPARATION_PATH) as CardData
	var preparation_stack := load(PREPARATION_STACK_PATH) as CardStack
	_expect(preparation != null, "stealth preparation resource is missing")
	_expect(preparation_stack != null and preparation_stack.card_data == preparation and preparation_stack.count == 1, "stealth preparation standalone stack resource loads")
	if preparation == null:
		return
	_expect(preparation.card_name == "潜踪整备", "stealth preparation name")
	_expect(preparation.rarity == CardEnums.Rarity.COMMON and preparation.ap_cost == 1, "stealth preparation common 1 AP")
	_expect(preparation.card_text == "选择并弃置至多2张其他手牌，然后抽等量牌。进入潜行。你的下回合开始时，获得1 AP。", "stealth preparation canonical text")
	_expect(preparation.get_description_for_context().contains("潜行"), "stealth preparation display text getter")
	var catalog := load("res://resources/adventure_reward_catalog.tres") as AdventureRewardCatalog
	_expect(catalog != null, "adventure reward catalog loads")
	if catalog != null:
		for path in [FARTHEST_PATH, PURSUIT_PATH, PREPARATION_PATH]:
			var expected := load(path) as CardData
			_expect(expected != null and catalog.cards.has(expected), "reward catalog registers %s" % path)
	var service := AdventureRewardService.new()
	service._ensure_catalog()
	var ranger_rewards := service._cards_for_class(CardEnums.CardClass.RANGER)
	for path in [FARTHEST_PATH, PURSUIT_PATH, PREPARATION_PATH]:
		var reward_card := load(path) as CardData
		_expect(reward_card != null and reward_card.can_appear_in_rewards() and ranger_rewards.has(reward_card), "COMMON reward query exposes %s" % path)
	var starter := load("res://resources/characters/battle_ranger_state.tres") as CharacterState
	_expect(starter != null and starter.deck.size() == 3 and _starter_count(starter, "险步突袭") == 5 and _starter_count(starter, "猎影穿行") == 2 and _starter_count(starter, "透支灵感") == 1, "ranger starter remains exactly 5 perilous + 2 shadow + 1 overdrawn")


func _test_stealth_preparation_actual_discards_and_next_turn_ap() -> void:
	for discard_count in [0, 1, 2]:
		var fixture := _fixture(Vector2i(1, 3), Vector2i(2, 3))
		var hooks := PreparationHandHooks.new()
		hooks.status_id = "preparation_hand_hooks"
		hooks.stacks = 1
		fixture.r.add_status(hooks)
		var preparation := _hand_card(fixture.r, PREPARATION_PATH)
		var selected: Array[CardData] = []
		for index in range(discard_count):
			var other := _hand_card(fixture.r, FARTHEST_PATH)
			selected.append(other)
			fixture.r.draw_pile.append((load(PURSUIT_PATH) as CardData).duplicate(true) as CardData)
		var ap: int = fixture.r.current_ap
		_expect(fixture.c.play_card(fixture.r, preparation, [fixture.r], {"ordered_discard_cards": selected}), "stealth preparation %d-discard actual play" % discard_count)
		_expect(fixture.r.current_ap == ap - 1 and hooks.preparation_discards == discard_count and hooks.preparation_draws == discard_count, "stealth preparation %d uses live discard/draw hooks" % discard_count)
		_expect(fixture.r.is_stealthed() and fixture.r.get_status("ranger_next_turn_ap") != null, "stealth preparation %d enters stealth and queues AP" % discard_count)
	var invalid := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	var invalid_card := _hand_card(invalid.r, PREPARATION_PATH)
	var first := _hand_card(invalid.r, FARTHEST_PATH)
	var second := _hand_card(invalid.r, PURSUIT_PATH)
	var third := _hand_card(invalid.r, FARTHEST_PATH)
	var invalid_ap: int = invalid.r.current_ap
	_expect(not invalid.c.play_card(invalid.r, invalid_card, [invalid.r], {"ordered_discard_cards": [first, first]}) and invalid.r.current_ap == invalid_ap and invalid.r.hand.has(invalid_card), "stealth preparation duplicate rejects before payment")
	_expect(not invalid.c.play_card(invalid.r, invalid_card, [invalid.r], {"ordered_discard_cards": [invalid_card]}) and invalid.r.current_ap == invalid_ap and invalid.r.hand.has(invalid_card), "stealth preparation source card rejects before payment")
	_expect(not invalid.c.play_card(invalid.r, invalid_card, [invalid.r], {"ordered_discard_cards": [first, second, third]}) and invalid.r.current_ap == invalid_ap and invalid.r.hand.has(invalid_card), "stealth preparation over-limit rejects before payment")
	invalid.r.hand.erase(second)
	_expect(not invalid.c.play_card(invalid.r, invalid_card, [invalid.r], {"ordered_discard_cards": [second]}) and invalid.r.current_ap == invalid_ap and invalid.r.hand.has(invalid_card), "stealth preparation stale card rejects before payment")
	var stacked := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	var first_preparation := _hand_card(stacked.r, PREPARATION_PATH)
	var second_preparation := _hand_card(stacked.r, PREPARATION_PATH)
	_expect(stacked.c.play_card(stacked.r, first_preparation, [stacked.r], {"ordered_discard_cards": []}), "first preparation queues AP")
	stacked.r.leave_stealth()
	_expect(stacked.c.play_card(stacked.r, second_preparation, [stacked.r], {"ordered_discard_cards": []}), "second preparation queues AP after stealth breaks")
	var pending: StatusEffect = stacked.r.get_status("ranger_next_turn_ap")
	_expect(pending != null and pending.stacks == 2, "preparation AP status stacks independently of stealth")
	stacked.c.current_unit = stacked.e
	stacked.c._resolve_turn_start_action(stacked.e)
	stacked.c.resolve_effect_queue()
	_expect(stacked.r.get_status("ranger_next_turn_ap") != null, "enemy turn does not consume ranger preparation AP")
	stacked.c.current_unit = stacked.r
	stacked.c._resolve_turn_start_action(stacked.r)
	stacked.c.resolve_effect_queue()
	stacked.c._finish_turn_start_action(stacked.r)
	_expect(stacked.r.current_ap == stacked.r.get_max_ap(stacked.c.config) + 2 and stacked.r.get_status("ranger_next_turn_ap") == null, "next own turn grants stacked AP after refill exactly once")
	stacked.c.current_unit = stacked.r
	stacked.c._resolve_turn_start_action(stacked.r)
	stacked.c.resolve_effect_queue()
	_expect(stacked.r.current_ap == stacked.r.get_max_ap(stacked.c.config), "second subsequent own turn does not repeat preparation AP")


func _test_live_stealth_preparation_ordered_discard_buttons() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	_expect(packed != null, "battle scene exists for preparation discard UI")
	if packed == null:
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(3):
		await get_tree().process_frame
	var controller := scene.controller
	var ranger := _find_ranger(controller)
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.current_ap = 9
	ranger.turn_serial = 1
	ranger.is_deployed = true
	var cancelled := _hand_card(ranger, PREPARATION_PATH)
	var cancelled_ap: int = ranger.current_ap
	var cancelled_discard_size: int = ranger.discard_pile.size()
	scene._select_card_with_mode(cancelled, CardEnums.CardPlayMode.NORMAL)
	_expect(scene._ordered_discard_popup.visible, "live preparation selection opens ordered-discard popup even with zero selection")
	var cancel_button := _find_button(scene._ordered_discard_popup, "取消")
	_expect(cancel_button != null, "live preparation popup exposes actual Cancel button")
	if cancel_button != null:
		cancel_button.emit_signal("pressed")
	await get_tree().process_frame
	_expect(ranger.current_ap == cancelled_ap and ranger.hand.has(cancelled) and ranger.discard_pile.size() == cancelled_discard_size and not ranger.is_stealthed(), "live preparation Cancel causes no mutation")
	var confirmed := _hand_card(ranger, PREPARATION_PATH)
	var selected := _hand_card(ranger, FARTHEST_PATH)
	ranger.draw_pile.append((load(PURSUIT_PATH) as CardData).duplicate(true) as CardData)
	scene._select_card_with_mode(confirmed, CardEnums.CardPlayMode.NORMAL)
	var selected_button := _find_button(scene._ordered_discard_popup, selected.card_name)
	var confirm_button := _find_button(scene._ordered_discard_popup, "确认")
	_expect(selected_button != null and confirm_button != null, "live preparation popup exposes actual selection and Confirm buttons")
	if selected_button != null:
		selected_button.emit_signal("pressed")
	if confirm_button != null:
		confirm_button.emit_signal("pressed")
	await get_tree().process_frame
	_expect(not ranger.hand.has(confirmed) and ranger.discard_pile.has(selected) and ranger.is_stealthed(), "live preparation Confirm discards, resolves once, and enters stealth")
	var discard_count: int = ranger.discard_pile.count(selected)
	if confirm_button != null:
		confirm_button.emit_signal("pressed")
	await get_tree().process_frame
	_expect(ranger.discard_pile.count(selected) == discard_count, "live preparation Confirm cannot resolve a second time")
	scene.queue_free()


func _test_farthest_actual_target_modes() -> void:
	var normal := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(normal.r, "ranger_dagger_crossbow")
	var normal_card := _hand_card(normal.r, FARTHEST_PATH)
	var normal_ap: int = normal.r.current_ap
	_expect(normal.c.play_card(normal.r, normal_card, [normal.e]), "farthest arrow ordinary near target plays")
	_expect(normal.r.current_ap == normal_ap - 2 and normal.r.discard_pile.has(normal_card), "farthest arrow ordinary payment")
	var far := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_set_weapon(far.r, "ranger_dagger_crossbow")
	far.r.ranger_state.combo_window_open = true
	var far_card := _hand_card(far.r, FARTHEST_PATH)
	var far_ap: int = far.r.current_ap
	_expect(far.c.can_preview_card_targets(far.r, far_card, [far.e], "paired", CardEnums.CardPlayMode.COMBO), "farthest arrow combo preview at actual range")
	_expect(far.c.play_card(far.r, far_card, [far.e], {}, CardEnums.CardPlayMode.COMBO), "farthest arrow combo plays at actual range")
	_expect(far.r.current_ap == far_ap, "farthest arrow combo is free")
	var closed := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_set_weapon(closed.r, "ranger_dagger_crossbow")
	var closed_card := _hand_card(closed.r, FARTHEST_PATH)
	_expect(not closed.c.play_card(closed.r, closed_card, [closed.e], {}, CardEnums.CardPlayMode.COMBO), "closed combo window rejects before payment")


func _test_farthest_paid_distance_two_damage() -> void:
	var fixture := _fixture(Vector2i(1, 3), Vector2i(3, 3))
	_set_weapon(fixture.r, "ranger_dagger_crossbow")
	fixture.e.set_current_health(99)
	var health: int = fixture.e.get_current_health()
	_expect(fixture.c.play_card(fixture.r, _hand_card(fixture.r, FARTHEST_PATH), [fixture.e]), "paid distance-two farthest arrow plays")
	_expect(fixture.e.get_current_health() == health - 7, "paid distance-two arrow applies exact +1 damage modifier")


func _test_surface_pursuit_modes_and_collection() -> void:
	var normal := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(normal.r, "ranger_dagger_crossbow")
	var normal_card := _hand_card(normal.r, PURSUIT_PATH)
	var normal_ap: int = normal.r.current_ap
	_expect(normal.c.play_card(normal.r, normal_card, [normal.e]), "surface pursuit ordinary bare-cell play")
	_expect(normal.r.current_ap == normal_ap - 2, "surface pursuit ordinary payment")
	var combo := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(combo.r, "ranger_dagger_crossbow")
	combo.c.surface_state.add_residue(combo.r.cell, BattleSurfaceState.Element.FIRE, combo.c.battle_round)
	combo.r.ranger_state.combo_window_open = true
	var combo_card := _hand_card(combo.r, PURSUIT_PATH)
	var combo_ap: int = combo.r.current_ap
	_expect(combo.c.play_card(combo.r, combo_card, [combo.e], {}, CardEnums.CardPlayMode.COMBO), "surface pursuit combo on elemental surface")
	_expect(combo.r.current_ap == combo_ap and combo.r.ranger_state.get_element_total() >= 1, "surface pursuit free combo collects own surface")


func _test_farthest_selected_target_and_universal_preview() -> void:
	var fixture := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(fixture.r, "ranger_dagger_crossbow")
	var far_enemy: BattleUnitState = fixture.c.enemy_units[1]
	far_enemy.is_deployed = true
	far_enemy.set_hex_cell(Vector2i(4, 3), fixture.c.map_data)
	fixture.r.ranger_state.combo_window_open = true
	var card := _hand_card(fixture.r, FARTHEST_PATH)
	var ap: int = fixture.r.current_ap
	_expect(fixture.c.can_play_card_with_mode(fixture.r, card, CardEnums.CardPlayMode.COMBO), "targetless combo availability finds far candidate")
	_expect(not fixture.c.can_preview_card_targets(fixture.r, card, [fixture.e], "paired", CardEnums.CardPlayMode.COMBO), "near selected target rejects despite far candidate")
	_expect(not fixture.c.play_card(fixture.r, card, [fixture.e], {}, CardEnums.CardPlayMode.COMBO) and fixture.r.current_ap == ap and fixture.r.hand.has(card), "near combo rejects before mutation")
	fixture.r.ranger_state.universal_combo_ready = true
	_expect(fixture.c.can_preview_card_targets(fixture.r, card, [fixture.e], "paired", CardEnums.CardPlayMode.COMBO), "universal combo preview bypasses target condition")
	_expect(fixture.c.play_card(fixture.r, card, [fixture.e], {}, CardEnums.CardPlayMode.COMBO), "universal combo plays near target")


func _test_wind_range_and_object_strikes() -> void:
	var wind := _fixture(Vector2i(1, 3), Vector2i(5, 3))
	_set_weapon(wind.r, "ranger_wind_hunter_pair")
	wind.r.notify_equipment_battle_started({"controller": wind.c})
	wind.r.notify_movement_completed({"controller": wind.c, "forced": false})
	_expect(_wind_action(wind.c, wind.r, BattleHexGrid.direction_index(wind.r.cell, wind.e.cell)), "wind direction setup")
	wind.r.ranger_state.combo_window_open = true
	var wind_card := _hand_card(wind.r, FARTHEST_PATH)
	_expect(wind.c.get_effective_attack_range_against(wind.r, wind.e, "paired") == 4, "downwind actual range is four")
	wind.e.set_current_health(99)
	var wind_health: int = wind.e.get_current_health()
	_expect(wind.c.play_card(wind.r, wind_card, [wind.e], {}, CardEnums.CardPlayMode.COMBO), "downwind maximum combo plays")
	_expect(wind.e.get_current_health() == wind_health - 11, "downwind farthest arrow applies its paired weapon damage plus capped +3 modifier")
	var upwind := _fixture(Vector2i(1, 3), Vector2i(5, 3))
	_set_weapon(upwind.r, "ranger_wind_hunter_pair")
	upwind.r.notify_equipment_battle_started({"controller": upwind.c})
	upwind.r.notify_movement_completed({"controller": upwind.c, "forced": false})
	_expect(_wind_action(upwind.c, upwind.r, BattleHexGrid.direction_index(upwind.e.cell, upwind.r.cell)), "upwind direction setup")
	upwind.r.ranger_state.combo_window_open = true
	var upwind_card := _hand_card(upwind.r, FARTHEST_PATH)
	var upwind_ap: int = upwind.r.current_ap
	_expect(not upwind.c.play_card(upwind.r, upwind_card, [upwind.e], {}, CardEnums.CardPlayMode.COMBO) and upwind.r.current_ap == upwind_ap and upwind.r.hand.has(upwind_card), "upwind target beyond shortened boundary rejects before payment")
	var long_wind := _fixture(Vector2i(1, 3), Vector2i(6, 3))
	_set_weapon(long_wind.r, "ranger_wind_hunter_pair")
	long_wind.r.character_state.weapon_equipment.paired_component.attack_range = 4
	long_wind.r.notify_equipment_battle_started({"controller": long_wind.c})
	long_wind.r.notify_movement_completed({"controller": long_wind.c, "forced": false})
	_expect(_wind_action(long_wind.c, long_wind.r, BattleHexGrid.direction_index(long_wind.r.cell, long_wind.e.cell)), "long downwind direction setup")
	long_wind.r.ranger_state.combo_window_open = true
	long_wind.e.set_current_health(99)
	var long_health: int = long_wind.e.get_current_health()
	_expect(long_wind.c.get_effective_attack_range_against(long_wind.r, long_wind.e, "paired") == 5 and long_wind.c.play_card(long_wind.r, _hand_card(long_wind.r, FARTHEST_PATH), [long_wind.e], {}, CardEnums.CardPlayMode.COMBO), "range-greater-than-four downwind maximum combo plays")
	_expect(long_wind.e.get_current_health() == long_health - 11, "range-greater-than-four arrow damage remains capped at +3")
	var object_fixture := _fixture(Vector2i(1, 3), Vector2i(3, 3))
	_set_weapon(object_fixture.r, "ranger_dagger_crossbow")
	var object: BattleObjectState = object_fixture.c.spawn_battle_object(BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(4, 3)) as BattleObjectState
	object.current_health = 99
	var health: int = object.current_health
	_expect(object_fixture.c.play_card(object_fixture.r, _hand_card(object_fixture.r, FARTHEST_PATH), [object]), "farthest arrow object play")
	_expect(object.current_health == health - 8, "farthest arrow object exact paired strike damage including distance modifier")
	var pursuit_object: BattleObjectState = object_fixture.c.spawn_battle_object(BattleObjectDefinition.Kind.WATER_CISTERN, Vector2i(2, 3)) as BattleObjectState
	pursuit_object.current_health = 99
	object_fixture.r.ranger_state.element_inventory.clear()
	object_fixture.c.apply_base_surface_element(object_fixture.r.cell, BattleSurfaceState.Element.FIRE, {"diagnostic": "pursuit object"})
	_expect(object_fixture.c.surface_state.get_readable_elements(object_fixture.r.cell).has(BattleSurfaceState.Element.FIRE), "pursuit object fixture has readable own fire")
	var elements: int = object_fixture.r.ranger_state.get_element_total()
	_expect(object_fixture.c.play_card(object_fixture.r, _hand_card(object_fixture.r, PURSUIT_PATH), [pursuit_object]), "surface pursuit object play")
	_expect(object_fixture.r.ranger_state.get_element_total() > elements, "surface pursuit object collects own cell total=%d before=%d" % [object_fixture.r.ranger_state.get_element_total(), elements])


func _test_object_only_targetless_combo_availability() -> void:
	var fixture := _fixture(Vector2i(1, 3), Vector2i(6, 3))
	_set_weapon(fixture.r, "ranger_dagger_crossbow")
	fixture.e.is_deployed = false
	var target: BattleObjectState = fixture.c.spawn_battle_object(BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(4, 3)) as BattleObjectState
	fixture.r.ranger_state.combo_window_open = true
	var card := _hand_card(fixture.r, FARTHEST_PATH)
	_expect(fixture.c.can_play_card_with_mode(fixture.r, card, CardEnums.CardPlayMode.COMBO), "object-only maximum target enables combo mode")
	_expect(fixture.c.can_preview_card_targets(fixture.r, card, [target], "paired", CardEnums.CardPlayMode.COMBO), "object-only maximum target previews")


func _test_fixed_component_payment_rejections() -> void:
	var missing := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(missing.r, "ranger_dagger_crossbow")
	missing.r.character_state.weapon_equipment.paired_component = null
	var missing_card := _hand_card(missing.r, FARTHEST_PATH)
	var missing_ap: int = missing.r.current_ap
	_expect(not missing.c.play_card(missing.r, missing_card, [missing.e]) and missing.r.current_ap == missing_ap and missing.r.hand.has(missing_card), "missing raw paired component rejects before payment")
	var wrong := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(wrong.r, "ranger_dagger_crossbow")
	wrong.r.ranger_state.active_weapon_lock_slot = "weapon"
	var locked_card := _hand_card(wrong.r, FARTHEST_PATH)
	var locked_ap: int = wrong.r.current_ap
	_expect(not wrong.c.play_card(wrong.r, locked_card, [wrong.e]) and wrong.r.current_ap == locked_ap and wrong.r.hand.has(locked_card), "locked paired slot rejects before payment")
	var wrong_range := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(wrong_range.r, "ranger_dagger_crossbow")
	var wrong_card := _hand_card(wrong_range.r, PURSUIT_PATH)
	wrong_range.r.character_state.weapon_equipment.range_type = EquipmentData.WeaponRangeType.RANGED
	var wrong_ap: int = wrong_range.r.current_ap
	_expect(not wrong_range.c.play_card(wrong_range.r, wrong_card, [wrong_range.e]) and wrong_range.r.current_ap == wrong_ap and wrong_range.r.hand.has(wrong_card), "wrong raw weapon range type rejects before payment")


func _test_pursuit_after_strike_source_order_and_combo_finish() -> void:
	var fixture := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(fixture.r, "ranger_dagger_crossbow")
	fixture.c.surface_state.add_residue(fixture.r.cell, BattleSurfaceState.Element.FIRE, fixture.c.battle_round)
	var observer := PursuitAfterStrikeSourceStatus.new()
	observer.status_id = "pursuit_after_strike_source"
	observer.stacks = 1
	observer.controller = fixture.c
	observer.cell = fixture.r.cell
	fixture.r.add_status(observer)
	fixture.r.ranger_state.combo_points = 2
	fixture.r.ranger_state.combo_window_open = true
	_expect(fixture.c.play_card(fixture.r, _hand_card(fixture.r, PURSUIT_PATH), [fixture.e], {}, CardEnums.CardPlayMode.COMBO), "pursuit combo plays with after-strike source observer")
	_expect(observer.combo_during_hook == 2 and int(fixture.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.WATER, 0)) == 1 and int(fixture.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.FIRE, 0)) == 0 and fixture.r.ranger_state.combo_points == 3, "after-strike descendant replaces source before collection and combo increments only on card finish")


func _test_lethal_cistern_final_cell_evidence() -> void:
	var fixture := _fixture(Vector2i(1, 3), Vector2i(3, 3))
	_set_weapon(fixture.r, "ranger_dagger_crossbow")
	fixture.c.surface_state.add_residue(fixture.r.cell, BattleSurfaceState.Element.FIRE, fixture.c.battle_round)
	var cistern := fixture.c.spawn_battle_object(BattleObjectDefinition.Kind.WATER_CISTERN, Vector2i(2, 3)) as BattleObjectState
	cistern.current_health = 1
	var origin: Vector2i = fixture.r.cell
	_expect(fixture.c.play_card(fixture.r, _hand_card(fixture.r, PURSUIT_PATH), [cistern]), "lethal cistern pursuit plays")
	_expect(fixture.c.surface_state.get_air_effect(origin) == BattleSurfaceState.Element.STEAM and fixture.r.cell != origin and not fixture.c.surface_state.get_collectible_entries(origin, "unit:%d" % fixture.r.unit_id).is_empty() and fixture.c.surface_state.get_collectible_entries(fixture.r.cell, "unit:%d" % fixture.r.unit_id).is_empty() and fixture.r.ranger_state.get_element_total() == 0, "lethal cistern leaves original STEAM uncollected after forced movement makes the final Ranger cell empty")


func _test_live_scene_combo_targeting() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	_expect(packed != null, "battle scene exists for live combo mode")
	if packed == null:
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(3):
		await get_tree().process_frame
	var controller := scene.controller
	var ranger := _find_ranger(controller)
	var near: BattleUnitState = controller.enemy_units[0]
	var far: BattleUnitState = controller.enemy_units[1]
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.current_ap = 9
	ranger.turn_serial = 1
	ranger.is_deployed = true
	near.is_deployed = true
	far.is_deployed = true
	ranger.set_hex_cell(Vector2i(1, 3), controller.map_data)
	near.set_hex_cell(Vector2i(3, 3), controller.map_data)
	far.set_hex_cell(Vector2i(4, 3), controller.map_data)
	_set_weapon(ranger, "ranger_dagger_crossbow")
	ranger.ranger_state.combo_window_open = true
	var card := _hand_card(ranger, FARTHEST_PATH)
	var modes := scene._available_hand_play_modes(card)
	_expect(modes.has(CardEnums.CardPlayMode.COMBO), "live mode popup offers enabled farthest-arrow combo")
	scene._select_card_with_mode(card, CardEnums.CardPlayMode.COMBO)
	_expect(scene.input_mode == BattleScene.InputMode.CARD_TARGET and scene.pending_card == card, "live combo selection enters target mode")
	scene._handle_card_target(near.cell, near)
	_expect(scene.pending_card == card and ranger.hand.has(card), "live combo targeting denies near target")
	scene._handle_card_target(far.cell, far)
	_expect(scene.pending_card == null and not ranger.hand.has(card), "live combo targeting accepts legal far target")
	scene.queue_free()


func _test_pursuit_advanced_zero_and_kill_collection() -> void:
	var advanced := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(advanced.r, "ranger_dagger_crossbow")
	advanced.c.apply_advanced_surface(advanced.r.cell, BattleSurfaceState.Element.ICE)
	advanced.e.gain_armor(99)
	var health: int = advanced.e.get_current_health()
	advanced.r.ranger_state.combo_window_open = true
	var before: int = advanced.r.ranger_state.get_element_total()
	_expect(advanced.c.play_card(advanced.r, _hand_card(advanced.r, PURSUIT_PATH), [advanced.e], {}, CardEnums.CardPlayMode.COMBO), "advanced surface enables pursuit combo")
	_expect(advanced.e.get_current_health() == health and advanced.r.ranger_state.get_element_total() > before, "advanced alone enables combo while armor reduces health damage to zero and collection succeeds")
	var lethal := _fixture(Vector2i(1, 3), Vector2i(2, 3))
	_set_weapon(lethal.r, "ranger_dagger_crossbow")
	lethal.c.surface_state.add_residue(lethal.r.cell, BattleSurfaceState.Element.FIRE, lethal.c.battle_round)
	lethal.e.set_current_health(1)
	var lethal_before: int = lethal.r.ranger_state.get_element_total()
	_expect(lethal.c.play_card(lethal.r, _hand_card(lethal.r, PURSUIT_PATH), [lethal.e]), "lethal pursuit plays")
	_expect(not lethal.e.is_alive() and lethal.r.ranger_state.get_element_total() > lethal_before, "lethal pursuit still collects own source")


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
	return {"c": controller, "r": ranger, "e": enemy}


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit.is_ranger():
			return unit
	return null


func _set_weapon(ranger: BattleUnitState, name: String) -> void:
	ranger.character_state.weapon_equipment = (load("res://resources/items/%s.tres" % name) as EquipmentData).duplicate(true) as EquipmentData
	ranger.character_state.weapon_face = 0
	ranger.equipment_runtime_states.clear()


func _hand_card(ranger: BattleUnitState, path: String) -> CardData:
	var card := (load(path) as CardData).duplicate(true) as CardData
	ranger.hand.append(card)
	return card


func _find_button(root: Node, label: String) -> Button:
	if root == null:
		return null
	if root is Button and ((root as Button).text == label or (root as Button).text.begins_with(label + " |")):
		return root as Button
	for child in root.get_children():
		var found := _find_button(child as Node, label)
		if found != null:
			return found
	return null


func _starter_count(starter: CharacterState, card_name: String) -> int:
	if starter == null:
		return 0
	var count := 0
	for stack: CardStack in starter.deck:
		if stack != null and stack.card_data != null and stack.card_data.card_name == card_name:
			count += stack.count
	return count


func _wind_action(controller: BattleController, ranger: BattleUnitState, direction: int) -> bool:
	var action_id := "wind_%d" % direction
	for action in ranger.get_equipment_actions({"controller": controller, "unit": ranger, "phase": "battle"}):
		if str(action.get("action_id", "")) != action_id:
			continue
		var effect := action.get("effect") as EquipmentEffect
		return effect != null and effect.activate(ranger, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {"controller": controller, "unit": ranger, "equipment_action_id": action_id, "phase": "battle"})
	return false


func _expect(value: bool, message: String) -> void:
	if value:
		return
	_exit_code = 1
	push_error("RANGER_COMMON_CARDS: " + message)
	print("ERROR: " + message)
