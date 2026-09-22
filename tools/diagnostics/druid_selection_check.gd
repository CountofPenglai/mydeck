extends Node


var _exit_code := 0
var _zone_continued: Array[CardData] = []
var _zone_continuation_action_id := 0
var _picker_submitted: Array[CardData] = []
var _picker_browsed_deck: bool = false
var _picker_cancelled: bool = false


func _ready() -> void:
	var service_script := load("res://scripts/battle/battle_selection_service.gd")
	_expect(service_script != null, "selection service exists")
	if service_script != null:
		_test_live_zone_identity_validation(service_script.new())
	_test_zone_choice_suspends_and_revalidates()
	await _test_zone_picker_selection_lifecycle()
	await _test_zone_picker_browse_and_cancel()
	await _test_zone_picker_hides_non_candidates()
	await _test_mounted_hide_cancels_runner_choice()
	await _test_mounted_submit_closes_completed_choice()
	await _test_mounted_submit_keeps_synchronous_followup_choice()
	print("DRUID_SELECTION: completed")
	get_tree().quit(_exit_code)


# Catches implementations that compare card resource content rather than the
# live CardData entities, or accept cards no longer present in the requested zone.
func _test_live_zone_identity_validation(service) -> void:
	var fixture := DruidExpansionFixture.make("druid_wild_shape", false)
	_expect(not fixture.is_empty(), "druid selection fixture is available")
	if fixture.is_empty():
		return
	var owner: BattleUnitState = fixture["u"] as BattleUnitState
	var first := CardData.new()
	var second := first.duplicate(true) as CardData
	owner.mana_zone.assign([first, second])
	var mana := PackedStringArray(["mana"])
	var distinct: Array[CardData] = [first, second]
	var duplicate: Array[CardData] = [first, first]
	_expect(service.validate(owner, distinct, mana, 0, 5), "distinct copies are legal")
	_expect(not service.validate(owner, duplicate, mana, 0, 5), "duplicate entity is illegal")
	owner.mana_zone.erase(second)
	var stale: Array[CardData] = [second]
	var empty: Array[CardData] = []
	_expect(not service.validate(owner, stale, mana, 0, 5), "card leaving its zone invalidates an old selection")
	_expect(not service.validate(owner, empty, PackedStringArray(["void"]), 0, 5), "unknown zone is rejected")
	_expect(service.validate(owner, empty, mana, 0, 5), "minimum zero and maximum five permit an empty selection")


# Catches a runner that stores a snapshot rather than the requested live zones,
# or which resumes a different action after a post-payment choice.
func _test_zone_choice_suspends_and_revalidates() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var runner := controller.resolution_runner
	_expect(runner.has_method("request_zone_card_choice"), "runner exposes a zone-card choice request")
	if not runner.has_method("request_zone_card_choice"):
		return
	var owner := BattleUnitState.new()
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.append(source)
	owner.discard_pile.append(candidate)
	_zone_continued.clear()
	_zone_continuation_action_id = 0
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_request_zone_choice"),
		[runner, owner, source]
	))
	_expect(runner.has_pending_hand_card_choice(), "zone choice suspends its current action")
	var paused_id := controller.get_current_action_id()
	owner.discard_pile.erase(candidate)
	var stale: Array[CardData] = [candidate]
	_expect(not runner.submit_hand_card_choice(stale), "zone submit rejects a card moved after the popup opened")
	owner.discard_pile.append(candidate)
	var live: Array[CardData] = [candidate]
	_expect(runner.submit_hand_card_choice(live), "zone submit accepts a live card from discard")
	_expect(_zone_continued == [candidate] and _zone_continuation_action_id == paused_id, "zone continuation stays on the suspended action")


func _request_zone_choice(runner, owner: BattleUnitState, source: CardData) -> void:
	_expect(runner.request_zone_card_choice(
		owner,
		source,
		PackedStringArray(["discard"]),
		1,
		1,
		"选择一张弃牌",
		Callable(self, "_record_zone_selection").bind(runner)
	), "zone choice request is accepted")


