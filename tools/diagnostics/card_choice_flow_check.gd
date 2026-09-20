extends Node


var _exit_code := 0
var _continued_cards: Array[CardData] = []
var _continuation_action_id := 0
var _continuation_locked := false
var _after_action_id := 0
var _after_queue_marker_ran := false
var _after_choice_requests := 0
var _empty_choice_continuation_called := false


func _ready() -> void:
	_test_binary_choice_delegation()
	_test_runner_suspends_and_resumes_the_same_action()
	_test_empty_choice_continuation_is_typed()
	await _test_pending_choice_rejects_new_actions()
	_test_paused_after_queue_keeps_unexecuted_entries()
	_test_choice_requested_by_after_callback_does_not_repeat_callback()
	await _test_live_binary_choice_popup()
	await _test_invalid_ranged_slot_is_rejected()
	print("CARD_CHOICE_FLOW: completed")
	get_tree().quit(_exit_code)


# Catches CardData swallowing the effect's binary options, which would make
# the scene either skip the choice or permit an unavailable assault branch.
func _test_binary_choice_delegation() -> void:
	var card := CardData.new()
	var effect := WarriorAdvanceRetreatCardEffect.new()
	var owner := BattleUnitState.new()
	card.effect = effect
	if not card.has_method("requires_card_choice") \
			or not card.has_method("get_card_choice_options") \
			or not card.has_method("get_card_choice_prompt"):
		_fail("CARD_CHOICE_FLOW: CardData does not delegate generic binary choice")
		return
	var context := {"user": owner, "card": card}
	var options: Array[Dictionary] = card.call("get_card_choice_options", context)
	_expect(bool(card.call("requires_card_choice", context)), "binary card requires a choice before play")
	_expect(options.size() == 2 and str(options[0].get("id", "")) == "steady", "steady option remains visible")
	_expect(options.size() == 2 and not bool(options[1].get("enabled", true)), "unaffordable assault remains visible but disabled")
	_expect(str(card.call("get_card_choice_prompt", context)) == "选择进退有势的战术", "binary prompt delegates to effect")


# Catches a runner that either finalizes before a required selection, accepts a
# stale/duplicate card, or resumes a new action instead of the suspended one.
func _test_runner_suspends_and_resumes_the_same_action() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var runner := controller.resolution_runner
	if not runner.has_method("request_hand_card_choice") \
			or not runner.has_method("submit_hand_card_choice") \
			or not runner.has_method("has_pending_hand_card_choice"):
		_fail("CARD_CHOICE_FLOW: runner does not expose the hand-choice API")
		return

	var owner := BattleUnitState.new()
	var source := CardData.new()
	source.card_name = "choice source"
	var candidate := CardData.new()
	candidate.card_name = "drawn candidate"
	var stale := CardData.new()
	stale.card_name = "stale candidate"
	owner.hand.assign([source, candidate])
	_continued_cards.clear()
	_continuation_action_id = 0
	_continuation_locked = false
	_after_action_id = 0

	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_request_fixture_choice"),
		[controller, owner, source],
		0,
		"hand choice diagnostic",
		null,
		Callable(self, "_record_after_choice"),
		[controller]
	))

	var paused_action_id := controller.get_current_action_id()
	_expect(paused_action_id > 0, "required choice retains a current action id")
	_expect(controller.is_resolving_actions(), "required choice keeps ordinary actions locked")
	_expect(bool(runner.call("has_pending_hand_card_choice")), "required choice remains pending")
	_expect(owner.hand.has(source), "source card remains in hand while choice is pending")
	var source_selected: Array[CardData] = [source]
	var duplicate_selected: Array[CardData] = [candidate, candidate]
	var stale_selected: Array[CardData] = [stale]
	var live_selected: Array[CardData] = [candidate]
	_expect(not runner.submit_hand_card_choice(source_selected), "source card selection is rejected")
	_expect(bool(runner.call("has_pending_hand_card_choice")), "invalid source selection leaves choice pending")
	_expect(not runner.submit_hand_card_choice(duplicate_selected), "duplicate selection is rejected")
	_expect(bool(runner.call("has_pending_hand_card_choice")), "duplicate selection leaves choice pending")
	_expect(not runner.submit_hand_card_choice(stale_selected), "stale selection is rejected")
	_expect(bool(runner.call("has_pending_hand_card_choice")), "stale selection leaves choice pending")
	_expect(runner.submit_hand_card_choice(live_selected), "live drawn card selection resumes")
	_expect(_continued_cards == [candidate], "continuation receives exactly the selected live card")
	_expect(_continuation_action_id == paused_action_id and _after_action_id == paused_action_id, "continuation and after stage retain original action id")
	_expect(_continuation_locked, "continuation executes before action unlock")
	_expect(not controller.is_resolving_actions() and controller.get_current_action_id() == 0, "action unlocks only after continuation and after stage")


