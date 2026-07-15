extends Node

const CURSE_IDS: Array[String] = [
	"blood", "greed", "cripple", "disease", "passing", "possession", "unrest",
	"counterfeit", "universal_love", "gluttony", "offspring", "preservation", "unbound",
]

var _exit_code := 0


func _ready() -> void:
	_test_resources()
	_test_persistent_lifecycle()
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


func _fail(message: String) -> void:
	push_error(message)
	_exit_code = 1
