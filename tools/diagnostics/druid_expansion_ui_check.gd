extends Node


var _exit_code := 0


func _ready() -> void:
	await _test_mana_recovery_hand_picker()
	await _test_overflow_zone_picker_is_scrollable()
	await _test_continuous_strike_target_picker()
	await _test_twin_card_detail_rulings()
	_test_actual_twin_cross_zone_entry_and_whisper_exception()
	if _exit_code == 0:
		print("DRUID_EXPANSION_UI: PASS")
	get_tree().quit(_exit_code)


# This mounts the actual battle scene. It catches a wiring regression where
# Wellspring's runner choice exists but no usable picker is ever presented.
func _test_mana_recovery_hand_picker() -> void:
	var scene := await _new_battle_scene()
	if scene == null:
		return
	var owner := _active_druid(scene)
	if owner == null:
		_fail("mana recovery fixture has an active druid")
		await _free_scene(scene)
		return
	var card := _card_copy("druid_wellspring_return")
	var mana_card := _card_copy("druid_wild_wander")
	owner.hand.append(card)
	owner.mana_zone.append(mana_card)
	_expect(scene.controller.play_card(owner, card, []), "Wellspring starts its paid recovery action")
	scene.call("_refresh")
	await _frames(3)
	var popup := scene.get("_zone_card_picker") as PopupPanel
	_expect(popup != null and popup.visible, "mana recovery presents the mounted hand picker")
	_expect(_fits_compact_picker(popup), "mana recovery's short picker stays below 80% of the viewport height")
	var picker_list := popup.get("_list") as VBoxContainer if popup != null else null
	_expect(picker_list != null and _has_button(picker_list, "随风入野"), "mana recovery picker names the live mana-zone card")
	if popup != null and picker_list != null:
		popup.call("_on_card_toggled", true, mana_card)
		popup.call("_submit_selection")
		await _frames(3)
		_expect(not popup.visible and owner.hand.has(mana_card) and owner.get_available_mana() == 3, "confirmed recovery returns the selected entity and grants three mana")
	await _free_scene(scene)


func _test_overflow_zone_picker_is_scrollable() -> void:
	var scene := await _new_battle_scene()
	if scene == null:
		return
	var owner := _active_druid(scene)
	if owner == null:
		_fail("overflow picker fixture has an active druid")
		await _free_scene(scene)
		return
	var card := _card_copy("druid_wellspring_return")
	owner.hand.append(card)
	for index in range(20):
		owner.mana_zone.append(_card_copy("druid_wild_wander"))
	_expect(scene.controller.play_card(owner, card, []), "overflow fixture starts the paid recovery action")
	scene.call("_refresh")
	await _frames(3)
	var popup := scene.get("_zone_card_picker") as PopupPanel
	var scroll := popup.get("_scroll") as ScrollContainer if popup != null else null
	_expect(popup != null and popup.visible and _fits_compact_picker(popup), "overflow picker stays inside its compact viewport budget")
	_expect(scroll != null and scroll.get_v_scroll_bar().max_value > 0.0, "overflow picker exposes a vertical scroll range")
	if scroll != null:
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
		await _frames(2)
		var confirm := _find_button(popup, "确认")
		var scroll_rect := scroll.get_global_rect()
		_expect(confirm != null and scroll_rect.has_point(confirm.get_global_rect().get_center()), "overflow picker can scroll its confirmation control into view")
	if popup != null:
		popup.call("_skip_selection")
	await _frames(2)
	await _free_scene(scene)


# This uses the real unit picker and its successor refresh path, so a first
# target cannot accidentally close the second optional strike choice.
func _test_continuous_strike_target_picker() -> void:
	var scene := await _new_battle_scene()
	if scene == null:
		return
	var owner := _active_druid(scene)
	if owner == null:
		_fail("continuous strike fixture has an active druid")
		await _free_scene(scene)
		return
	owner.set_druid_transformed(true)
	owner.gain_mana(2, {"controller": scene.controller})
	owner.draw_pile.append_array([CardData.new(), CardData.new()])
	var card := _card_copy("druid_wellspring_return")
	owner.hand.append(card)
	var target := scene.controller.enemy_units[0] as BattleUnitState
	if target != null:
		target.is_deployed = true
		target.set_hex_cell(Vector2i(5, 4), scene.controller.map_data)
	_expect(target != null and scene.controller.play_card(owner, card, []), "inverted Wellspring opens its first optional strike")
	scene.call("_refresh")
	await _frames(3)
	var picker := scene.get("_unit_target_picker") as PopupPanel
	_expect(picker != null and picker.visible, "continuous strike presents the mounted target picker")
	_expect(_fits_compact_picker(picker), "continuous strike's three-row picker stays below 80% of the viewport height")
	_expect(picker != null and _has_button(picker, "结束"), "continuous strike picker offers early finish")
	if picker != null and target != null:
		scene.call("_submit_unit_target_choice", target)
		await _frames(3)
		_expect(picker.visible and scene.controller.resolution_runner.has_pending_unit_target_choice(), "after the first strike the successor target picker remains available")
		scene.call("_submit_unit_target_choice", null)
		await _frames(3)
		_expect(not picker.visible and not scene.controller.resolution_runner.has_pending_unit_target_choice(), "ending the sequence dismisses the target picker cleanly")
	await _free_scene(scene)