func _request_two_zone_choices(runner, owner: BattleUnitState, source: CardData) -> void:
	runner.request_zone_card_choice(owner, source, PackedStringArray(["discard"]), 1, 1, "first", Callable(self, "_request_followup_zone_choice").bind(runner, owner, source))


func _request_followup_zone_choice(_selected: Array[CardData], runner, owner: BattleUnitState, source: CardData) -> void:
	runner.request_zone_card_choice(owner, source, PackedStringArray(["discard"]), 0, 1, "followup", Callable(self, "_record_zone_selection").bind(runner))


func _record_zone_selection(selected: Array[CardData], runner) -> void:
	_zone_continued.assign(selected)
	_zone_continuation_action_id = runner.get_current_action_id()


func _test_zone_picker_selection_lifecycle() -> void:
	var picker_script := load("res://scripts/battle/ui/battle_zone_card_picker.gd")
	_expect(picker_script != null, "zone picker module exists")
	if picker_script == null:
		return
	var owner := BattleUnitState.new()
	var shared := CardData.new()
	shared.card_name = "shared choice"
	owner.discard_pile.append(shared)
	var choice_a: Variant = BattleCardChoiceState.create(owner, CardData.new(), 0, 1, "first", Callable())
	choice_a.zones = PackedStringArray(["discard"])
	var choice_b: Variant = BattleCardChoiceState.create(owner, CardData.new(), 0, 1, "second", Callable())
	choice_b.zones = PackedStringArray(["discard"])
	var picker: Variant = picker_script.new()
	add_child(picker)
	await get_tree().process_frame
	picker.show_choice(choice_a)
	var choice_a_toggle := _find_checkbox(picker, "shared choice")
	_expect(choice_a_toggle != null, "picker renders the first choice card")
	if choice_a_toggle == null:
		picker.queue_free()
		return
	choice_a_toggle.button_pressed = true
	picker.show_choice(choice_b)
	var choice_b_toggle := _find_checkbox(picker, "shared choice")
	_expect(choice_b_toggle != null and not choice_b_toggle.button_pressed, "a new choice never inherits another choice's selection")
	if choice_b_toggle != null:
		choice_b_toggle.button_pressed = true
	picker.show_choice(choice_b)
	choice_b_toggle = _find_checkbox(picker, "shared choice")
	_expect(choice_b_toggle != null and choice_b_toggle.button_pressed, "refreshing the same choice retains its selection")
	_picker_submitted.clear()
	picker.selection_submitted.connect(_record_picker_submission_and_show.bind(picker, choice_a))
	picker._submit_selection()
	_expect(_picker_submitted == [shared], "submit emits the chosen live entity")
	var after_submit_toggle := _find_checkbox(picker, "shared choice")
	_expect(after_submit_toggle != null and not after_submit_toggle.button_pressed, "submit clears old selection before a synchronous continuation choice")
	if after_submit_toggle != null:
		after_submit_toggle.button_pressed = true
	_picker_submitted.clear()
	picker._skip_selection()
	_expect(_picker_submitted.is_empty(), "skip emits an empty selection")
	var after_skip_toggle := _find_checkbox(picker, "shared choice")
	_expect(after_skip_toggle != null and not after_skip_toggle.button_pressed, "skip clears old selection before a synchronous continuation choice")
	picker.queue_free()


func _record_picker_submission_and_show(selected: Array[CardData], picker, next_choice) -> void:
	_picker_submitted.assign(selected)
	picker.show_choice(next_choice)


func _test_zone_picker_browse_and_cancel() -> void:
	var owner := BattleUnitState.new()
	var draw := CardData.new()
	draw.card_name = "deck twin"
	var discard := CardData.new()
	discard.card_name = "discard twin"
	owner.draw_pile.append(draw)
	owner.discard_pile.append(discard)
	var choice: Variant = BattleCardChoiceState.create(owner, CardData.new(), 0, 1, "browse", Callable())
	choice.zones = PackedStringArray(["draw", "discard"])
	var picker := BattleZoneCardPicker.new()
	add_child(picker)
	await get_tree().process_frame
	_picker_browsed_deck = false
	_picker_cancelled = false
	picker.zone_browsed.connect(func(zone: String) -> void: _picker_browsed_deck = zone == "draw")
	picker.selection_cancelled.connect(func() -> void: _picker_cancelled = true)
	picker.show_choice(choice)
	_expect(_find_checkbox(picker, "discard twin") != null and _find_checkbox(picker, "deck twin") == null, "picker defaults to discard without viewing deck")
	picker._browse_zone("draw")
	_expect(_picker_browsed_deck and _find_checkbox(picker, "deck twin") != null, "deck browse is explicit and observable")
	picker._cancel_selection()
	_expect(_picker_cancelled, "picker exposes a non-submitting cancel path")
	picker.queue_free()


