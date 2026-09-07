extends Node

const BOTTLE_PATH := "res://resources/cards/ranger_exotic_bottle.tres"

var _exit_code := 0

func _ready() -> void:
	await _test_live_scene_choice_cancel_and_submit()
	_test_empty_inventory_collects_and_loads()
	_test_full_inventory_temporary_batch_is_not_capped()
	_test_old_inventory_cannot_supply_payload()
	_test_leftover_is_stored_without_double_counting()
	_test_same_cell_duplicate_sources_yield_one_component()
	_test_advanced_source_splits_and_cannot_be_recollected()
	_test_damage_uses_8_4_plus_agility()
	_test_range_uses_paired_profile()
	_test_upwind_range_rejects_beyond_shortened_boundary()
	print("RANGER_BOTTLE_DIAG: completed")
	get_tree().quit(_exit_code)

func _test_live_scene_choice_cancel_and_submit() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("live UI: battle scene missing")
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(5):
		await get_tree().process_frame
	var c := scene.controller
	var r := _find_ranger(c)
	c.phase = BattleController.Phase.BATTLE
	c.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	c.current_unit = r
	r.current_ap = 9
	r.is_deployed = true
	r.set_hex_cell(Vector2i(1, 3), c.map_data)
	_seed_residue(c, r.cell, BattleSurfaceState.Element.FIRE)
	var cancel_card := _hand_card(r)
	scene._select_card(cancel_card)
	await get_tree().process_frame
	if not scene._ranger_blend_popup.visible or scene._ranger_blend_popup.title != "异域爆瓶：选择载荷":
		_fail("live UI: bottle load popup did not open")
	else:
		var cancel := _popup_button(scene._ranger_blend_list, "取消")
		if cancel == null:
			_fail("live UI: recipe cancel button was not displayed")
		else:
			cancel.emit_signal("pressed")
			await get_tree().process_frame
		if scene._ranger_blend_popup.visible or scene._ranger_recipe_card != null or scene.pending_card != null or r.ranger_state.elements_collected_this_turn != 0 or r.current_ap != 9:
			_fail("live UI: cancel mutated pending state, collection, or AP")
	var submit_card := _hand_card(r)
	scene._select_card(submit_card)
	await get_tree().process_frame
	var option := _first_popup_option(scene._ranger_blend_list)
	if option == null:
		_fail("live UI: no clickable payload option")
	else:
		option.emit_signal("pressed")
		await get_tree().process_frame
		if scene.input_mode != BattleScene.InputMode.CARD_TARGET:
			_fail("live UI: payload confirmation did not continue to AREA targeting")
		else:
			scene._handle_card_target(Vector2i(4, 3), null)
			if submit_card in r.hand or r.current_ap != 7:
				_fail("live UI: AREA submission did not execute exactly once")
	var hidden_card := _hand_card(r)
	scene._select_card(hidden_card)
	await get_tree().process_frame
	scene._ranger_blend_popup.hide()
	await get_tree().process_frame
	if scene._ranger_recipe_card != null or scene.pending_card != null:
		_fail("live UI: popup hide left a pending bottle recipe")
	scene.queue_free()


func _popup_button(list: VBoxContainer, text: String) -> Button:
	for child in list.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
	return null


func _first_popup_option(list: VBoxContainer) -> Button:
	for child in list.get_children():
		var button := child as Button
		if button != null and button.text != "取消":
			return button
	return null

func _test_empty_inventory_collects_and_loads() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_seed_residue(f.c, Vector2i(1, 3), BattleSurfaceState.Element.FIRE)
	var card := _hand_card(f.r)
	var ap: int = f.r.current_ap
	var extra := {"bottle_payload": [BattleSurfaceState.Element.FIRE]}
	if not f.c.play_card(f.r, card, [f.e.cell], extra, CardEnums.CardPlayMode.NORMAL):
		_fail("empty inventory: collectible surface did not permit actual bottle play")
		return
	if f.r.current_ap != ap - 2 or f.r.ranger_state.elements_collected_this_turn != 1 or f.c.surface_state.get_element(f.e.cell) != BattleSurfaceState.Element.FIRE:
		_fail("empty inventory: AP/counter/final payload wrong ap=%d collected=%d surface=%d" % [f.r.current_ap, f.r.ranger_state.elements_collected_this_turn, f.c.surface_state.get_element(f.e.cell)])

