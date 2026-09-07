extends Node

const AFTER_STRIKE_STATUS = preload("res://tools/diagnostics/ranger_terrain_after_strike_status.gd")
const TETHER_PATH := "res://resources/cards/ranger_crossbow_tether.tres"
const BAIT_PATH := "res://resources/cards/ranger_exotic_sampling.tres"
const FLAVOR_PATH := "res://resources/cards/ranger_full_flavor.tres"

var _exit_code := 0

func _ready() -> void:
	_test_1_tether_actual_pull_collect()
	_test_1b_tether_rejects_unavailable_paired_mode()
	_test_1c_tether_uses_alternate_range_origin()
	_test_2_target_sensitive_range_and_los()
	_test_3_tether_kill_and_blocked_pull()
	_test_4_tether_after_strike_descendant_order()
	_test_5_bait_rejections_and_valid_play()
	await _test_6_bait_cap_and_live_scene_hint()
	_test_7_full_flavor_draws()
	print("RANGER_TERRAIN_CARDS: completed")
	get_tree().quit(_exit_code)

func _test_1_tether_actual_pull_collect() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var c: BattleController = f.c; var r: BattleUnitState = f.r; var e: BattleUnitState = f.e
	_set_weapon(r, "ranger_dagger_crossbow")
	c.surface_state.add_residue(Vector2i(3, 3), BattleSurfaceState.Element.FIRE, c.battle_round)
	var card := _hand_card(r, TETHER_PATH); var ap := r.current_ap
	if not c.play_card(r, card, [e]): _fail("1 tether: ordinary paired range-3 actual play rejected")
	if e.cell != Vector2i(3, 3) or r.ranger_state.get_element_total() != 1 or r.current_ap != ap - 2 or r.hand.has(card) or not r.discard_pile.has(card):
		_fail("1 tether: final=%s elements=%d ap=%d hand=%s discard=%s" % [str(e.cell), r.ranger_state.get_element_total(), r.current_ap, str(r.hand.has(card)), str(r.discard_pile.has(card))])

func _test_1b_tether_rejects_unavailable_paired_mode() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3))
	var c: BattleController = f.c; var r: BattleUnitState = f.r; var e: BattleUnitState = f.e
	_set_weapon(r, "ranger_sea_dragon_pair")
	c.perform_strike(r, e, null, "diagnostic cooldown", "paired")
	var card := _hand_card(r, TETHER_PATH); var ap := r.current_ap
	if r.can_use_attack_mode("paired") or c.play_card(r, card, [e]) or r.current_ap != ap or not r.hand.has(card):
		_fail("1b tether: unavailable paired mode consumed AP/card or resolved a pull")


func _test_1c_tether_uses_alternate_range_origin() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(5, 3))
	var c: BattleController = f.c; var r: BattleUnitState = f.r; var e: BattleUnitState = f.e
	_set_weapon(r, "ranger_dagger_crossbow")
	var origin: BattleUnitState = null
	for unit in c.player_units:
		if unit != r:
			origin = unit
			break
	if origin == null:
		_fail("1c tether: fixture has no alternate-origin ally")
		return
	origin.is_deployed = true
	origin.set_hex_cell(Vector2i(2, 3), c.map_data)
	origin.turn_serial = 1
	var borrowed := DruidBorrowedOriginStatus.new()
	borrowed.status_id = "diagnostic_borrowed_origin"
	borrowed.stacks = 1
	borrowed.source_unit = origin
	borrowed.source_turn_serial = origin.turn_serial
	r.add_status(borrowed)
	var card := _hand_card(r, TETHER_PATH); var ap := r.current_ap
	var range_distance := r.get_range_distance_to(e, {"controller": c, "equipment_slot": "paired", "card": card})
	var preview := c.can_preview_card_targets(r, card, [e])
	var played := c.play_card(r, card, [e])
	if range_distance != 3 or not preview or not played \
			or r.current_ap != ap - 2 or r.hand.has(card):
		_fail("1c tether: distance=%d preview=%s play=%s ap=%d hand=%s" % [range_distance, str(preview), str(played), r.current_ap, str(r.hand.has(card))])