func _request_fixture_choice(controller: BattleController, owner: BattleUnitState, source: CardData) -> void:
	var accepted := bool(controller.resolution_runner.call(
		"request_hand_card_choice",
		owner,
		source,
		1,
		1,
		"选择一张其他手牌",
		Callable(self, "_record_choice_continuation").bind(controller)
	))
	_expect(accepted, "effect boundary accepts required hand-card choice")


func _record_choice_continuation(selected: Array[CardData], controller: BattleController) -> void:
	_continued_cards.assign(selected)
	_continuation_action_id = controller.get_current_action_id()
	_continuation_locked = controller.is_resolving_actions()


func _record_after_choice(controller: BattleController) -> void:
	_after_action_id = controller.get_current_action_id()


# An empty live-card set is not a pending UI choice, but its continuation must
# still receive a typed Array[CardData] so effects such as zero-select Canopy
# can complete their remaining action stages.
func _test_empty_choice_continuation_is_typed() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var owner := BattleUnitState.new()
	var source := CardData.new()
	owner.hand.assign([source])
	_empty_choice_continuation_called = false
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_request_empty_fixture_choice"),
		[controller, owner, source],
		0,
		"empty hand choice diagnostic"
	))
	_expect(_empty_choice_continuation_called, "zero-candidate choice invokes its typed continuation")
	_expect(not controller.resolution_runner.has_pending_hand_card_choice(), "zero-candidate choice opens no pending popup")


func _request_empty_fixture_choice(controller: BattleController, owner: BattleUnitState, source: CardData) -> void:
	_expect(
		controller.resolution_runner.request_hand_card_choice(
			owner,
			source,
			0,
			2,
			"zero-candidate diagnostic",
			Callable(self, "_record_empty_choice_continuation")
		),
		"zero-candidate choice request is accepted"
	)


func _record_empty_choice_continuation(selected: Array[CardData]) -> void:
	_empty_choice_continuation_called = true
	_expect(selected.is_empty(), "zero-candidate choice continuation receives an empty typed selection")


# A pending card decision is a suspended action, not ordinary in-progress
# resolution. Public card play and a directly submitted action frame must both
# leave it alone; its AP and queued work can change only after the player picks.
func _test_pending_choice_rejects_new_actions() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("CARD_CHOICE_FLOW: battle scene is unavailable for pending-choice reentry")
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(3):
		await get_tree().process_frame
	var controller := scene.controller
	var owner := _find_warrior(controller)
	if owner == null:
		_fail("CARD_CHOICE_FLOW: warrior fixture is unavailable for pending-choice reentry")
		scene.queue_free()
		return
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = owner
	owner.is_deployed = true
	owner.current_ap = 6
	var source := CardData.new()
	source.card_name = "suspended choice source"
	var candidate := CardData.new()
	candidate.card_name = "suspended choice candidate"
	var unrelated := CardData.new()
	unrelated.card_name = "unrelated queued card"
	unrelated.ap_cost = 1
	owner.hand.append_array([source, candidate, unrelated])
	_expect(
		controller.can_play_card_with_mode(owner, unrelated, CardEnums.CardPlayMode.NORMAL),
		"unrelated public card is valid before the choice suspends resolution"
	)
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_request_fixture_choice"),
		[controller, owner, source],
		0,
		"pending-choice reentry diagnostic"
	))
	var runner := controller.resolution_runner
	_expect(runner.has_pending_hand_card_choice(), "fixture creates a real pending hand choice")
	var ap_before := owner.current_ap
	var queued_before := runner.action_queue.size()
	var public_play_accepted := controller.play_card(owner, unrelated, [])
	_expect(not public_play_accepted, "public card play is rejected while a hand choice is pending")
	_expect(owner.current_ap == ap_before, "rejected pending-choice card play spends no AP")
	_expect(runner.action_queue.size() == queued_before, "rejected pending-choice card play queues no action")
	var direct_action_accepted := controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_mark_after_queue"),
		[],
		0,
		"unrelated pending-choice action"
	))
	_expect(not direct_action_accepted, "new action frame is rejected while a hand choice is pending")
	_expect(owner.current_ap == ap_before and runner.action_queue.size() == queued_before, "rejected pending-choice action preserves AP and queue")
	runner.reset()
	scene.queue_free()


# Catches a pause that copies and clears the entire after-effect queue, then
# loses siblings that were still waiting behind the choice-requesting entry.
func _test_paused_after_queue_keeps_unexecuted_entries() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var owner := BattleUnitState.new()
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.assign([source, candidate])
	_after_queue_marker_ran = false
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_queue_after_choice_and_marker"),
		[controller, owner, source]
	))
	_expect(controller.resolution_runner.has_pending_hand_card_choice(), "after-effect choice pauses the current action")
	var selected: Array[CardData] = [candidate]
	_expect(controller.resolution_runner.submit_hand_card_choice(selected), "after-effect choice accepts live card")
	_expect(_after_queue_marker_ran, "after-effect queued behind choice remains and resolves")
	_expect(not controller.is_resolving_actions(), "after-effect choice action eventually unlocks")