func _test_zone_picker_hides_non_candidates() -> void:
	var owner := BattleUnitState.new()
	var source := CardData.new()
	var allowed := CardData.new()
	allowed.card_name = "opposite twin"
	var same_face := CardData.new()
	same_face.card_name = "same face twin"
	var ordinary := CardData.new()
	ordinary.card_name = "ordinary card"
	owner.discard_pile.append_array([allowed, same_face, ordinary])
	var choice: Variant = BattleCardChoiceState.create(owner, source, 0, 1, "filtered", Callable())
	choice.zones = PackedStringArray(["discard"])
	choice.card_filter = func(card: CardData) -> bool: return card == allowed
	var picker := BattleZoneCardPicker.new()
	add_child(picker)
	await get_tree().process_frame
	picker.show_choice(choice)
	_expect(_find_checkbox(picker, "opposite twin") != null, "picker shows a live filtered candidate")
	_expect(_find_checkbox(picker, "same face twin") == null and _find_checkbox(picker, "ordinary card") == null, "picker hides same-face and non-twin cards")
	picker.queue_free()


# Catches Esc/background hide leaving BattleScene's suspended runner locked.
func _test_mounted_hide_cancels_runner_choice() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.append(source)
	owner.discard_pile.append(candidate)
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_zone_choice"), [controller.resolution_runner, owner, source]))
	scene._refresh_hand_card_choice_popup()
	_expect(scene._zone_card_picker.visible and controller.resolution_runner.has_pending_hand_card_choice(), "mounted picker shows a suspended runner choice")
	scene._zone_card_picker.hide()
	await get_tree().process_frame
	_expect(not controller.resolution_runner.has_pending_hand_card_choice() and not controller.is_resolving_actions(), "mounted implicit hide cancels and unblocks the runner")
	scene.queue_free()


# Catches a successful submission leaving the old exclusive popup mounted after
# the runner has no continuation choice.
func _test_mounted_submit_closes_completed_choice() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.append(source)
	owner.discard_pile.append(candidate)
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_zone_choice"), [controller.resolution_runner, owner, source]))
	scene._refresh_hand_card_choice_popup()
	scene._zone_card_picker._on_card_toggled(true, candidate)
	scene._zone_card_picker._submit_selection()
	await get_tree().process_frame
	_expect(not controller.resolution_runner.has_pending_hand_card_choice() and not scene._zone_card_picker.visible, "mounted successful choice closes its completed exclusive picker")
	scene.queue_free()


func _test_mounted_submit_keeps_synchronous_followup_choice() -> void:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller: BattleController = scene.controller
	var owner: BattleUnitState = controller.player_units[0] as BattleUnitState
	var source := CardData.new()
	var candidate := CardData.new()
	owner.hand.append(source)
	owner.discard_pile.append(candidate)
	controller.push_action_frame(BattleActionFrame.create(Callable(self, "_request_two_zone_choices"), [controller.resolution_runner, owner, source]))
	scene._refresh_hand_card_choice_popup()
	scene._zone_card_picker._on_card_toggled(true, candidate)
	scene._zone_card_picker._submit_selection()
	await get_tree().process_frame
	_expect(controller.resolution_runner.has_pending_hand_card_choice() and scene._zone_card_picker.visible, "mounted synchronous followup keeps its new picker visible")
	scene._zone_card_picker.hide()
	scene.queue_free()


func _find_checkbox(root: Node, card_name: String) -> CheckBox:
	if root is CheckBox and root.text.begins_with(card_name):
		return root as CheckBox
	for child in root.get_children():
		var found := _find_checkbox(child, card_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_SELECTION: %s" % message)
