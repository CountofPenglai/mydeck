extends Node

var _exit_code := 0

func _ready() -> void:
	var f := DruidExpansionFixture.make("druid_spirit_whisper", false)
	_expect(not f.is_empty(), "fixture available")
	if not f.is_empty():
		_test_unarmed_hits_preserve_weapon_bonus(f)
	print("DRUID_WHISPER_UNARMED: completed")
	get_tree().quit(_exit_code)

func _test_unarmed_hits_preserve_weapon_bonus(f: Dictionary) -> void:
	var c := f.c as BattleController
	var user := f.u as BattleUnitState
	var enemy := f.enemy as BattleUnitState
	var source := f.card as CardData
	var discarded := CardData.new(); discarded.card_type = CardEnums.CardType.SKILL
	var revealed := CardData.new(); revealed.card_type = CardEnums.CardType.ATTACK
	user.hand.append(discarded); user.draw_pile.append(revealed)
	_expect(c.play_card(user, source, []), "real Spirit Whisper play grants next weapon strike bonus")
	_expect(user.get_status("druid_spirit_whisper_next_strike") != null, "attack revelation grants bonus")
	var weapon := user.character_state.weapon_equipment
	user.character_state.weapon_equipment = null
	var before := enemy.get_current_health()
	c.perform_strike(user, enemy, null, "unarmed unit")
	_expect(before - enemy.get_current_health() < 5, "unarmed unit hit receives no weapon bonus")
	_expect(user.get_status("druid_spirit_whisper_next_strike") != null, "unarmed unit hit does not consume bonus")
	var trap := c.place_elemental_trap(user, Vector2i(3, 4))
	if trap != null:
		c.perform_object_strike_with_modifier(user, trap, null, 0, "unarmed object")
	_expect(user.get_status("druid_spirit_whisper_next_strike") != null, "unarmed object hit does not consume bonus")
	user.character_state.weapon_equipment = weapon
	enemy.set_current_health(enemy.get_max_health())
	var armed_before := enemy.get_current_health()
	c.perform_strike(user, enemy, null, "armed unit")
	_expect(armed_before - enemy.get_current_health() >= 5, "next armed weapon strike gets +4")
	_expect(user.get_status("druid_spirit_whisper_next_strike") == null, "armed weapon strike consumes bonus")

func _expect(condition: bool, message: String) -> void:
	if condition: return
	_exit_code = 1
	push_error("DRUID_WHISPER_UNARMED FAILURE: %s" % message)