func _queue_after_choice_and_marker(controller: BattleController, owner: BattleUnitState, source: CardData) -> void:
	controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_request_fixture_choice"), [controller, owner, source])
	controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_mark_after_queue"))


func _mark_after_queue() -> void:
	_after_queue_marker_ran = true


# Catches resuming by re-entering the whole finalization sequence: an
# after-callback that requested one choice must not request it again.
func _test_choice_requested_by_after_callback_does_not_repeat_callback() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var owner := BattleUnitState.new()
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.assign([source, candidate])
	_after_choice_requests = 0
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_mark_after_queue"),
		[],
		0,
		"after callback choice diagnostic",
		null,
		Callable(self, "_request_choice_from_after_callback"),
		[controller, owner, source]
	))
	_expect(controller.resolution_runner.has_pending_hand_card_choice(), "after callback can suspend once")
	var selected: Array[CardData] = [candidate]
	_expect(controller.resolution_runner.submit_hand_card_choice(selected), "after callback selection submits")
	_expect(_after_choice_requests == 1, "resuming does not re-enter the after callback")
	_expect(not controller.resolution_runner.has_pending_hand_card_choice() and not controller.is_resolving_actions(), "after callback choice completes the original action")
	controller.resolution_runner.reset()


func _request_choice_from_after_callback(controller: BattleController, owner: BattleUnitState, source: CardData) -> void:
	_after_choice_requests += 1
	controller.resolution_runner.request_hand_card_choice(
		owner,
		source,
		1,
		1,
		"after callback choice",
		Callable(self, "_record_choice_continuation").bind(controller)
	)


# Catches a scene that advances into weapon/target selection before showing the
# required binary choice, or lets an unavailable assault be pressed.
func _test_live_binary_choice_popup() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("CARD_CHOICE_FLOW: battle scene is unavailable for binary-choice UI")
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(3):
		await get_tree().process_frame
	var warrior := _find_warrior(scene.controller)
	var card_template := load("res://resources/cards/warrior_advance_retreat.tres") as CardData
	if warrior == null or card_template == null:
		_fail("CARD_CHOICE_FLOW: binary-choice UI fixture is unavailable")
		scene.queue_free()
		return
	var card := card_template.duplicate(true) as CardData
	scene.controller.phase = BattleController.Phase.BATTLE
	scene.controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	scene.controller.current_unit = warrior
	warrior.is_deployed = true
	warrior.current_ap = 9
	warrior.hand.append(card)
	scene._select_card_with_mode(card, CardEnums.CardPlayMode.NORMAL)
	var popup := scene.get("_card_choice_popup") as PopupPanel
	_expect(popup != null and popup.visible, "binary choice popup opens before targeting")
	var assault := _find_button(popup, "强攻")
	_expect(assault != null and assault.disabled, "unavailable assault is visibly disabled")
	var steady := _find_button(popup, "稳进")
	_expect(steady != null and not steady.disabled, "available steady is selectable")
	if steady != null:
		steady.emit_signal("pressed")
	await get_tree().process_frame
	_expect(str(scene.pending_extra_context.get("card_choice", "")) == "steady", "selected binary option survives into targeting context")
	scene.queue_free()


func _find_warrior(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.character_state != null and unit.character_state.character_data != null \
				and unit.character_state.character_data.character_class == CardEnums.CardClass.WARRIOR:
			return unit
	return null


func _test_invalid_ranged_slot_is_rejected() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	for _frame in range(3):
		await get_tree().process_frame
	var ranger := _find_ranger(scene.controller)
	if ranger == null or ranger.character_state == null:
		_fail("CARD_CHOICE_FLOW: ranger fixture is unavailable for slot validation")
		scene.queue_free()
		return
	ranger.character_state.weapon_equipment = null
	ranger.equipment_runtime_states.clear()
	scene.controller.phase = BattleController.Phase.BATTLE
	scene.controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	scene.controller.current_unit = ranger
	var options := ranger.get_attack_weapon_options()
	var has_paired := false
	for option in options:
		if str(option.get("slot", "")) == "paired":
			has_paired = true
	_expect(not has_paired, "no paired equipment exposes no ranged weapon option")
	scene.pending_equipment_slot = ""
	scene._on_weapon_choice_pressed("paired")
	_expect(scene.pending_equipment_slot.is_empty(), "stale paired selection cannot enter targeting context")
	scene.queue_free()


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_ranger():
			return unit
	return null


func _find_button(root: Node, text_value: String) -> Button:
	if root == null:
		return null
	for child in root.get_children():
		if child is Button and (child as Button).text.contains(text_value):
			return child as Button
		var nested := _find_button(child, text_value)
		if nested != null:
			return nested
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail("CARD_CHOICE_FLOW: %s" % message)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	_exit_code = 1