func _test_full_inventory_temporary_batch_is_not_capped() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	for _index in range(f.r.ranger_state.ELEMENT_LIMIT):
		f.r.ranger_state.add_element(BattleSurfaceState.Element.WATER)
	f.r.ranger_state.elements_collected_this_turn = 0
	_seed_residue(f.c, Vector2i(1, 3), BattleSurfaceState.Element.FIRE)
	_seed_residue(f.c, Vector2i(2, 3), BattleSurfaceState.Element.EARTH)
	var card := _hand_card(f.r)
	if not f.c.play_card(f.r, card, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("full inventory: temporary batch could not load payload")
		return
	if f.r.ranger_state.elements_collected_this_turn != 2:
		_fail("full inventory: collection batch counted %d instead of 2" % f.r.ranger_state.elements_collected_this_turn)

func _test_old_inventory_cannot_supply_payload() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	f.r.ranger_state.add_element(BattleSurfaceState.Element.FIRE)
	var card := _hand_card(f.r)
	var ap: int = f.r.current_ap
	if f.c.play_card(f.r, card, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL) or f.r.current_ap != ap or not f.r.hand.has(card):
		_fail("old inventory: stale inventory supplied bottle payload or mutated payment")

func _test_leftover_is_stored_without_double_counting() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_seed_residue(f.c, Vector2i(1, 3), BattleSurfaceState.Element.FIRE)
	_seed_residue(f.c, Vector2i(2, 3), BattleSurfaceState.Element.EARTH)
	var card := _hand_card(f.r)
	if not f.c.play_card(f.r, card, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("leftover: valid two-token batch rejected")
		return
	if f.r.ranger_state.elements_collected_this_turn != 2 or int(f.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.EARTH, 0)) != 1:
		_fail("leftover: counter double-counted or remainder missing count=%d inventory=%s" % [f.r.ranger_state.elements_collected_this_turn, str(f.r.ranger_state.element_inventory)])


func _test_same_cell_duplicate_sources_yield_one_component() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var collector_id := "unit:%d" % f.r.unit_id
	f.c.surface_state.add_persistent_source(f.r.cell, BattleSurfaceState.Element.FIRE, "bottle:duplicate-fire:a", "diagnostic")
	f.c.surface_state.add_persistent_source(f.r.cell, BattleSurfaceState.Element.FIRE, "bottle:duplicate-fire:b", "diagnostic")
	if f.c.surface_state.get_collectible_entries(f.r.cell, collector_id).size() != 2:
		_fail("same-cell duplicate: fixture did not create two collectible sources")
		return
	var card := _hand_card(f.r)
	if not f.c.play_card(f.r, card, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("same-cell duplicate: valid single-component payload was rejected")
		return
	if f.r.ranger_state.elements_collected_this_turn != 1 \
			or int(f.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.FIRE, 0)) != 0 \
			or not f.c.surface_state.get_collectible_entries(f.r.cell, collector_id).is_empty():
		_fail("same-cell duplicate: expected one yielded component with both sources committed count=%d inventory=%d remaining=%d" % [
			f.r.ranger_state.elements_collected_this_turn,
			int(f.r.ranger_state.element_inventory.get(BattleSurfaceState.Element.FIRE, 0)),
			f.c.surface_state.get_collectible_entries(f.r.cell, collector_id).size(),
		])

func _test_advanced_source_splits_and_cannot_be_recollected() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	f.c.apply_advanced_surface(f.r.cell, BattleSurfaceState.Element.ICE, {"diagnostic": "bottle split"})
	var first := _hand_card(f.r)
	if not f.c.play_card(f.r, first, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.WATER, BattleSurfaceState.Element.AIR]}, CardEnums.CardPlayMode.NORMAL):
		_fail("advanced split: water/air payload rejected")
		return
	if f.r.ranger_state.elements_collected_this_turn != 2:
		_fail("advanced split: expected both base components, got %d" % f.r.ranger_state.elements_collected_this_turn)
	var second := _hand_card(f.r)
	var ap: int = f.r.current_ap
	if f.c.play_card(f.r, second, [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.WATER]}, CardEnums.CardPlayMode.NORMAL) or f.r.current_ap != ap:
		_fail("advanced split: same persistent source was recollected")

func _test_damage_uses_8_4_plus_agility() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_seed_residue(f.c, f.r.cell, BattleSurfaceState.Element.FIRE)
	var before: int = f.e.get_current_health()
	var agility_bonus: int = f.r.get_damage_bonus({"controller": f.c, "resolved_damage_type": CardEnums.DamageType.AGILITY})
	if not f.c.play_card(f.r, _hand_card(f.r), [f.e.cell], {"bottle_payload": [BattleSurfaceState.Element.FIRE]}, CardEnums.CardPlayMode.NORMAL):
		_fail("damage: valid play rejected")
	elif before - f.e.get_current_health() != 8 + agility_bonus:
		_fail("damage: center got %d rather than 8+agility bonus(%d)" % [before - f.e.get_current_health(), agility_bonus])

