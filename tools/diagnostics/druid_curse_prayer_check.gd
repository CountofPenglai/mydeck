extends Node


var _exit_code := 0
var _ui_submitted: Dictionary = {}
var _ui_cancelled := false
var _ui_cancel_count: int = 0


func _ready() -> void:
	print("DRUID_CURSE_PRAYER: contract")
	_test_prayer_card_and_suppression_contract()
	print("DRUID_CURSE_PRAYER: upright")
	_test_upright_draw_mana_and_battle_reset()
	print("DRUID_CURSE_PRAYER: queued")
	_test_suppression_rechecks_queued_trigger()
	print("DRUID_CURSE_PRAYER: boundaries")
	_test_inverted_zone_boundaries_and_payment()
	print("DRUID_CURSE_PRAYER: shield")
	_test_inverted_randomness_and_shield_absorption()
	_test_deferred_strike_revalidates_legality()
	print("DRUID_CURSE_PRAYER: ui")
	await _test_posttarget_panel_interaction()
	await _test_battle_scene_posttarget_transaction()
	print("DRUID_CURSE_PRAYER: completed")
	get_tree().quit(_exit_code)


# Catches a missing battle-local suppression service or a prayer card which
# cannot be loaded as a real game resource.
func _test_prayer_card_and_suppression_contract() -> void:
	var suppression_script := load("res://scripts/curses/battle_curse_suppression.gd") as GDScript
	var card := load("res://resources/cards/druid_curse_prayer.tres") as CardData
	_expect(suppression_script != null, "battle-local curse suppression service is available")
	_expect(card != null, "curse prayer card resource is available")
	if suppression_script == null or card == null:
		return
	var suppression = suppression_script.new()
	var curse := CurseInstance.new()
	curse.definition = load("res://resources/curses/blood.tres") as CurseDefinition
	curse.state = CurseInstance.State.REPORT
	var depth_before := curse.depth
	var load_before := curse.get_load_cost()
	_expect(suppression.suppress(curse), "report curse can be suppressed")
	_expect(suppression.is_suppressed(curse), "suppression is observable")
	_expect(curse.depth == depth_before and curse.get_load_cost() == load_before and not curse.sealed, "suppression does not mutate permanent curse state")
	curse.state = CurseInstance.State.INDUSTRY
	_expect(not suppression.suppress(curse), "industry curse cannot be suppressed")
	suppression.clear()
	_expect(not suppression.is_suppressed(curse), "clearing battle state restores curse availability")


# Catches permanent sealing, a missing optional choice, and treating industry
# as a selectable curse. A new battle must restore the runtime-only effect.
func _test_upright_draw_mana_and_battle_reset() -> void:
	var f: Dictionary = _fixture(false)
	if f.is_empty():
		return
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var card: CardData = f.get("card") as CardData
	var target: BattleUnitState = _ally(controller, user)
	var curse := _report_curse()
	target.add_curse_to_zone(curse)
	_add_draws(target, 2)
	var depth_before := curse.depth
	var maturity_before := curse.maturity
	var load_before := curse.get_load_cost()
	_expect(controller.play_card(user, card, [target], {"selected_option_values": [curse]}), "upright accepts an allied target and a report")
	_expect(target.hand.size() == 2 and user.get_available_mana() == 2, "upright makes target draw two and caster gain two mana")
	_expect(not target.is_curse_effect_active(curse), "selected report is inactive during this battle")
	_expect(curse.depth == depth_before and curse.maturity == maturity_before and curse.get_load_cost() == load_before and not curse.sealed, "upright does not alter depth, maturity, load, or sealed state")
	curse.state = CurseInstance.State.INDUSTRY
	_expect(not card.requires_posttarget_configuration({"user": user, "druid_orientation": CardEnums.DruidOrientation.UPRIGHT}, [target]), "industry is not offered as a suppression choice")
	curse.state = CurseInstance.State.REPORT
	_expect(not card.requires_posttarget_configuration({"user": user, "druid_orientation": CardEnums.DruidOrientation.UPRIGHT}, [target]), "an already suppressed curse cannot be selected again")
	target.setup_player(target.unit_id, target.character_state, target.token_radius)
	_expect(target.is_curse_effect_active(curse), "starting a new battle resets suppression and restores report effects")