func _test_2_target_sensitive_range_and_los() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(5, 3))
	var c: BattleController = f.c; var r: BattleUnitState = f.r; var e: BattleUnitState = f.e
	_set_weapon(r, "ranger_wind_hunter_pair")
	r.notify_equipment_battle_started({"controller": c}); r.notify_movement_completed({"controller": c, "forced": false})
	var direction := BattleHexGrid.direction_index(r.cell, e.cell)
	if not _wind_action(c, r, direction): _fail("2 range: real wind direction action failed")
	var downwind := _hand_card(r, TETHER_PATH); var range := c.get_effective_attack_range_against(r, e, "paired")
	var preview := c.can_preview_card_targets(r, downwind, [e]); var played := c.play_card(r, downwind, [e])
	if not preview or not played: _fail("2 range: literal distance-4 downwind preview=%s play=%s range=%d direction=%d" % [str(preview), str(played), range, direction])
	var up := _fixture(Vector2i(1, 3), Vector2i(5, 3)); _set_weapon(up.r, "ranger_wind_hunter_pair")
	up.r.notify_equipment_battle_started({"controller": up.c}); up.r.notify_movement_completed({"controller": up.c, "forced": false})
	if not _wind_action(up.c, up.r, (BattleHexGrid.direction_index(up.r.cell, up.e.cell) + 3) % 6): _fail("2 range: upwind action setup failed")
	var up_card := _hand_card(up.r, TETHER_PATH); var up_ap: int = up.r.current_ap
	if up.c.can_preview_card_targets(up.r, up_card, [up.e]) or up.c.play_card(up.r, up_card, [up.e]) or up.r.current_ap != up_ap or not up.r.hand.has(up_card): _fail("2 range: upwind distance-4 was accepted or paid")
	var blocked := _fixture(Vector2i(1, 3), Vector2i(4, 3)); _set_weapon(blocked.r, "ranger_dagger_crossbow")
	blocked.c.spawn_battle_object(BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(2, 3))
	var blocked_card := _hand_card(blocked.r, TETHER_PATH); var blocked_ap: int = blocked.r.current_ap
	var blocked_preview: bool = blocked.c.can_preview_card_targets(blocked.r, blocked_card, [blocked.e])
	var blocked_played: bool = blocked.c.play_card(blocked.r, blocked_card, [blocked.e])
	if blocked_preview or blocked_played or blocked.r.current_ap != blocked_ap: _fail("2 range: LOS-blocked preview=%s play=%s ap=%d" % [str(blocked_preview), str(blocked_played), blocked.r.current_ap])

func _test_3_tether_kill_and_blocked_pull() -> void:
	var kill := _fixture(Vector2i(1, 3), Vector2i(4, 3)); _set_weapon(kill.r, "ranger_dagger_crossbow")
	kill.e.set_current_health(1); kill.c.surface_state.add_residue(kill.e.cell, BattleSurfaceState.Element.FIRE, kill.c.battle_round)
	if not kill.c.play_card(kill.r, _hand_card(kill.r, TETHER_PATH), [kill.e]) or kill.e.is_alive() or kill.e.cell != Vector2i(4, 3) or kill.r.ranger_state.get_element_total() != 0: _fail("3 tether kill: dead target moved or collected (cell=%s, elements=%d)" % [str(kill.e.cell), kill.r.ranger_state.get_element_total()])
	var blocked := _fixture(Vector2i(1, 3), Vector2i(4, 3)); _set_weapon(blocked.r, "ranger_dagger_crossbow")
	blocked.c.spawn_battle_object(BattleObjectDefinition.Kind.WATER_CISTERN, Vector2i(3, 3)); blocked.c.surface_state.add_residue(Vector2i(4, 3), BattleSurfaceState.Element.FIRE, blocked.c.battle_round)
	if not blocked.c.play_card(blocked.r, _hand_card(blocked.r, TETHER_PATH), [blocked.e]) or blocked.e.cell != Vector2i(4, 3) or blocked.r.ranger_state.get_element_total() != 1: _fail("3 tether blocked: final=%s elements=%d" % [str(blocked.e.cell), blocked.r.ranger_state.get_element_total()])