func _test_twin_card_detail_rulings() -> void:
	var encyclopedia := CardEncyclopedia.new()
	add_child(encyclopedia)
	await _frames(2)
	var whisper := load("res://resources/cards/druid_spirit_whisper.tres") as CardData
	var wander := load("res://resources/cards/druid_wild_wander.tres") as CardData
	_expect(whisper != null and wander != null, "twin resources load for the detail panel")
	if whisper != null:
		encyclopedia.show_card(whisper, false)
		_expect(encyclopedia.detail_title.text == "万灵低语" and encyclopedia.detail_rules.text.contains("支付2 AP"), "Whisper upright displays its active-play detailed ruling")
		encyclopedia.show_card(whisper, true)
		_expect(encyclopedia.detail_title.text == "盘根守望" and encyclopedia.detail_rules.text.contains("一次性响应"), "Whisper inverted displays its mana-zone detailed ruling")
	if wander != null:
		encyclopedia.show_card(wander, false)
		_expect(encyclopedia.detail_rules.text.contains("传送"), "Wander upright detail exposes its form-exception ruling")
		encyclopedia.show_card(wander, true)
		_expect(encyclopedia.detail_rules.text.contains("不能直接主动打出"), "Wander inverted detail exposes its twin-face restriction")
	encyclopedia.queue_free()
	await _frames(1)


# Uses the shipped Wander and Whisper Resources in both directions rather
# than metadata-only stand-ins. This catches face-based filtering drifting
# from the actual resource flags, or a twin entry accidentally firing either
# card's normal active effect.
func _test_actual_twin_cross_zone_entry_and_whisper_exception() -> void:
	var wander_fixture := DruidExpansionFixture.make("druid_wild_wander", false)
	_expect(not wander_fixture.is_empty(), "actual Wander twin fixture loads")
	if not wander_fixture.is_empty():
		var controller := wander_fixture.c as BattleController
		var owner := wander_fixture.u as BattleUnitState
		var wander := wander_fixture.card as CardData
		var whisper := _card_copy("druid_spirit_whisper")
		owner.discard_pile.append(whisper)
		var ap_before := owner.current_ap
		var mana_before := owner.get_available_mana()
		var cell_before: Vector2i = owner.cell
		_expect(controller.use_druid_twin_spell_entry(owner, wander), "actual Wander begins its free twin entry")
		var selected: Array[CardData] = [whisper]
		_expect(controller.resolution_runner.submit_hand_card_choice(selected), "actual Whisper in discard is a reciprocal Wander candidate")
		_expect(owner.mana_zone.has(wander) and owner.hand.has(whisper), "Wander enters mana and retrieves Whisper from discard")
		_expect(owner.current_ap == ap_before and owner.get_available_mana() == mana_before and owner.cell == cell_before, "Wander twin entry is free and does not invoke its teleport")
	var whisper_fixture := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not whisper_fixture.is_empty(), "actual Whisper twin fixture loads")
	if not whisper_fixture.is_empty():
		var controller := whisper_fixture.c as BattleController
		var owner := whisper_fixture.u as BattleUnitState
		var whisper := whisper_fixture.card as CardData
		var wander := _card_copy("druid_wild_wander")
		owner.draw_pile.append(wander)
		var ap_before := owner.current_ap
		_expect(controller.use_druid_twin_spell_entry(owner, whisper), "actual Whisper begins its free twin entry")
		var selected: Array[CardData] = [wander]
		_expect(controller.resolution_runner.submit_hand_card_choice(selected), "actual Wander in draw pile is a reciprocal Whisper candidate")
		_expect(owner.mana_zone.has(whisper) and owner.hand.has(wander), "Whisper enters mana and retrieves Wander from draw pile")
		_expect(owner.current_ap == ap_before, "Whisper twin entry is free and does not invoke its hand-rebuild effect")
	var active_whisper := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not active_whisper.is_empty(), "actual active Whisper fixture loads")
	if not active_whisper.is_empty():
		var controller := active_whisper.c as BattleController
		var owner := active_whisper.u as BattleUnitState
		var whisper := active_whisper.card as CardData
		_expect(controller.play_card(owner, whisper, []), "Whisper's explicit twin-face exception permits its upright active play")
		_expect(owner.current_ap == 8 and owner.discard_pile.has(whisper) and not owner.mana_zone.has(whisper), "active Whisper pays two AP and resolves normally rather than entering mana")


func _new_battle_scene() -> BattleScene:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await _frames(3)
	scene.controller.phase = BattleController.Phase.BATTLE
	scene.controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	var owner := _active_druid(scene)
	if owner != null:
		owner.is_deployed = true
		owner.set_hex_cell(Vector2i(4, 4), scene.controller.map_data)
		owner.current_ap = 10
		scene.controller.current_unit = owner
	return scene


func _active_druid(scene: BattleScene) -> BattleUnitState:
	for unit_value in scene.controller.player_units:
		var unit := unit_value as BattleUnitState
		if unit != null and unit.is_druid():
			return unit
	return null


func _card_copy(card_id: String) -> CardData:
	var template := load("res://resources/cards/%s.tres" % card_id) as CardData
	return template.duplicate(true) as CardData if template != null else null


func _has_button(root: Node, fragment: String) -> bool:
	return _find_button(root, fragment) != null


func _find_button(root: Node, fragment: String) -> Button:
	if root is Button and (root as Button).text.contains(fragment):
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, fragment)
		if found != null:
			return found
	return null


func _fits_compact_picker(picker: PopupPanel) -> bool:
	if picker == null:
		return false
	var viewport_height := get_viewport().get_visible_rect().size.y
	return viewport_height > 0.0 and float(picker.size.y) <= viewport_height * 0.8


func _frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _free_scene(scene: BattleScene) -> void:
	scene.queue_free()
	await _frames(2)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_fail(label)


func _fail(label: String) -> void:
	_exit_code = 1
	push_error("DRUID_EXPANSION_UI: " + label)
