extends Node

const CURSE_IDS: Array[String] = [
	"blood", "greed", "cripple", "disease", "passing", "possession", "unrest",
	"counterfeit", "universal_love", "gluttony", "offspring", "preservation", "unbound",
]

var _exit_code := 0


func _ready() -> void:
	_test_resources()
	_test_persistent_lifecycle()
	_test_distortion_rewards()
	_test_manifestation_lifecycle()
	_test_battle_projection()
	_test_curse_ui()
	print("CURSE_SYSTEM: completed")
	get_tree().quit(_exit_code)


func _test_resources() -> void:
	for curse_id in CURSE_IDS:
		var definition := load("res://resources/curses/%s.tres" % curse_id) as CurseDefinition
		if definition == null or not definition.is_valid_definition():
			_fail("CURSE_SYSTEM: invalid definition %s" % curse_id)
			continue
		if definition.curse_id != curse_id or definition.industry_card.card_type != CardEnums.CardType.CURSE:
			_fail("CURSE_SYSTEM: definition/card mismatch %s" % curse_id)
		if definition.effect is not CoreCurseEffect or definition.industry_card.effect is not CurseIndustryCardEffect:
			_fail("CURSE_SYSTEM: wrong effect type %s" % curse_id)
	var disease := load("res://resources/cards/curse_disease.tres") as CardData
	if disease == null or disease.card_type != CardEnums.CardType.CURSE or disease.can_play():
		_fail("CURSE_SYSTEM: disease card is invalid")


func _test_persistent_lifecycle() -> void:
	var state := CharacterState.new()
	var blood := load("res://resources/curses/blood.tres") as CurseDefinition
	var first := state.acquire_curse(blood)
	var duplicate := state.acquire_curse(blood)
	if first == null or duplicate != first or first.depth != 2:
		_fail("CURSE_SYSTEM: duplicate acquisition did not deepen")
	var cards := state.create_industry_cards()
	if cards.size() != 1 or cards[0].bound_curse_instance != first:
		_fail("CURSE_SYSTEM: industry projection failed")
	if not first.transform_to_report() or state.get_curse_load() != 2:
		_fail("CURSE_SYSTEM: industry to report/load failed")
	for _index in range(blood.maturity_threshold):
		state.process_curse_battle_result(true)
	if first.state != CurseInstance.State.FRUIT or state.distortion_progress != 1:
		_fail("CURSE_SYSTEM: report maturity failed")
	var run_state := PartyRunState.new()
	if not state.seal_curse(first, run_state) or state.get_curse_load() != 0 or run_state.ritual_points != 1:
		_fail("CURSE_SYSTEM: sealing/load failed")
	if not state.unseal_curse() or state.get_curse_load() != 2:
		_fail("CURSE_SYSTEM: unsealing failed")
	var greed := state.acquire_curse(load("res://resources/curses/greed.tres") as CurseDefinition)
	state.acquire_curse(greed.definition)
	greed.transform_to_report()
	if not state.is_curse_overloaded():
		_fail("CURSE_SYSTEM: overload was not detected")
	var transfer_source := CharacterState.new()
	var transfer_target := CharacterState.new()
	var transferable := transfer_source.acquire_curse(greed.definition)
	transferable.transform_to_report()
	var love := transfer_target.acquire_curse(load("res://resources/curses/universal_love.tres") as CurseDefinition)
	love.state = CurseInstance.State.FRUIT
	var free_run := PartyRunState.new()
	if not transfer_source.transfer_curse_to(transferable, transfer_target, free_run) or free_run.ritual_points != 3:
		_fail("CURSE_SYSTEM: universal love free transfer failed")