func _test_4_tether_after_strike_descendant_order() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(4, 3)); _set_weapon(f.r, "ranger_dagger_crossbow")
	var status := AFTER_STRIKE_STATUS.new() as StatusEffect; status.status_id = "ranger_terrain_after_strike"; status.stacks = 1; status.controller = f.c; status.cell = Vector2i(3, 3); f.r.add_status(status)
	if not f.c.play_card(f.r, _hand_card(f.r, TETHER_PATH), [f.e]) or not status.ran or f.r.ranger_state.get_element_total() != 2: _fail("4 tether ordering: descendant=%s collected=%d" % [str(status.ran), f.r.ranger_state.get_element_total()])

func _test_5_bait_rejections_and_valid_play() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(5, 3)); var bad_cells := [Vector2i(2, 3), Vector2i(5, 3), Vector2i(6, 3)]
	# Non-elemental, occupied elemental, and elemental distance > 3.
	_seed_elemental_surface(f.c, Vector2i(5, 3), BattleSurfaceState.Element.ICE)
	_seed_elemental_surface(f.c, Vector2i(6, 3), BattleSurfaceState.Element.ICE)
	for cell in bad_cells:
		var card := _hand_card(f.r, BAIT_PATH); var ap: int = f.r.current_ap
		if f.c.play_card(f.r, card, [cell]) or f.r.current_ap != ap or not f.r.hand.has(card): _fail("5 bait reject: illegal cell %s consumed card/AP" % str(cell))
		f.r.hand.erase(card)
	var valid := Vector2i(2, 3); _seed_elemental_surface(f.c, valid, BattleSurfaceState.Element.ICE)
	var good := _hand_card(f.r, BAIT_PATH); var good_ap: int = f.r.current_ap
	var good_played: bool = f.c.play_card(f.r, good, [valid])
	if not good_played or f.c.get_active_trap_count(f.r) != 1 or f.r.current_ap != good_ap - 2 or f.r.hand.has(good): _fail("5 bait valid: play=%s traps=%d limit=%d ap=%d hand=%s" % [str(good_played), f.c.get_active_trap_count(f.r), f.c.get_trap_limit(f.r), f.r.current_ap, str(f.r.hand.has(good))])

func _test_6_bait_cap_and_live_scene_hint() -> void:
	var f := _fixture(Vector2i(1, 3), Vector2i(5, 3)); var first_cell := Vector2i(2, 3); var second_cell := Vector2i(3, 3)
	_seed_elemental_surface(f.c, first_cell, BattleSurfaceState.Element.ICE); _seed_elemental_surface(f.c, second_cell, BattleSurfaceState.Element.ICE)
	var first: BattleObjectState = f.c.place_elemental_trap(f.r, first_cell); var card := _hand_card(f.r, BAIT_PATH); var ap: int = f.r.current_ap
	var cap_played: bool = f.c.play_card(f.r, card, [second_cell]); var spread: int = f.c.surface_state.get_element(Vector2i(4, 3))
	if first == null or not cap_played or not first.is_active() or f.c.get_active_trap_count(f.r) != 1 or f.r.current_ap != ap - 2 or f.r.hand.has(card) or spread != BattleSurfaceState.Element.ICE: _fail("6 bait cap: first=%s play=%s traps=%d ap=%d hand=%s spread=%d" % [str(first != null and first.is_active()), str(cap_played), f.c.get_active_trap_count(f.r), f.r.current_ap, str(f.r.hand.has(card)), spread])
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null: _fail("6 bait UI: battle scene missing"); return
	var scene := packed.instantiate() as BattleScene; add_child(scene)
	for _frame in range(5):
		await get_tree().process_frame
	var c := scene.controller; var r := _find_ranger(c); c.phase = BattleController.Phase.BATTLE; c.turn_flow_state = BattleController.TurnFlowState.ACTIVE; c.current_unit = r; c.action_resolution_active = false; c.resolution_runner.is_draining_actions = false; r.current_ap = 9; r.is_deployed = true; r.set_hex_cell(Vector2i(1, 3), c.map_data)
	_seed_elemental_surface(c, Vector2i(2, 3), BattleSurfaceState.Element.ICE); var ui_first := c.place_elemental_trap(r, Vector2i(2, 3))
	if ui_first == null or not ui_first.is_active(): _fail("6 bait UI: cap fixture could not place original trap")
	scene._druid_prepare_hand_choice_active = false
	var ui_card := _hand_card(r, BAIT_PATH); var ui_modes := scene._available_hand_play_modes(ui_card); scene._select_card(ui_card); await get_tree().process_frame
	if not scene._battle_log_lines.has("超限：放置后爆炸"): _fail("6 bait UI: live _select_card hint missing locked=%s resolving=%s modes=%s mode=%d logs=%s" % [str(scene._actions_locked()), str(c.is_resolving_actions()), str(ui_modes), scene.input_mode, str(scene._battle_log_lines)])
	scene.queue_free()