class QueuedCurseProbe extends CurseEffect:
	var fired := 0
	func on_turn_end(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
		fired += 1


class FruitBonusProbe extends CurseEffect:
	func modify_damage_bonus(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> int:
		return 7


class MoveOnHandLossStatus extends StatusEffect:
	func _init() -> void:
		status_id = "diagnostic_move_on_hand_loss"
		display_name = "diagnostic hand-loss move"
	func on_hand_size_changed(unit: BattleUnitState, _previous_size: int, context: Dictionary = {}) -> void:
		var controller := context.get("controller") as BattleController
		if controller != null:
			unit.set_hex_cell(Vector2i(0, 0), controller.map_data)


# Catches the old direct-Callable queueing path: a hook queued before
# suppression must recheck activity at execution time.
func _test_suppression_rechecks_queued_trigger() -> void:
	var f: Dictionary = _fixture(false)
	if f.is_empty():
		return
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var probe := QueuedCurseProbe.new()
	var curse := _report_curse(probe)
	user.add_curse_to_zone(curse)
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_queue_then_suppress"), [user, curse]))
	_expect(probe.fired == 0, "a queued curse hook cannot bypass later battle suppression")
	var fruit := _report_curse(FruitBonusProbe.new())
	fruit.state = CurseInstance.State.FRUIT
	user.add_curse_to_zone(fruit)
	_expect(user.get_curse_damage_bonus() == 7 and user.suppress_curse_for_battle(fruit) and user.get_curse_damage_bonus() == 0, "suppressed fruit loses its ongoing benefit")


func _queue_then_suppress(owner: BattleUnitState, curse: CurseInstance) -> void:
	owner.notify_zone_turn_end({"controller": owner.battle_controller})
	owner.suppress_curse_for_battle(curse)


# Catches coupling hand and deck candidates, accidental fee spending, and an
# unavailable enhanced option preventing the base card from being played.
func _test_inverted_zone_boundaries_and_payment() -> void:
	var f: Dictionary = _fixture(true)
	if f.is_empty():
		return
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var card: CardData = f.get("card") as CardData
	var enemy: BattleUnitState = f.get("enemy") as BattleUnitState
	var hand_curse := _curse_card("hand curse")
	enemy.hand.append(hand_curse)
	_expect(controller.play_card(user, card, [enemy]), "inverted plays with only a hand curse")
	_expect(enemy.exiled_pile.has(hand_curse), "inverted exiles the hand curse")

	f = _fixture(true)
	controller = f.get("c") as BattleController
	user = f.get("u") as BattleUnitState
	card = f.get("card") as CardData
	enemy = f.get("enemy") as BattleUnitState
	var deck_curse := _curse_card("deck curse")
	enemy.draw_pile.append(deck_curse)
	user.gain_mana(2, {"controller": controller})
	_expect(card.requires_posttarget_configuration({"user": user, "druid_orientation": CardEnums.DruidOrientation.INVERTED}, [enemy]), "deck-only target offers the optional extra payment")
	_expect(controller.play_card(user, card, [enemy], {"selected_option_values": [true]}), "inverted enhanced payment succeeds with a deck curse")
	_expect(enemy.exiled_pile.has(deck_curse) and user.get_available_mana() == 0, "enhancement exiles deck curse and spends exactly two mana")

	f = _fixture(true)
	controller = f.get("c") as BattleController
	user = f.get("u") as BattleUnitState
	card = f.get("card") as CardData
	enemy = f.get("enemy") as BattleUnitState
	var ap_before: int = user.current_ap
	_expect(not card.requires_posttarget_configuration({"user": user, "druid_orientation": CardEnums.DruidOrientation.INVERTED}, [enemy]), "no deck curse does not show an enhanced-payment option")
	_expect(controller.play_card(user, card, [enemy]), "inverted base strike remains available with no curse candidates")
	_expect(user.current_ap == ap_before - 2 and user.get_available_mana() == 0, "base use spends AP but no optional mana")

	f = _fixture(true)
	controller = f.get("c") as BattleController
	user = f.get("u") as BattleUnitState
	card = f.get("card") as CardData
	enemy = f.get("enemy") as BattleUnitState
	enemy.draw_pile.append(_curse_card("unaffordable deck curse"))
	ap_before = user.current_ap
	_expect(not controller.play_card(user, card, [enemy], {"selected_option_values": [true]}), "insufficient mana rejects only the selected enhancement")
	_expect(user.current_ap == ap_before and user.hand.has(card), "rejected enhancement rolls back AP and keeps card usable")
	_expect(controller.play_card(user, card, [enemy]), "after rejecting enhancement, base inverse card remains usable")


# Catches random selection over all cards instead of curse candidates and a
# damage bonus that bypasses armor or depends on attempted rather than actual exile.
func _test_inverted_randomness_and_shield_absorption() -> void:
	var first := _run_seeded_hand_exile(937)
	var second := _run_seeded_hand_exile(937)
	_expect(first == second and not first.is_empty(), "two legal hand candidates use deterministic battle RNG")
	var no_exile_armor_loss := _shielded_armor_loss(false)
	var one_exile_armor_loss := _shielded_armor_loss(true)
	_expect(one_exile_armor_loss == no_exile_armor_loss + 4, "each actual exile adds four damage through armor")


func _run_seeded_hand_exile(seed: int) -> String:
	var f: Dictionary = _fixture(true)
	if f.is_empty():
		return ""
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var card: CardData = f.get("card") as CardData
	var enemy: BattleUnitState = f.get("enemy") as BattleUnitState
	controller.rng.seed = seed
	var first := _curse_card("seed-first")
	var second := _curse_card("seed-second")
	enemy.hand.append_array([first, second])
	if not controller.play_card(user, card, [enemy]) or enemy.exiled_pile.is_empty():
		return ""
	return (enemy.exiled_pile[0] as CardData).card_name


func _shielded_armor_loss(with_hand_curse: bool) -> int:
	var f: Dictionary = _fixture(true)
	if f.is_empty():
		return -1
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var card: CardData = f.get("card") as CardData
	var enemy: BattleUnitState = f.get("enemy") as BattleUnitState
	enemy.gain_armor(99, {"controller": controller})
	var health_before: int = enemy.get_current_health()
	var armor_before: int = enemy.get_armor_stacks()
	if with_hand_curse:
		enemy.hand.append(_curse_card("shield curse"))
	if not controller.play_card(user, card, [enemy]):
		return -1
	_expect(enemy.get_current_health() == health_before, "shield absorbs curse-prayer strike before life loss")
	return armor_before - enemy.get_armor_stacks()


# Exercises the real popup controls used by post-target decisions. Confirming
# must carry the live option value; cancelling must not submit any payment choice.
func _test_posttarget_panel_interaction() -> void:
	var panel := BattlePreplayPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_ui_submitted.clear()
	_ui_cancelled = false
	_ui_cancel_count = 0
	panel.configuration_confirmed.connect(_record_ui_submission)
	panel.configuration_cancelled.connect(_record_ui_cancel)
	panel.show_configuration({"title": "diagnostic", "options": ["pay two mana"], "option_values": ["extra"], "minimum": 0, "maximum": 1})
	await get_tree().process_frame
	var toggle := _find_checkbox(panel, "pay two mana")
	var confirm := _find_button(panel, "确认")
	_expect(toggle != null and confirm != null, "post-target preplay panel renders a selectable option and confirmation")
	if toggle != null:
		toggle.button_pressed = true
		panel._on_option_toggled(true, 0)
	if confirm != null:
		panel._submit()
	await get_tree().process_frame
	_expect(_ui_submitted.get("selected_option_values", []) == ["extra"], "confirm returns the selected live option value")
	_expect(_ui_cancel_count == 0, "successful configuration close does not also cancel")
	panel.show_configuration({"title": "diagnostic", "options": ["skip"], "option_values": ["skip"], "minimum": 0, "maximum": 1})
	await get_tree().process_frame
	panel.hide()
	await get_tree().process_frame
	_expect(_ui_cancelled and _ui_cancel_count == 1, "implicit popup close emits one cancellation")
	panel.queue_free()


# Uses the actual BattleScene target-selection continuation: confirm pays the
# optional cost and resolves the card, while cancel leaves AP, mana, and card
# ownership untouched so the player can immediately try again.
func _test_battle_scene_posttarget_transaction() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var user: BattleUnitState = null
	for candidate in controller.player_units:
		if (candidate as BattleUnitState).is_druid():
			user = candidate as BattleUnitState
	var enemy: BattleUnitState = controller.enemy_units[0] as BattleUnitState
	_expect(user != null and enemy != null, "battle scene exposes druid and enemy for post-target UI")
	if user == null or enemy == null:
		scene.queue_free()
		return
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = user
	user.is_deployed = true
	user.set_hex_cell(Vector2i(4, 4), controller.map_data)
	user.current_ap = 10
	user.hand.clear()
	user.clear_mana()
	user.set_druid_transformed(true)
	enemy.is_deployed = true
	enemy.set_hex_cell(Vector2i(5, 4), controller.map_data)
	enemy.hand.clear()
	enemy.draw_pile.clear()
	var card := (load("res://resources/cards/druid_curse_prayer.tres") as CardData).duplicate(true) as CardData
	var deck_curse := _curse_card("scene deck curse")
	user.hand.append(card)
	enemy.draw_pile.append(deck_curse)
	user.gain_mana(2, {"controller": controller})
	scene.pending_card = card
	scene.pending_play_mode = CardEnums.CardPlayMode.NORMAL
	scene.pending_extra_context.clear()
	scene.pending_equipment_slot = ""
	scene.input_mode = BattleScene.InputMode.CARD_TARGET
	scene._handle_card_target(enemy.cell, enemy)
	_expect(scene._preplay_panel != null and scene._preplay_panel.visible, "targeting opens the real post-target optional-payment UI")
	scene._preplay_panel._on_option_toggled(true, 0)
	scene._preplay_panel._submit()
	await get_tree().process_frame
	_expect(user.current_ap == 8 and user.get_available_mana() == 0 and enemy.exiled_pile.has(deck_curse) and user.discard_pile.has(card), "UI confirmation atomically pays AP/mana, exiles deck curse, and discards card")

	var retry := (load("res://resources/cards/druid_curse_prayer.tres") as CardData).duplicate(true) as CardData
	var retry_curse := _curse_card("scene retry curse")
	user.hand.append(retry)
	enemy.draw_pile.append(retry_curse)
	user.gain_mana(2, {"controller": controller})
	var ap_before: int = user.current_ap
	var mana_before: int = user.get_available_mana()
	scene.pending_card = retry
	scene.pending_play_mode = CardEnums.CardPlayMode.NORMAL
	scene.pending_extra_context.clear()
	scene.pending_equipment_slot = ""
	scene.input_mode = BattleScene.InputMode.CARD_TARGET
	scene._handle_card_target(enemy.cell, enemy)
	scene._preplay_panel.hide()
	await get_tree().process_frame
	_expect(user.current_ap == ap_before and user.get_available_mana() == mana_before and user.hand.has(retry) and scene.input_mode == BattleScene.InputMode.NONE, "UI cancellation costs nothing and leaves the card available for another use")
	scene.queue_free()


func _fixture(inverted: bool) -> Dictionary:
	return DruidExpansionFixture.make("druid_curse_prayer", inverted)


func _report_curse(effect: CurseEffect = null) -> CurseInstance:
	var curse := CurseInstance.new()
	var definition := (load("res://resources/curses/blood.tres") as CurseDefinition).duplicate(true) as CurseDefinition
	if effect != null:
		definition.effect = effect
	curse.definition = definition
	curse.state = CurseInstance.State.REPORT
	return curse


func _curse_card(name: String) -> CardData:
	var card := CardData.new()
	card.card_name = name
	card.card_type = CardEnums.CardType.CURSE
	return card


func _add_draws(unit: BattleUnitState, count: int) -> void:
	for index in range(count):
		var card := CardData.new()
		card.card_name = "prayer draw %d" % index
		unit.draw_pile.append(card)


func _ally(controller: BattleController, owner: BattleUnitState) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != owner:
			unit.is_deployed = true
			unit.set_hex_cell(Vector2i(4, 5), controller.map_data)
			unit.curse_zone.clear()
			unit.curse_suppression.clear()
			unit.hand.clear()
			unit.draw_pile.clear()
			return unit
	return null


func _find_checkbox(root: Node, label: String) -> CheckBox:
	if root is CheckBox and (root as CheckBox).text == label:
		return root as CheckBox
	for child in root.get_children():
		var found := _find_checkbox(child, label)
		if found != null:
			return found
	return null


func _find_button(root: Node, label: String) -> Button:
	if root is Button and (root as Button).text == label:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _record_ui_submission(configuration: Dictionary) -> void:
	_ui_submitted = configuration.duplicate(true)


func _record_ui_cancel() -> void:
	_ui_cancelled = true
	_ui_cancel_count += 1


func _test_deferred_strike_revalidates_legality() -> void:
	var f: Dictionary = _fixture(true)
	if f.is_empty(): return
	var controller: BattleController = f.get("c") as BattleController
	var user: BattleUnitState = f.get("u") as BattleUnitState
	var card: CardData = f.get("card") as CardData
	var enemy: BattleUnitState = f.get("enemy") as BattleUnitState
	var effect := card.effect as DruidCursePrayerCardEffect
	var health_before: int = enemy.get_current_health()
	enemy.is_deployed = false
	effect._strike_after_exiles(controller, user, enemy, card, 4, "")
	_expect(enemy.get_current_health() == health_before, "undeployed deferred target takes no hit")
	enemy.is_deployed = true
	effect._strike_after_exiles(controller, user, enemy, card, 4, "")
	_expect(enemy.get_current_health() < health_before, "still-legal deferred target is struck")
	var moved: Dictionary = _fixture(true)
	if moved.is_empty(): return
	controller = moved.get("c") as BattleController
	user = moved.get("u") as BattleUnitState
	card = moved.get("card") as CardData
	enemy = moved.get("enemy") as BattleUnitState
	health_before = enemy.get_current_health()
	var ap_before: int = user.current_ap
	var mover := MoveOnHandLossStatus.new()
	enemy.add_status(mover)
	_expect(enemy.get_status("diagnostic_move_on_hand_loss") == mover, "hand-size descendant status is mounted before Prayer resolves")
	enemy.hand.append(_curse_card("move on exile"))
	_expect(controller.play_card(user, card, [enemy]), "inverse prayer queues after a real hand exile")
	_expect(enemy.cell == Vector2i(0, 0) and enemy.get_current_health() == health_before and user.current_ap == ap_before - 2, "hand-size descendant moves target before deferred strike; no hit or AP refund")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_CURSE_PRAYER: " + message)