func _test_battle_projection() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	if controller.player_units.is_empty():
		_fail("CURSE_SYSTEM: sample battle has no player")
		return
	var unit := controller.player_units[0]
	unit.is_deployed = true
	unit.set_hex_cell(Vector2i(2, 4), controller.map_data)
	unit.character_state.curse_instances.clear()
	var greed := unit.character_state.acquire_curse(load("res://resources/curses/greed.tres") as CurseDefinition)
	greed.transform_to_report()
	unit.ensure_initialized(controller.config, controller.rng)
	unit.curse_zone.clear()
	unit.add_curse_to_zone(greed, {"controller": controller})
	if unit.curse_zone.size() != 1:
		_fail("CURSE_SYSTEM: curse zone projection failed")
	unit.gain_curse_wave(7, {"controller": controller})
	if unit.consume_curse_wave(3) != 3 or unit.curse_wave != 4:
		_fail("CURSE_SYSTEM: curse wave accounting failed")
	var unrest := unit.character_state.acquire_curse(load("res://resources/curses/unrest.tres") as CurseDefinition)
	unrest.state = CurseInstance.State.FRUIT
	unit.add_curse_to_zone(unrest, {"controller": controller})
	unit.set_current_health(unit.get_max_health())
	if unit.get_lethal_health_floor({"amount": 1}) != 0:
		_fail("CURSE_SYSTEM: unrest triggered on nonlethal damage")
	unit.set_current_health(1)
	if unit.get_lethal_health_floor({"amount": 1}) != 1:
		_fail("CURSE_SYSTEM: unrest did not prevent lethal damage")
	var root := controller.spawn_curse_root(unit, Vector2i(3, 4), 15, true, true, 1)
	if root == null or root in controller.turn_order or controller.get_unit_at_cell(Vector2i(3, 4)) != root:
		_fail("CURSE_SYSTEM: root proxy failed")


func _test_distortion_rewards() -> void:
	var template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	if template == null:
		_fail("CURSE_SYSTEM: distortion test hero missing")
		return
	var state := template.duplicate(true) as CharacterState
	state.curse_instances.clear()
	state.distortion_progress = 2
	state.selected_distortion_fields.clear()
	state.claimed_distortion_milestones.clear()
	state.distortion_grace_count = 0
	state.ensure_initialized()
	var old_strength := state.get_strength()
	var old_agility := state.get_agility()
	var old_intelligence := state.get_intelligence()
	var old_max_health := state.get_max_health()
	state.current_health = maxi(1, old_max_health - 2)
	if not state.has_pending_distortion_reward() or not state.apply_distortion_reward(DistortionCatalog.GRACE_ID):
		_fail("CURSE_SYSTEM: grace reward could not be claimed")
	elif state.get_strength() != old_strength + 1 or state.get_agility() != old_agility + 1 \
		or state.get_intelligence() != old_intelligence + 1:
		_fail("CURSE_SYSTEM: grace attributes were not applied")
	elif state.current_health != old_max_health - 2 + state.get_max_health() - old_max_health:
		_fail("CURSE_SYSTEM: grace did not preserve missing health")
	if not state.claimed_distortion_milestones.has(0) or state.has_pending_distortion_reward():
		_fail("CURSE_SYSTEM: claimed milestone was not consumed")

	var counterfeit_state := template.duplicate(true) as CharacterState
	counterfeit_state.curse_instances.clear()
	counterfeit_state.distortion_progress = 2
	counterfeit_state.claimed_distortion_milestones.clear()
	var counterfeit := counterfeit_state.acquire_curse(load("res://resources/curses/counterfeit.tres") as CurseDefinition)
	counterfeit.depth = 2
	counterfeit.state = CurseInstance.State.REPORT
	if counterfeit_state.get_effective_distortion_threshold(0) != 4 \
		or counterfeit_state.has_pending_distortion_reward():
		_fail("CURSE_SYSTEM: counterfeit did not delay current milestone")
	counterfeit_state.distortion_progress = 4
	if not counterfeit_state.has_pending_distortion_reward():
		_fail("CURSE_SYSTEM: delayed milestone did not unlock")
	var low_field_id := str(DistortionCatalog.LOW_FIELDS[0])
	if not counterfeit_state.apply_distortion_reward(low_field_id):
		_fail("CURSE_SYSTEM: low-tier distortion could not be claimed")
	elif counterfeit_state.get_effective_distortion_threshold(1) != 7:
		_fail("CURSE_SYSTEM: counterfeit did not move to the next unclaimed milestone")