func _test_7_full_flavor_draws() -> void:
	for types in [0, 2, 4]:
		var f := _fixture(Vector2i(1, 3), Vector2i(5, 3)); f.r.hand.clear(); f.r.draw_pile.clear(); f.r.discard_pile.clear(); f.r.ranger_state.element_inventory.clear()
		for index in range(types): f.r.ranger_state.add_element(BattleSurfaceState.BASE_ELEMENTS[index], 1)
		var inventory: Dictionary = f.r.ranger_state.element_inventory.duplicate(true); var source := _hand_card(f.r, FLAVOR_PATH)
		for index in range(5): f.r.draw_pile.append((load(TETHER_PATH) as CardData).duplicate(true) as CardData)
		if (load(FLAVOR_PATH) as CardData).rarity != CardEnums.Rarity.COMMON: _fail("7 flavor: fixture resource is not CardEnums.Rarity.COMMON")
		var played: bool = f.c.play_card(f.r, source, [f.r])
		if not played or f.r.hand.size() != 2 + (1 if types >= 2 else 0) + (1 if types >= 4 else 0) or f.r.ranger_state.element_inventory != inventory: _fail("7 flavor: types=%d play=%s hand=%d draw=%d discard=%d inventory=%s" % [types, str(played), f.r.hand.size(), f.r.draw_pile.size(), f.r.discard_pile.size(), str(f.r.ranger_state.element_inventory)])

func _fixture(ranger_cell: Vector2i, enemy_cell: Vector2i) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var c := BattleController.new(); c.setup(scenario); var r := _find_ranger(c); var e: BattleUnitState = c.enemy_units[0]
	c.phase = BattleController.Phase.BATTLE; c.turn_flow_state = BattleController.TurnFlowState.ACTIVE; c.current_unit = r; r.current_ap = 9; r.turn_serial = 1; r.is_deployed = true; e.is_deployed = true
	r.set_hex_cell(ranger_cell, c.map_data); e.set_hex_cell(enemy_cell, c.map_data); return {"c": c, "r": r, "e": e}

func _find_ranger(c: BattleController) -> BattleUnitState:
	for unit in c.player_units:
		if unit.is_ranger(): return unit
	return null

func _set_weapon(r: BattleUnitState, name: String) -> void:
	r.character_state.weapon_equipment = load("res://resources/items/%s.tres" % name) as EquipmentData; r.character_state.weapon_face = 0; r.equipment_runtime_states.clear()

func _hand_card(r: BattleUnitState, path: String) -> CardData:
	var card := (load(path) as CardData).duplicate(true) as CardData; r.hand.append(card); return card

func _seed_elemental_surface(c: BattleController, cell: Vector2i, element: int) -> void:
	c.apply_advanced_surface(cell, element, {"diagnostic": "ranger terrain"})
	if c.surface_state.get_element(cell) != element:
		_fail("fixture: expected elemental surface %d at %s, found %d" % [element, str(cell), c.surface_state.get_element(cell)])

func _wind_action(c: BattleController, r: BattleUnitState, direction: int) -> bool:
	var action_id := "wind_%d" % direction
	for action in r.get_equipment_actions({"controller": c, "unit": r, "phase": "battle"}):
		if str(action.get("action_id", "")) == action_id:
			var effect := action.get("effect") as EquipmentEffect
			return effect != null and effect.activate(r, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {"controller": c, "unit": r, "equipment_action_id": action_id, "phase": "battle"})
	return false

func _fail(message: String) -> void:
	_exit_code = 1; push_error("RANGER_TERRAIN_CARDS: " + message); print("ERROR: " + message)
