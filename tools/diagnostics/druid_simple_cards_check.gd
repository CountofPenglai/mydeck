extends Node

var _exit_code := 0


func _ready() -> void:
	_test_insight_both_faces()
	_test_moon_healing_and_mana()
	_test_moon_damage_and_mana()
	_test_basic_transform_and_strike()
	_test_rare_form_cycle()
	_test_stored_mana_hud()
	if _exit_code == 0:
		print("DRUID_SIMPLE_CARDS: PASS")
	get_tree().quit(_exit_code)


func _test_insight_both_faces() -> void:
	for inverted in [false, true]:
		var f := _fixture("druid_rooted_insight", inverted)
		_expect(f.c.play_card(f.u, f.card, []), "insight must be playable")
		_expect(f.u.hand.size() == (1 if inverted else 2), "insight must draw 2/1 without counting the played card")
		_expect(f.u.get_available_mana() == 1, "both insight faces give one immediate mana, no auto payment")
		_expect(f.u.mana_zone.has(f.card) == inverted, "only inverse insight enters mana")
		_expect(f.u.discard_pile.has(f.card) != inverted, "upright insight must discard")


func _test_moon_healing_and_mana() -> void:
	for inverted in [false, true]:
		for supplied in [0, 1]:
			var f := _fixture("druid_moonlit_mend", inverted)
			f.u.character_state.flat_damage_bonus = 7
			f.u.set_current_health(10)
			f.u.gain_temporary_mana(supplied)
			_expect(f.c.play_card(f.u, f.card, [f.u]), "moon must heal self")
			var heal := (8 if supplied == 1 else 6) if inverted else 4
			_expect(f.u.get_current_health() == 10 + heal, "moon healing must ignore damage bonuses; only inverse may strengthen")
			_expect(f.u.get_available_mana() == (0 if inverted else supplied), "only inverse moon auto pays mana")
			_expect(f.u.discard_pile.has(f.card) and not f.u.mana_zone.has(f.card), "both moon faces must discard")


func _test_moon_damage_and_mana() -> void:
	for inverted in [false, true]:
		for supplied in [0, 1]:
			var f := _fixture("druid_moonlit_mend", inverted)
			f.u.character_state.weapon_equipment = null
			f.u.character_state.character_data.base_intelligence = 4
			f.u.character_state.character_data.base_strength = 12
			f.u.character_state.flat_damage_bonus = 1
			f.u.gain_mana(supplied)
			var health_before: int = f.enemy.get_current_health()
			_expect(f.c.play_card(f.u, f.card, [f.enemy]), "moon must target an enemy without a weapon")
			var base := (8 if supplied == 1 else 6) if inverted else 4
			# Existing transformation swaps strength/intelligence: effective INT
			# is 12 in beast form and 4 in human form, plus the flat +1 bonus.
			var expected := base + (7 if inverted else 3)
			_expect(health_before - f.enemy.get_current_health() == expected, "moon damage inverse=%s mana=%d: expected %d, got %d" % [inverted, supplied, expected, health_before - f.enemy.get_current_health()])
			_expect(f.u.get_available_mana() == (0 if inverted else supplied), "moon damage has the same inverse-only payment as healing")
			_expect(f.enemy.get_status("druid_root") == null and f.u.discard_pile.has(f.card), "moon damage neither applies root nor enters mana")


func _test_basic_transform_and_strike() -> void:
	var f := _fixture("druid_verdant_strike", false)
	f.u.character_state.weapon_equipment = null
	_expect(f.c.play_card(f.u, f.card, [f.u]), "basic transform needs no weapon or enemy target")
	_expect(f.u.is_druid_transformed() and f.u.get_available_mana() == 1, "basic transform grants one mana and transforms")
	_expect(f.u.current_ap == 9 and f.u.discard_pile.has(f.card), "basic upright costs one AP and discards")
	f = _fixture("druid_verdant_strike", true)
	# Use an ordinary weapon so the sample bear's hand-based armor trigger
	# does not get mistaken for the card's fixed armor reward.
	var weapon := EquipmentData.new()
	weapon.base_damage = 3
	weapon.attack_range = 1
	f.u.character_state.weapon_equipment = weapon
	f.u.gain_temporary_mana(4)
	var health_before: int = f.enemy.get_current_health()
	_expect(f.c.play_card(f.u, f.card, [f.enemy]), "beast strike must play in weapon range")
	_expect(f.enemy.get_current_health() < health_before, "beast strike must deal weapon damage")
	_expect(f.u.get_armor_stacks() == 2, "beast strike grants fixed two armor, not mana-scaled armor")
	_expect(f.u.mana_zone.has(f.card), "beast strike explicitly enters mana")
	_expect(f.u.get_available_mana() == 4, "beast strike entering mana grants no immediate mana")


func _test_rare_form_cycle() -> void:
	var f := _fixture("druid_wild_shape", false)
	_expect(f.c.play_card(f.u, f.card, []), "rare transform must play")
	_expect(f.u.is_druid_transformed() and f.u.get_available_mana() == 2, "rare transform grants two mana before form change")
	_expect(f.u.hand.size() == 1 and f.u.discard_pile.has(f.card), "rare transform draws one and discards")
	f = _fixture("druid_wild_shape", true)
	f.u.set_current_health(10)
	f.u.gain_temporary_mana(3)
	_expect(f.c.play_card(f.u, f.card, []), "return instinct must play")
	_expect(not f.u.is_druid_transformed(), "return instinct must return to human")
	_expect(f.u.get_current_health() == 14 and f.u.get_available_mana() == 3, "return heals four without mana fee or grant")
	_expect(f.u.hand.size() == 1 and f.u.discard_pile.has(f.card), "return draws one and discards despite form change")


func _test_stored_mana_hud() -> void:
	var f := _fixture("druid_rooted_insight", false)
	f.u.gain_mana(3)
	f.u.mana_zone.append(CardData.new())
	var hud := (load("res://scripts/battle/ui/battle_bottom_hud.gd") as Script).new() as Control
	var summary: String = hud.call("_build_resource_summary", f.u)
	_expect(summary.contains("法力 3") and summary.contains("法力区 1张") and not summary.contains("3/3"), "HUD must show stored mana and zone size, not obsolete capacity")
	hud.free()


func _fixture(card_id: String, inverted: bool) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var unit: BattleUnitState
	for player in controller.player_units:
		if player.is_druid():
			unit = player
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = unit
	unit.is_deployed = true
	unit.set_hex_cell(Vector2i(4, 4), controller.map_data)
	unit.current_ap = 10
	unit.hand.clear()
	unit.draw_pile.clear()
	unit.discard_pile.clear()
	unit.mana_zone.clear()
	unit.statuses.clear()
	unit.set_druid_transformed(inverted)
	for i in range(5):
		var drawn := CardData.new()
		drawn.card_name = "可抽牌%d" % i
		unit.draw_pile.append(drawn)
	var card := (load("res://resources/cards/%s.tres" % card_id) as CardData).duplicate(true) as CardData
	unit.hand.append(card)
	var enemy: BattleUnitState = controller.enemy_units[0]
	enemy.statuses.clear()
	enemy.set_hex_cell(Vector2i(5, 4), controller.map_data)
	enemy.set_current_health(enemy.get_max_health())
	return {"c": controller, "u": unit, "card": card, "enemy": enemy}


func _expect(value: bool, message: String) -> void:
	if not value:
		_exit_code = 1
		push_error("DRUID_SIMPLE_CARDS: " + message)
