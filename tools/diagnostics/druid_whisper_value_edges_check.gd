extends Node

var _exit_code := 0

class DiscardGift extends StatusEffect:
	var fired := false
	var gift := CardData.new()
	func _init() -> void:
		status_id = "whisper_discard_gift_probe"
	func on_card_discarded(unit: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
		if not fired and context.get("reason", "") == "druid_spirit_whisper_discard":
			fired = true
			unit.hand.append(gift)

func _ready() -> void:
	_test_form_gate()
	_test_reveal_categories_and_healing()
	_test_fixed_count_and_reshuffle()
	for paired in [false, true]:
		_test_actual_strike(paired, false)
		_test_actual_strike(paired, true)
	_test_turn_end_expiry()
	print("DRUID_WHISPER_VALUE_EDGES: completed")
	get_tree().quit(_exit_code)

func _fixture() -> Dictionary:
	var f := DruidExpansionFixture.make("druid_spirit_whisper", false)
	for unit: BattleUnitState in f.c.player_units:
		unit.set_current_health(unit.get_max_health())
	return f

func _test_form_gate() -> void:
	var f := _fixture()
	f.u.set_druid_transformed(true)
	_expect(not f.c.play_card(f.u, f.card, []), "Whisper cannot bypass form: only Wander has that exception")
	_expect(f.u.current_ap == 10 and f.u.hand.has(f.card), "rejected inverse costs nothing")

func _test_reveal_categories_and_healing() -> void:
	var f := _fixture()
	var multi := CardData.new()
	multi.card_type = CardEnums.CardType.ATTACK
	multi.upright_is_transformation = true
	multi.is_twin_spell = true
	multi.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	f.u.hand.append(CardData.new())
	f.u.draw_pile.append(multi)
	f.u.set_current_health(10)
	_expect(f.c.play_card(f.u, f.card, []), "multi-category reveal starts")
	_expect(f.u.current_ap == 9 and f.u.get_current_health() == 14, "one entity grants AP and healing independently")
	_expect(f.u.get_status("druid_spirit_whisper_next_strike").stacks == 4 and f.u.hand.has(multi), "same entity also grants attack bonus and enters hand")
	var full := _fixture()
	var heal := CardData.new()
	heal.upright_is_transformation = true
	full.u.hand.append(CardData.new())
	full.u.draw_pile.append(heal)
	_expect(full.c.play_card(full.u, full.card, []) and full.u.hand.has(heal), "no wounded ally skips heal without dropping revealed card")
	var repeat := _fixture()
	var ally := repeat.c.player_units[0] as BattleUnitState
	if ally == repeat.u:
		ally = repeat.c.player_units[1]
	ally.is_deployed = true
	ally.set_current_health(12)
	repeat.u.set_current_health(10)
	for _i in range(2):
		repeat.u.hand.append(CardData.new())
		repeat.u.draw_pile.append(heal.duplicate(true))
	_expect(repeat.c.play_card(repeat.u, repeat.card, []), "repeat heal starts")
	_expect(repeat.u.get_current_health() == 14 and ally.get_current_health() == 16, "each heal reselects current lowest HP")
	var undeployed := _fixture()
	var reserve := undeployed.c.player_units[0] as BattleUnitState
	if reserve == undeployed.u:
		reserve = undeployed.c.player_units[1]
	reserve.is_deployed = false
	reserve.set_current_health(1)
	undeployed.u.set_current_health(10)
	undeployed.u.hand.append(CardData.new())
	undeployed.u.draw_pile.append(heal.duplicate(true))
	_expect(undeployed.c.play_card(undeployed.u, undeployed.card, []), "healing with reserve ally starts")
	_expect(reserve.get_current_health() == 1 and undeployed.u.get_current_health() == 14, "undeployed ally is not a battlefield healing target")

func _test_fixed_count_and_reshuffle() -> void:
	var f := _fixture()
	var probe := DiscardGift.new()
	f.u.add_status(probe)
	for _i in range(2):
		f.u.hand.append(CardData.new())
	for _i in range(4):
		f.u.draw_pile.append(CardData.new())
	_expect(f.c.play_card(f.u, f.card, []), "discard descendant test starts")
	_expect(probe.fired and f.u.hand.has(probe.gift), "real discard callback adds a hand entity")
	_expect(f.u.hand.size() == 3 and f.u.draw_pile.size() == 2, "descendant hand growth does not increase reveal count")
	var reshuffle := _fixture()
	var first := CardData.new()
	var second := CardData.new()
	reshuffle.u.hand.append_array([first, second])
	_expect(reshuffle.c.play_card(reshuffle.u, reshuffle.card, []), "empty draw pile reshuffles the two discarded physical cards")
	_expect(reshuffle.u.hand.size() == 2 and reshuffle.u.hand.has(first) and reshuffle.u.hand.has(second), "reshuffle returns distinct entities exactly once")
	_expect(reshuffle.u.discard_pile.size() == 1 and reshuffle.u.discard_pile.has(reshuffle.card), "resolving source cannot be revealed during reshuffle")

func _strike_fixture(with_bonus: bool, paired: bool) -> Dictionary:
	var f := _fixture()
	var weapon := (load("res://resources/items/iron_rock_pair.tres") as EquipmentData).duplicate(true) as EquipmentData
	weapon.trigger_effects.clear()
	if not paired:
		weapon.paired_component = null
	f.u.character_state.weapon_equipment = weapon
	f.u.character_state.weapon_face = 0
	f.u.equipment_runtime_states.clear()
	f.enemy.enemy_state.fixed_max_health_override = 1000
	f.enemy.set_current_health(1000)
	var revealed := CardData.new()
	revealed.card_type = CardEnums.CardType.ATTACK if with_bonus else CardEnums.CardType.SKILL
	f.u.hand.append(CardData.new())
	f.u.draw_pile.append(revealed)
	_expect(f.c.play_card(f.u, f.card, []), "strike setup grants bonus through actual card")
	return f

func _damage(f: Dictionary, object_target: bool) -> int:
	if object_target:
		var target := BattleObjectState.create(987, BattleObjectDefinition.Kind.UNSTABLE_PILLAR, Vector2i(4, 5))
		target.definition.max_health = 1000
		target.current_health = 1000
		f.c.battle_objects.append(target)
		f.c.perform_object_strike_with_modifier(f.u, target, null, 0, "whisper edge", "weapon")
		return 1000 - target.current_health
	var before: int = f.enemy.get_current_health()
	f.c.perform_strike(f.u, f.enemy, null, "whisper edge", "weapon")
	return before - f.enemy.get_current_health()

func _test_actual_strike(paired: bool, object_target: bool) -> void:
	var baseline := _strike_fixture(false, paired)
	var bonus := _strike_fixture(true, paired)
	bonus.u.get_attack_range("weapon", {"controller": bonus.c})
	bonus.u.build_strike_profile_object("weapon", {"controller": bonus.c})
	var normal := _damage(baseline, object_target)
	var boosted := _damage(bonus, object_target)
	_expect(normal > 0 and boosted - normal == (8 if paired else 4), "preview preserves bonus; real single/dual unit/object strike adds four per segment")
	_expect(_damage(bonus, object_target) == _damage(baseline, object_target), "next strike bonus is consumed exactly once")

func _test_turn_end_expiry() -> void:
	var f := _strike_fixture(true, false)
	var ally := f.c.player_units[0] as BattleUnitState
	if ally == f.u:
		ally = f.c.player_units[1]
	ally.is_deployed = true
	f.c.turn_order.assign([f.u, ally])
	f.c.current_turn_index = 0
	f.c.end_current_turn()
	_expect(f.c.current_unit == ally, "real turn end advances to another friendly")
	var baseline := _strike_fixture(false, false)
	_expect(_damage(f, false) == _damage(baseline, false), "unused bonus expires through actual owner turn end")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_exit_code = 1
		push_error("DRUID_WHISPER_VALUE_EDGES FAILURE: " + message)