func _test_range_uses_paired_profile() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(5, 3))
	_set_weapon(f.r, "ranger_wind_hunter_pair")
	f.r.notify_equipment_battle_started({"controller": f.c})
	f.r.notify_movement_completed({"controller": f.c, "forced": false})
	var direction := BattleHexGrid.direction_index(f.r.cell, f.e.cell)
	if not _wind_action(f.c, f.r, direction):
		_fail("range: could not establish downwind")
		return
	_seed_residue(f.c, Vector2i(1, 3), BattleSurfaceState.Element.FIRE)
	var card := _hand_card(f.r)
	var context := {"bottle_payload": [BattleSurfaceState.Element.FIRE], "equipment_slot": "paired"}
	if not f.c.can_preview_card_targets(f.r, card, [f.e.cell], "paired", CardEnums.CardPlayMode.NORMAL, context) or not f.c.play_card(f.r, card, [f.e.cell], context, CardEnums.CardPlayMode.NORMAL):
		_fail("range: downwind paired distance 4 preview/play rejected")


func _test_upwind_range_rejects_beyond_shortened_boundary() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	_set_weapon(f.r, "ranger_wind_hunter_pair")
	f.r.notify_equipment_battle_started({"controller": f.c})
	f.r.notify_movement_completed({"controller": f.c, "forced": false})
	var upwind_direction := BattleHexGrid.direction_index(f.e.cell, f.r.cell)
	if not _wind_action(f.c, f.r, upwind_direction):
		_fail("upwind range: could not establish opposing wind direction")
		return
	_seed_residue(f.c, f.r.cell, BattleSurfaceState.Element.FIRE)
	var card := _hand_card(f.r)
	var context := {"bottle_payload": [BattleSurfaceState.Element.FIRE], "equipment_slot": "paired"}
	var ap: int = f.r.current_ap
	var collector_id := "unit:%d" % f.r.unit_id
	var source_count: int = f.c.surface_state.get_collectible_entries(f.r.cell, collector_id).size()
	if f.c.can_preview_card_targets(f.r, card, [f.e.cell], "paired", CardEnums.CardPlayMode.NORMAL, context) \
			or f.c.play_card(f.r, card, [f.e.cell], context, CardEnums.CardPlayMode.NORMAL):
		_fail("upwind range: target beyond shortened range was previewed or played")
	if f.r.current_ap != ap or not f.r.hand.has(card) \
			or f.c.surface_state.get_collectible_entries(f.r.cell, collector_id).size() != source_count:
		_fail("upwind range: rejected target mutated AP/card/source")
	var boundary_cell := Vector2i(3, 3)
	if not f.c.can_preview_card_targets(f.r, card, [boundary_cell], "paired", CardEnums.CardPlayMode.NORMAL, context) \
			or not f.c.play_card(f.r, card, [boundary_cell], context, CardEnums.CardPlayMode.NORMAL):
		_fail("upwind range: target at shortened boundary was not previewed and played")

func _fixture(ranger_cell: Vector2i, enemy_cell: Vector2i) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var c := BattleController.new()
	c.setup(scenario)
	var r := _find_ranger(c)
	var e: BattleUnitState = c.enemy_units[0]
	c.phase = BattleController.Phase.BATTLE
	c.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	c.current_unit = r
	r.current_ap = 9
	r.turn_serial = 1
	r.is_deployed = true
	e.is_deployed = true
	r.set_hex_cell(ranger_cell, c.map_data)
	e.set_hex_cell(enemy_cell, c.map_data)
	_set_weapon(r, "ranger_dagger_crossbow")
	return {"c": c, "r": r, "e": e}

func _find_ranger(c: BattleController) -> BattleUnitState:
	for unit in c.player_units:
		if unit.is_ranger():
			return unit
	return null

func _hand_card(r: BattleUnitState) -> CardData:
	var card := (load(BOTTLE_PATH) as CardData).duplicate(true) as CardData
	r.hand.append(card)
	return card

func _seed_residue(c: BattleController, cell: Vector2i, element: int) -> void:
	c.surface_state.add_residue(cell, element, c.battle_round)

func _set_weapon(r: BattleUnitState, name: String) -> void:
	r.character_state.weapon_equipment = load("res://resources/items/%s.tres" % name) as EquipmentData
	r.character_state.weapon_face = 0
	r.equipment_runtime_states.clear()

func _wind_action(c: BattleController, r: BattleUnitState, direction: int) -> bool:
	var action_id := "wind_%d" % direction
	for action in r.get_equipment_actions({"controller": c, "unit": r, "phase": "battle"}):
		if str(action.get("action_id", "")) == action_id:
			var effect := action.get("effect") as EquipmentEffect
			return effect != null and effect.activate(r, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {"controller": c, "unit": r, "equipment_action_id": action_id, "phase": "battle"})
	return false

func _fail(message: String) -> void:
	_exit_code = 1
	push_error("RANGER_BOTTLE_DIAG: " + message)
	print("ERROR: " + message)
