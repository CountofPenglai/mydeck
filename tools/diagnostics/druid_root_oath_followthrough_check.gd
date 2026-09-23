extends Node


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")

var _exit_code := 0


func _ready() -> void:
	_test_blood_tide_consumes_self_root_and_drops_live_incarnation_values()
	print("DRUID_ROOT_OATH_FOLLOWTHROUGH: completed")
	get_tree().quit(_exit_code)


# This is an end-to-end cross-card test.  Replacing incarnation's live root
# query with an entry snapshot, or letting Blood Tide skip its self root, makes
# the post-flow weapon hit/reduction remain at the pre-consumption values.
func _test_blood_tide_consumes_self_root_and_drops_live_incarnation_values() -> void:
	var f := DruidExpansionFixture.make("druid_root_oath", true)
	_expect(not f.is_empty(), "root oath fixture is available")
	if f.is_empty():
		return
	var controller := f.c as BattleController
	var user := f.u as BattleUnitState
	var target := f.enemy as BattleUnitState
	target.enemy_state.fixed_max_health_override = 1000
	target.set_current_health(target.get_max_health())
	_expect(controller.play_card(user, f.card as CardData, []), "inverse root oath enters enchant before follow-through")
	user.add_status(ROOT_STATUS.new())
	var rooted_weapon_damage := _weapon_damage(controller, user, target)
	user.set_druid_transformed(false)
	_expect(_incoming_damage(controller, target, user) == 7, "self root enables incarnation's three-point nonfixed reduction before Blood Tide")
	user.set_druid_transformed(true)
	user.gain_mana(2, {"controller": controller, "reason": "root oath follow-through"})
	user.current_ap = 10
	var blood_tide := (load("res://resources/cards/druid_overgrowth_graft.tres") as CardData).duplicate(true) as CardData
	user.hand.append(blood_tide)
	target.set_current_health(target.get_max_health())
	_expect(controller.play_card(user, blood_tide, [target]), "inverse Blood Tide resolves against a live high-health target")
	_expect(not user.has_status("druid_root"), "Blood Tide consumes the nearest root, which is the caster at distance zero")
	user.set_druid_transformed(false)
	var unrooted_weapon_damage := _weapon_damage(controller, user, target)
	_expect(rooted_weapon_damage - unrooted_weapon_damage == 2, "post-consumption real weapon hit loses exactly the self-root conditional +2")
	_expect(_incoming_damage(controller, target, user) == 10, "post-consumption nonfixed damage loses incarnation reduction immediately")


func _weapon_damage(controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> int:
	target.set_current_health(target.get_max_health())
	var before := target.get_current_health()
	controller.perform_strike(user, target, null, "root oath follow-through", "weapon")
	return before - target.get_current_health()


func _incoming_damage(controller: BattleController, source: BattleUnitState, target: BattleUnitState) -> int:
	target.set_current_health(target.get_max_health())
	var before := target.get_current_health()
	controller.apply_damage(source, target, 10, "root oath follow-through", {"ignore_armor": true})
	return before - target.get_current_health()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_ROOT_OATH_FOLLOWTHROUGH FAILURE: %s" % message)