func _test_manifestation_lifecycle() -> void:
	var template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	if template == null:
		_fail("CURSE_SYSTEM: manifestation hero missing")
		return
	var state := template.duplicate(true) as CharacterState
	state.selected_distortion_fields = PackedStringArray(["lashing"])
	var unit := BattleUnitState.new()
	unit.setup_player(77, state, 24.0)
	if not unit.distortion_state.has_field("lashing"):
		_fail("CURSE_SYSTEM: permanent distortion field did not project into battle")
	var first := CardData.new()
	first.card_name = "诊断附肢甲"
	first.mutation_fields = PackedStringArray(["appendage"])
	var second := CardData.new()
	second.card_name = "诊断附肢乙"
	second.mutation_fields = PackedStringArray(["appendage"])
	unit.add_card_to_enchant_zone(first, {"reason": "diagnostic_manifest"})
	unit.add_card_to_enchant_zone(second, {"reason": "diagnostic_manifest"})
	if unit.distortion_state.get_source_count("appendage") != 2 \
			or unit.get_active_distortion_fields().count("appendage") != 1:
		_fail("CURSE_SYSTEM: duplicate mutation sources did not share one field effect")
	unit.start_turn(BattleConfig.new())
	var decayed := unit.decay_turn_start_manifestations({"reason": "diagnostic_decay"})
	if decayed != 2 or unit.discard_pile.size() != 2 \
			or unit.distortion_state.has_field("appendage"):
		_fail("CURSE_SYSTEM: manifestation decay did not use the common discard path")
	var blood_card := CardData.new()
	blood_card.card_name = "诊断觅血"
	blood_card.mutation_fields = PackedStringArray(["bloodseeking"])
	unit.hand.append(blood_card)
	if unit.manifest_cards_from_hand([blood_card], {"reason": "diagnostic_manual"}) != 1 \
			or not unit.distortion_state.has_field("bloodseeking") \
			or not unit.hand.is_empty():
		_fail("CURSE_SYSTEM: manual manifestation failed")
	if unit.release_all_manifestations({"reason": "diagnostic_release"}) != 1 \
			or unit.distortion_state.has_field("bloodseeking"):
		_fail("CURSE_SYSTEM: manifestation release failed")
	for card_id in [
		"lashing_tentacle", "blood_mouth", "extra_limbs", "scorch_sac",
		"enlightened_tumor", "night_membrane", "irradiated_gland", "stampeding_feet",
	]:
		var card := load("res://resources/cards/monster_cards/%s.tres" % card_id) as CardData
		if card == null or not card.has_mutation_fields() or not card.description.contains(card.get_mutation_label()):
			_fail("CURSE_SYSTEM: mutation card mapping missing for %s" % card_id)


func _test_curse_ui() -> void:
	var scene := load("res://scenes/battle_scene.tscn") as PackedScene
	if scene == null:
		_fail("CURSE_SYSTEM: battle scene could not instantiate")
		return
	var state := scene.get_state()
	var found := false
	for index in range(state.get_node_count()):
		if str(state.get_node_name(index)) == "CurseButton":
			found = true
			break
	if not found:
		_fail("CURSE_SYSTEM: curse zone UI entry missing")
	var battle_scene := scene.instantiate() as BattleScene
	add_child(battle_scene)
	if battle_scene.controller.player_units.is_empty():
		_fail("CURSE_SYSTEM: battle UI has no player for manifestation check")
	else:
		var unit := battle_scene.controller.player_units[0]
		var card := CardData.new()
		card.card_name = "诊断显化牌"
		card.mutation_fields = PackedStringArray(["appendage"])
		unit.hand.append(card)
		unit.distortion_state.pending_manual_manifest = true
		battle_scene.controller.phase = BattleController.Phase.BATTLE
		battle_scene.controller.current_unit = unit
		battle_scene.controller.turn_flow_state = BattleController.TurnFlowState.MANIFEST_PENDING
		battle_scene._refresh_manifest_popup()
		if battle_scene._manifest_popup == null or not battle_scene._manifest_popup.visible \
				or battle_scene._manifest_list.get_child_count() < 3:
			_fail("CURSE_SYSTEM: manifestation selection UI did not open")
	battle_scene.queue_free()


func _fail(message: String) -> void:
	push_error(message)
	_exit_code = 1
