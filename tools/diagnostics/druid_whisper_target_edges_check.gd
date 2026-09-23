extends Node

var _exit_code := 0

class ProbeEffect extends CardEffect:
	var responses := 0
	var kill_source := false
	var move_target := false
	func on_zone_owner_targeted(owner: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
		responses += 1
		var controller := context.get("controller") as BattleController
		var source := context.get("source") as BattleUnitState
		if kill_source and source != null:
			source.set_current_health(0)
		if move_target and controller != null:
			owner.set_hex_cell(Vector2i(0, 0), controller.map_data)

class UnpayableEnemyEffect extends CardEffect:
	func can_pay_play_cost(_context: Dictionary = {}) -> bool:
		return false

func _ready() -> void:
	_test_failed_payment_and_friendly_and_submerge_do_not_notify()
	_test_stampeding_declares_only_actual_recipients()
	_test_roots_boundary_self_count_and_live_owner()
	_test_response_descendants_cancel_stale_source_and_target()
	print("DRUID_WHISPER_TARGET_EDGES: completed")
	get_tree().quit(_exit_code)

func _fixture() -> Dictionary:
	return DruidExpansionFixture.make("druid_spirit_whisper", false)

func _probe(owner: BattleUnitState) -> ProbeEffect:
	var card := CardData.new()
	var effect := ProbeEffect.new()
	card.effect = effect
	owner.mana_zone.append(card)
	return effect

func _enemy_card(path: String) -> CardData:
	return (load(path) as CardData).duplicate(true) as CardData

func _play(controller: BattleController, enemy: BattleUnitState, card: CardData, targets: Array = []) -> bool:
	enemy.hand.append(card)
	enemy.current_ap = 10
	controller.current_unit = enemy
	return controller.play_card(enemy, card, targets)

func _test_failed_payment_and_friendly_and_submerge_do_not_notify() -> void:
	var f := _fixture(); if f.is_empty(): return
	var c := f.c as BattleController; var owner := f.u as BattleUnitState; var enemy := f.enemy as BattleUnitState
	var probe := _probe(owner)
	var unpaid := CardData.new(); unpaid.ap_cost = 1; unpaid.effect = UnpayableEnemyEffect.new()
	_expect(not _play(c, enemy, unpaid), "unpayable enemy card is rejected")
	_expect(probe.responses == 0, "payment failure never notifies target response")
	var ally := c.enemy_units[1] as BattleUnitState
	ally.is_deployed = true; ally.set_hex_cell(Vector2i(5, 5), c.map_data)
	_expect(_play(c, enemy, _enemy_card("res://resources/cards/monster_cards/guard_hiss.tres"), [ally]), "friendly guard hiss resolves")
	_expect(probe.responses == 0, "friendly enemy target does not notify player mana response")
	c.surface_state.add_residue(Vector2i(4, 5), BattleSurfaceState.Element.WATER, c.battle_round)
	_expect(_play(c, enemy, _enemy_card("res://resources/cards/monster_cards/submerge.tres"), [Vector2i(4, 5)]), "SUBMERGE resolves to water cell")
	_expect(probe.responses == 0, "cell-only SUBMERGE does not notify occupants")

func _test_stampeding_declares_only_actual_recipients() -> void:
	var f := _fixture(); if f.is_empty(): return
	var c := f.c as BattleController; var near := f.u as BattleUnitState; var enemy := f.enemy as BattleUnitState
	var far := c.player_units[1] as BattleUnitState
	near.set_hex_cell(Vector2i(4, 4), c.map_data); far.set_hex_cell(Vector2i(0, 0), c.map_data)
	var near_probe := _probe(near); var far_probe := _probe(far)
	_expect(_play(c, enemy, _enemy_card("res://resources/cards/monster_cards/stampeding_feet.tres")), "STAMPEDING_FEET resolves")
	_expect(near_probe.responses == 1 and far_probe.responses == 0, "STAMPEDING_FEET notifies each actual in-range recipient and excludes out-of-range units")

func _test_roots_boundary_self_count_and_live_owner() -> void:
	var f := _fixture(); if f.is_empty(): return
	var c := f.c as BattleController; var owner := f.u as BattleUnitState; var enemy := f.enemy as BattleUnitState
	var outside := c.enemy_units[1] as BattleUnitState
	enemy.set_hex_cell(Vector2i(5, 4), c.map_data); outside.is_deployed = true; outside.set_hex_cell(Vector2i(7, 4), c.map_data)
	owner.add_status(preload("res://scripts/status/druid_root_status.gd").new())
	var whisper := f.card as CardData; owner.mana_zone.append(whisper)
	_expect(_play(c, enemy, _enemy_card("res://resources/cards/monster_cards/extra_limbs.tres")), "boundary EXTRA_LIMBS resolves")
	_expect(enemy.has_status("druid_root") and outside.has_status("druid_root"), "radius-three roots include boundary")
	_expect(owner.get_armor_stacks() >= 3, "self-root is counted with boundary enemy for armor after damage")
	var dead := _fixture(); if dead.is_empty(): return
	var dead_owner := dead.u as BattleUnitState; var dead_enemy := dead.enemy as BattleUnitState; var dead_c := dead.c as BattleController
	dead_owner.set_current_health(0); dead_owner.mana_zone.append(dead.card as CardData)
	_expect(_play(dead_c, dead_enemy, _enemy_card("res://resources/cards/monster_cards/extra_limbs.tres")), "enemy action with dead target resolves")
	_expect(dead_owner.get_armor_stacks() == 0, "dead owner does not gain response")
	var undeployed := _fixture(); if undeployed.is_empty(): return
	var undeployed_owner := undeployed.u as BattleUnitState; var undeployed_enemy := undeployed.enemy as BattleUnitState; var undeployed_c := undeployed.c as BattleController
	undeployed_owner.is_deployed = false; undeployed_owner.mana_zone.append(undeployed.card as CardData)
	_expect(_play(undeployed_c, undeployed_enemy, _enemy_card("res://resources/cards/monster_cards/extra_limbs.tres")), "enemy action with undeployed owner resolves")
	_expect(undeployed_owner.get_armor_stacks() == 0, "undeployed owner does not gain response")

func _test_response_descendants_cancel_stale_source_and_target() -> void:
	var killed := _fixture(); if killed.is_empty(): return
	var c := killed.c as BattleController; var target := killed.u as BattleUnitState; var enemy := killed.enemy as BattleUnitState
	var killer := _probe(target); killer.kill_source = true
	var before := target.get_current_health()
	_expect(_play(c, enemy, _enemy_card("res://resources/cards/monster_cards/extra_limbs.tres")), "kill-source response action starts")
	_expect(killer.responses == 1 and target.get_current_health() == before, "response descendant killing source prevents stale hit")
	var moved := _fixture(); if moved.is_empty(): return
	var mc := moved.c as BattleController; var mt := moved.u as BattleUnitState; var me := moved.enemy as BattleUnitState
	var mover := _probe(mt); mover.move_target = true
	var health := mt.get_current_health()
	_expect(_play(mc, me, _enemy_card("res://resources/cards/monster_cards/extra_limbs.tres")), "move-target response action starts")
	_expect(mover.responses == 1 and mt.get_current_health() == health, "response descendant moving declared recipient prevents stale retarget")

func _expect(condition: bool, message: String) -> void:
	if condition: return
	_exit_code = 1
	push_error("DRUID_WHISPER_TARGET_EDGES FAILURE: %s" % message)
