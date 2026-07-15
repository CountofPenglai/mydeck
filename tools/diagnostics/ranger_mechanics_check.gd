extends Node

const RANGER_CARD_PATHS := [
	"res://resources/cards/ranger_perilous_assault.tres",
	"res://resources/cards/ranger_shadow_passage.tres",
	"res://resources/cards/ranger_overdrawn_inspiration.tres",
	"res://resources/cards/ranger_relentless_backslash.tres",
	"res://resources/cards/ranger_waiting_prey.tres",
	"res://resources/cards/ranger_hunting_ground_lockdown.tres",
	"res://resources/cards/ranger_seamless_pursuit.tres",
	"res://resources/cards/ranger_cross_hunt_step.tres",
	"res://resources/cards/ranger_full_flavor.tres",
	"res://resources/cards/ranger_exotic_sampling.tres",
	"res://resources/cards/ranger_crossbow_tether.tres",
	"res://resources/cards/ranger_desperate_string.tres",
	"res://resources/cards/ranger_steal_plan.tres",
	"res://resources/cards/hidden_blade_again.tres",
	"res://resources/cards/ranger_tri_phase_dissection.tres",
	"res://resources/cards/ranger_dual_phase_hunt.tres",
	"res://resources/cards/ranger_exotic_bottle.tres",
	"res://resources/cards/ranger_final_hunt_declaration.tres",
	"res://resources/cards/ranger_no_place_to_hunt.tres",
	"res://resources/cards/ranger_hunter_three_acts.tres",
]

var _exit_code := 0


func _ready() -> void:
	_test_card_resources()
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle():
		_fail("RANGER_DIAG: battle failed to start")
		get_tree().quit(_exit_code)
		return
	var ranger := _find_ranger(controller)
	if ranger == null:
		_fail("RANGER_DIAG: sample battle has no ranger")
		get_tree().quit(_exit_code)
		return
	var guard := 0
	while controller.current_unit != ranger and guard < 12 and controller.phase == BattleController.Phase.BATTLE:
		controller.end_current_turn()
		guard += 1
	if controller.current_unit != ranger:
		_fail("RANGER_DIAG: could not advance to ranger turn")
		get_tree().quit(_exit_code)
		return
	_test_weapon_modes(ranger)
	if ranger.character_state == null or ranger.character_state.deck.size() < 21:
		_fail("RANGER_DIAG: default ranger deck does not include the full design set")
	if controller.surface_state.get_element(Vector2i(4, 2)) != BattleSurfaceState.Element.FIRE \
			or controller.surface_state.get_element(Vector2i(7, 5)) != BattleSurfaceState.Element.AIR:
		_fail("RANGER_DIAG: sample map base elements were not loaded")
	_test_combo_rollover(controller, ranger)
	_test_element_inventory(controller, ranger)
	_test_concealment(controller, ranger)
	print("RANGER_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_card_resources() -> void:
	for path in RANGER_CARD_PATHS:
		var card := load(path) as CardData
		if card == null or card.effect == null:
			_fail("RANGER_DIAG: failed to load %s" % path)
	var shared := load("res://resources/cards/hidden_blade_again.tres") as CardData
	if shared == null or not shared.is_available_to_class(CardEnums.CardClass.WARRIOR) \
			or not shared.is_available_to_class(CardEnums.CardClass.RANGER):
		_fail("RANGER_DIAG: hidden blade is not dual-class")


func _test_weapon_modes(ranger: BattleUnitState) -> void:
	var options := ranger.get_attack_weapon_options()
	if options.size() != 2:
		_fail("RANGER_DIAG: melee/ranged weapon did not expose two modes")
	if ranger.build_strike_profile_object("weapon").primary_range != 1:
		_fail("RANGER_DIAG: melee range is not 1")
	if ranger.build_strike_profile_object("paired").primary_range != 3:
		_fail("RANGER_DIAG: ranged range is not 3")


func _test_combo_rollover(controller: BattleController, ranger: BattleUnitState) -> void:
	ranger.ranger_state.combo_points = 9
	controller.gain_ranger_combo(ranger, 2)
	controller.resolve_effect_queue()
	if ranger.ranger_state.combo_points != 1:
		_fail("RANGER_DIAG: combo rollover did not preserve one point")
	var found_finisher := false
	for card in ranger.hand:
		if card != null and card.effect is RangerHuntMomentCardEffect:
			found_finisher = true
			break
	if not found_finisher:
		_fail("RANGER_DIAG: combo 10 did not grant Hunt Moment")


func _test_element_inventory(controller: BattleController, ranger: BattleUnitState) -> void:
	ranger.ranger_state.element_inventory.clear()
	ranger.collect_ranger_element(BattleSurfaceState.Element.FIRE, 1)
	ranger.collect_ranger_element(BattleSurfaceState.Element.WATER, 1)
	ranger.collect_ranger_element(BattleSurfaceState.Element.EARTH, 3)
	if ranger.ranger_state.get_element_total() != 5:
		_fail("RANGER_DIAG: element inventory cap setup failed")
	if ranger.collect_ranger_element(BattleSurfaceState.Element.AIR, 1) != 0:
		_fail("RANGER_DIAG: element inventory exceeded cap 5")
	controller.enter_ranger_stealth(ranger, "diagnostic")
	if not controller.prepare_ranger_blend(ranger, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("RANGER_DIAG: failed to prepare payable stealth blend")
	if ranger.ranger_state.prepared_blend != BattleSurfaceState.Element.STEAM:
		_fail("RANGER_DIAG: prepared blend state missing")


func _test_concealment(controller: BattleController, ranger: BattleUnitState) -> void:
	controller.surface_state.create_advanced_surface(ranger.cell, BattleSurfaceState.Element.STEAM, controller.battle_round)
	controller.enter_ranger_stealth(ranger, "diagnostic")
	if not controller.is_unit_concealed(ranger):
		_fail("RANGER_DIAG: stealth on Steam was not concealed")


func _deploy_players(controller: BattleController) -> void:
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(unit, cell):
			_fail("RANGER_DIAG: failed to deploy %s" % unit.get_display_name())


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_ranger():
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
