extends RefCounted
class_name ChapterTwoEnemyRules

const TEMPORARY_JINX := preload("res://resources/cards/monster_cards/temporary_jinx.tres")
const BLOOD_INDUSTRY := preload("res://resources/cards/curse_industry_blood.tres")
const MUTATION_CARDS := [
	preload("res://resources/cards/monster_cards/lashing_tentacle.tres"),
	preload("res://resources/cards/monster_cards/blood_mouth.tres"),
	preload("res://resources/cards/monster_cards/extra_limbs.tres"),
	preload("res://resources/cards/monster_cards/scorch_sac.tres"),
]


static func on_battle_started(controller: BattleController) -> void:
	if controller == null:
		return
	for unit in controller.enemy_units:
		if unit == null or unit.enemy_state == null:
			continue
		match _id(unit):
			&"corrupt_heart_veil":
				unit.enemy_state.runtime_state["phase"] = 1
				unit.enemy_state.runtime_state["gospel_pending"] = false
			&"blood_construct":
				unit.enemy_state.runtime_state["inverted"] = false
				unit.enemy_state.runtime_state["rebirth_used"] = false
			&"gray_bastion_paladin":
				unit.enemy_state.runtime_state["badges"] = PackedStringArray(["cup", "shield", "wing", "sword"])
			&"triumph_statue":
				unit.enemy_state.runtime_state["support_no_turn"] = true
				unit.enemy_state.runtime_state["last_badge_health"] = unit.get_current_health()


static func on_turn_started(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or not unit.is_alive() or unit.enemy_state == null:
		return
	match _id(unit):
		&"gray_shield_guard":
			if is_in_formation(controller, unit):
				unit.gain_armor(4, {"controller": controller, "reason": "formation_shield"})
		&"field_priest":
			if is_in_formation(controller, unit):
				for ally in _adjacent_military_allies(controller, unit):
					controller.heal_unit(unit, ally, 2, "战地祷告")
		&"standard_bearer":
			var allies := _adjacent_military_allies(controller, unit)
			if not allies.is_empty():
				allies.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool: return a.get_current_health() < b.get_current_health())
				var target: BattleUnitState = allies[0]
				target.gain_armor(3, {"controller": controller, "reason": "standard_bearer"})
				target.draw_cards(1, controller.rng, {"controller": controller, "reason": "standard_bearer"})
		&"punishment_knight":
			if is_in_formation(controller, unit):
				unit.enemy_state.runtime_state["formation_move_bonus"] = 2
		&"corrupt_heart_veil":
			if int(unit.enemy_state.runtime_state.get("phase", 1)) == 2:
				_pull_farthest_player(controller, unit, 3)


static func on_turn_ended(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or unit.enemy_state == null:
		return
	match _id(unit):
		&"creation_shard":
			if bool(unit.enemy_state.runtime_state.get("overloaded", false)) and unit.is_alive():
				unit.enemy_state.runtime_state["overloaded"] = false
				controller.lose_life(unit, unit, unit.get_current_health(), "造物过载")
		&"corrupt_heart_veil":
			if int(unit.enemy_state.runtime_state.get("phase", 1)) == 1:
				_push_adjacent_players(controller, unit, 3)
				if controller.battle_round >= 3:
					unit.enemy_state.runtime_state["gospel_pending"] = true
			else:
				for player in controller.player_units:
					if player != null and player.is_alive() and unit.cell_distance_to(player) <= 2:
						controller.apply_damage(unit, player, player.curse_zone.size(), "诅咒共振", {"fixed_damage": true})
		&"gray_bastion_paladin":
			if _has_badge(unit, "cup"):
				controller.heal_unit(unit, unit, 4, "圣杯徽记")


static func on_card_played(controller: BattleController, unit: BattleUnitState, card: CardData) -> void:
	if controller == null or unit == null or unit.enemy_state == null or card == null:
		return
	if _id(unit) == &"blood_construct" and card.is_curse_card():
		unit.gain_curse_wave(2, {"controller": controller, "reason": "blood_construct_industry"})


static func on_movement_completed(_controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	if unit == null or unit.enemy_state == null or bool(context.get("forced", false)):
		return
	unit.enemy_state.runtime_state.erase("formation_move_bonus")
	unit.enemy_state.runtime_state.erase("forced_march_move_bonus")
	if _id(unit) == &"military_god_remains" and bool(unit.enemy_state.runtime_state.get("wing_miracle_pending", false)):
		unit.enemy_state.runtime_state.erase("wing_miracle_pending")


static func on_armor_changed(_controller: BattleController, _unit: BattleUnitState, _previous: int, _current: int) -> void:
	pass


static func on_after_damage_dealt(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	if controller == null or unit == null or unit.enemy_state == null or int(context.get("amount", 0)) <= 0:
		return
	var target := context.get("target") as BattleUnitState
	match _id(unit):
		&"fortress_crossbow":
			if is_in_formation(controller, unit) and target != null \
					and int(unit.enemy_state.runtime_state.get("crossbow_wave_turn", -1)) != unit.turn_serial:
				unit.enemy_state.runtime_state["crossbow_wave_turn"] = unit.turn_serial
				target.gain_curse_wave(2, {"controller": controller, "reason": "fortress_crossbow"})
		&"corrupt_heart_veil":
			if int(unit.enemy_state.runtime_state.get("phase", 1)) == 2 and target != null:
				var action_id := int(context.get("action_id", 0))
				var key := "veil_wave_%d_%d" % [action_id, target.unit_id]
				if not bool(unit.battle_action_flags.get(key, false)) and target.curse_wave > 0:
					unit.battle_action_flags[key] = true
					controller.apply_damage(unit, target, target.curse_wave, "咒波增幅", {
						"fixed_damage": true,
						"veil_wave_bonus": true,
					})


static func on_after_damage_taken(controller: BattleController, unit: BattleUnitState, _context: Dictionary) -> void:
	if controller == null or _id(unit) != &"triumph_statue":
		return
	var paladin := _find_enemy(controller, &"gray_bastion_paladin")
	if paladin == null:
		return
	var previous := int(unit.enemy_state.runtime_state.get("last_badge_health", 40))
	var current := unit.get_current_health()
	unit.enemy_state.runtime_state["last_badge_health"] = current
	for threshold in [30, 20, 10, 0]:
		if previous > threshold and current <= threshold:
			var badge: String = str({30: "cup", 20: "shield", 10: "wing", 0: "sword"}[threshold])
			_remove_badge(paladin, badge)
			controller._emit_log("凯旋圣像的%s圣徽熄灭。" % _badge_label(badge))


static func on_after_strike(_controller: BattleController, unit: BattleUnitState, _context: Dictionary) -> void:
	if unit == null or unit.enemy_state == null:
		return
	if _id(unit) == &"holy_spearman":
		unit.enemy_state.runtime_state["spear_strike_turn"] = unit.turn_serial
	if _id(unit) == &"gray_bastion_paladin":
		unit.enemy_state.runtime_state["sword_strike_turn"] = unit.turn_serial


static func modify_agility(_unit: BattleUnitState, current: int) -> int:
	return current


static func modify_damage_bonus(unit: BattleUnitState, current: int, context: Dictionary = {}) -> int:
	if unit == null or unit.enemy_state == null:
		return current
	var target := context.get("target") as BattleUnitState
	match _id(unit):
		&"holy_spearman":
			if target != null and is_in_formation(unit.battle_controller, unit) \
					and unit.cell_distance_to(target) == unit.get_attack_range() \
					and int(unit.enemy_state.runtime_state.get("spear_strike_turn", -1)) != unit.turn_serial:
				current += 2
		&"gray_bastion_paladin":
			if _has_badge(unit, "sword") and int(unit.enemy_state.runtime_state.get("sword_strike_turn", -1)) != unit.turn_serial:
				current += 3
		&"creation_shard":
			if bool(unit.enemy_state.runtime_state.get("overloaded", false)):
				current += 3
	return current


static func modify_damage_reduction(unit: BattleUnitState, current: int, _context: Dictionary = {}) -> int:
	if unit == null or unit.enemy_state == null:
		return current
	if _id(unit) == &"holy_bastion_commander":
		current += mini(2, _adjacent_military_allies(unit.battle_controller, unit).size())
	if _id(unit) == &"gray_bastion_paladin" and _has_badge(unit, "shield"):
		current += 2
	return current


static func modify_max_ap(unit: BattleUnitState, current: int) -> int:
	if _id(unit) == &"gray_bastion_paladin" and _has_badge(unit, "wing"):
		return current + 1
	return current


static func modify_move_distance(unit: BattleUnitState, current: int) -> int:
	if unit == null or unit.enemy_state == null:
		return current
	current += int(unit.enemy_state.runtime_state.get("formation_move_bonus", 0))
	current += int(unit.enemy_state.runtime_state.get("forced_march_move_bonus", 0))
	if _id(unit) == &"gray_bastion_paladin" and _has_badge(unit, "wing"):
		current += 1
	return current


static func decorate_intent_plan(controller: BattleController, unit: BattleUnitState, plan: EnemyIntentPlan) -> void:
	if controller == null or unit == null or unit.enemy_state == null or plan == null:
		return
	match _id(unit):
		&"holy_bastion_commander":
			var command := "hold" if (controller.battle_round + 1) % 2 == 0 else "advance"
			plan.steps.push_front(_special_step(command, "固守" if command == "hold" else "推进"))
		&"creation_shard":
			plan.steps.push_front(_special_step("shard_exchange", "放逐手牌并生成怪物化职业牌"))
			if unit.get_current_health() <= unit.get_max_health() / 2:
				plan.steps.push_front(_special_step("shard_overload", "过载：本回合伤害+3，行动后死亡"))
		&"corrupt_heart_veil":
			if bool(unit.enemy_state.runtime_state.get("gospel_pending", false)):
				plan.steps.push_front(_special_step("gospel", "福音"))
		&"blood_construct":
			var inverted := bool(unit.enemy_state.runtime_state.get("inverted", false))
			if not inverted and unit.curse_wave > 0:
				plan.steps.push_front(_special_step("construct_invert", "倒转并显化畸变"))
			elif not inverted and unit.get_current_health() > 5 and _find_enemy(controller, &"flesh_spawn") == null:
				plan.steps.push_front(_special_step("construct_spawn", "支付5生命派出血肉衍生物"))
			elif inverted and _has_devour_target(controller, unit):
				plan.steps.push_front(_special_step("construct_devour", "吞噬相邻非首领友军"))
			elif inverted and unit.curse_wave == 0 and not bool(unit.enemy_state.runtime_state.get("rebirth_used", false)):
				plan.steps.push_front(_special_step("construct_rebirth", "往生"))
		&"military_god_remains":
			plan.steps.push_front(_special_step("remains_switch", "切换军神武器"))
			var badges: PackedStringArray = unit.enemy_state.runtime_state.get("badges", PackedStringArray())
			if not badges.is_empty():
				plan.steps.push_front(_special_step("remains_miracle", "%s圣徽奇迹" % _badge_label(badges[0])))


static func execute_intent_step(controller: BattleController, unit: BattleUnitState, step: Dictionary) -> bool:
	if str(step.get("type", "")) != "chapter_two_special":
		return false
	match str(step.get("action", "")):
		"hold":
			_resolve_commander_order(controller, unit, true)
		"advance":
			_resolve_commander_order(controller, unit, false)
		"shard_exchange":
			_resolve_shard_exchange(controller, unit)
		"shard_overload":
			unit.enemy_state.runtime_state["overloaded"] = true
			controller._emit_log("%s 令自身过载，本回合获得+3伤害加值。" % unit.get_display_name())
		"gospel":
			resolve_gospel(controller, unit, ChapterTwoEnemyCatalog.create_gospel_card())
		"construct_invert":
			_invert_construct(controller, unit)
		"construct_spawn":
			_try_spawn_flesh(controller, unit)
		"construct_devour":
			_try_devour(controller, unit)
		"construct_rebirth":
			_resolve_construct_rebirth(controller, unit)
		"remains_switch":
			unit.enemy_state.switch_weapon()
			controller._emit_log("%s 切换了公开武器模式。" % unit.get_display_name())
		"remains_miracle":
			_resolve_next_badge_miracle(controller, unit)
		_:
			return false
	controller.state_changed.emit()
	return true


static func try_handle_lethal(controller: BattleController, _source: BattleUnitState, target: BattleUnitState, _context: Dictionary) -> bool:
	if controller == null or target == null or target.enemy_state == null:
		return false
	if _id(target) == &"gray_bastion_paladin" and not bool(target.enemy_state.runtime_state.get("merge_queued", false)):
		target.set_current_health(1)
		target.enemy_state.runtime_state["merge_queued"] = true
		controller.enqueue_effect(
			Callable(ChapterTwoEnemyRules, "resolve_paladin_merge"),
			[controller, target],
			-1000,
			"灰垒圣骑与凯旋圣像合体"
		)
		return true
	return false


static func resolve_paladin_merge(controller: BattleController, paladin: BattleUnitState) -> void:
	if controller == null or paladin == null or not paladin.is_alive():
		return
	var statue := _find_enemy_any(controller, &"triumph_statue")
	var statue_health := statue.get_current_health() if statue != null and statue.is_alive() else 0
	var badges: PackedStringArray = paladin.enemy_state.runtime_state.get("badges", PackedStringArray())
	var state := ChapterTwoEnemyCatalog.create_enemy(&"military_god_remains", controller.rng.randi())
	if state == null:
		return
	state.runtime_state["max_health_override"] = 60 + statue_health
	state.runtime_state["badges"] = badges.duplicate()
	state.current_health = 60 + statue_health
	paladin.enemy_state = state
	paladin.statuses.clear()
	paladin.clear_armor({"controller": controller, "reason": "paladin_merge"})
	paladin.hand.clear()
	paladin.draw_pile.clear()
	paladin.discard_pile.clear()
	paladin.exiled_pile.clear()
	paladin.enchant_zone.clear()
	paladin.distortion_state.reset_for_battle()
	paladin.ensure_initialized(controller.config, controller.rng)
	if statue != null:
		paladin.set_hex_cell(statue.cell, controller.map_data)
		statue.set_current_health(0)
		statue.battle_action_flags["death_notified"] = true
		controller.units.erase(statue)
		controller.enemy_units.erase(statue)
		controller.turn_order.erase(statue)
	controller._emit_log("灰垒圣骑与圣像合体，化为军神圣骸。")
	controller.state_changed.emit()


static func resolve_gospel(controller: BattleController, unit: BattleUnitState, card: CardData) -> void:
	if controller == null or unit == null or not unit.is_alive():
		return
	for target in controller.units:
		if target == null or target == unit or not target.is_alive():
			continue
		var total := 6 + unit.get_damage_bonus({
			"controller": controller,
			"card": card,
			"target": target,
			"resolved_damage_type": CardEnums.DamageType.INTELLIGENCE,
		})
		var dealt := controller.apply_damage(unit, target, total, "福音", {
			"source_card": card,
			"resolved_damage_type": CardEnums.DamageType.INTELLIGENCE,
		})
		if dealt > 0:
			target.gain_curse_wave(1, {"controller": controller, "reason": "gospel"})
			_add_temporary_jinx(target, controller)
	unit.enemy_state.runtime_state["gospel_pending"] = false
	unit.enemy_state.runtime_state["phase"] = 2
	unit.enemy_state.runtime_state["strength_override"] = 6
	unit.enemy_state.runtime_state["agility_override"] = 3
	unit.enemy_state.runtime_state["intelligence_override"] = 1
	unit.enemy_state.runtime_state["max_health_override"] = 135
	unit.enemy_state.runtime_state["base_damage_override"] = 4
	unit.enemy_state.runtime_state["range_override"] = 2
	unit.current_ap = 0
	controller._emit_log("腐心帷幕开启福音，转入第二阶段。")


static func is_in_formation(controller: BattleController, unit: BattleUnitState) -> bool:
	return not _adjacent_military_allies(controller, unit).is_empty()


static func is_support_unit(unit: BattleUnitState) -> bool:
	return _has_tag(unit, "support")


static func _resolve_commander_order(controller: BattleController, unit: BattleUnitState, hold: bool) -> void:
	var affected: Array[BattleUnitState] = [unit]
	for ally in controller.enemy_units:
		if ally != null and ally != unit and ally.is_alive() and _has_tag(ally, "military") and is_in_formation(controller, ally):
			affected.append(ally)
	for ally in affected:
		if hold:
			ally.gain_armor(4, {"controller": controller, "reason": "commander_hold"})
		else:
			ally.enemy_state.runtime_state["forced_march_move_bonus"] = maxi(1, int(ally.enemy_state.runtime_state.get("forced_march_move_bonus", 0)))
			ally.gain_next_attack_damage_bonus(2)
	controller._emit_log("%s 发布%s命令。" % [unit.get_display_name(), "固守" if hold else "推进"])


static func _resolve_shard_exchange(controller: BattleController, unit: BattleUnitState) -> void:
	if unit.hand.is_empty():
		return
	var removed: CardData = unit.hand[controller.rng.randi_range(0, unit.hand.size() - 1)]
	unit.hand.erase(removed)
	unit.exiled_pile.append(removed)
	var pools := ["mage", "warlock", "ranger", "monster"]
	var pool_id: String = pools[controller.rng.randi_range(0, pools.size() - 1)]
	var generated := ChapterTwoEnemyCatalog.create_variant_card(pool_id, controller.rng.randi())
	if generated != null:
		unit.hand.append(generated)
		controller._emit_log("%s 放逐%s，并从%s副本池生成%s。" % [unit.get_display_name(), removed.card_name, pool_id, generated.card_name])


static func _invert_construct(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or unit.enemy_state == null \
			or bool(unit.enemy_state.runtime_state.get("inverted", false)) or unit.curse_wave <= 0:
		return
	var count := mini(4, unit.curse_wave)
	unit.consume_curse_wave(unit.curse_wave, {"controller": controller, "reason": "blood_construct_invert"})
	unit.enemy_state.runtime_state["inverted"] = true
	unit.enemy_state.active_weapon_index = 1
	unit.enemy_state.runtime_state["strength_override"] = 4
	unit.enemy_state.runtime_state["agility_override"] = 1
	unit.enemy_state.runtime_state["intelligence_override"] = 4
	for index in range(count):
		var template := MUTATION_CARDS[index % MUTATION_CARDS.size()] as CardData
		if template != null:
			var manifested := template.duplicate(true) as CardData
			unit.enchant_zone.append(manifested)
			unit.distortion_state.register_manifestation(manifested)
	controller._emit_log("%s 消耗咒波并倒转，显化%d张临时畸变牌。" % [unit.get_display_name(), count])


static func _resolve_construct_rebirth(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or unit.enemy_state == null \
			or not bool(unit.enemy_state.runtime_state.get("inverted", false)) \
			or unit.curse_wave != 0 or bool(unit.enemy_state.runtime_state.get("rebirth_used", false)):
		return
	unit.enemy_state.runtime_state["rebirth_used"] = true
	controller.gain_life(unit, unit, 10, "魔血往生")
	var curse := BLOOD_INDUSTRY as CardData
	if curse != null:
		var runtime_curse := curse.duplicate(true) as CardData
		runtime_curse.reward_eligible = false
		unit.draw_pile.append(runtime_curse)
		unit.shuffle_draw_pile(controller.rng)


static func _try_spawn_flesh(controller: BattleController, owner: BattleUnitState) -> void:
	if owner.get_current_health() <= 5 or _find_enemy(controller, &"flesh_spawn") != null:
		return
	var cell := _find_adjacent_clear_cell(controller, owner)
	if cell == BattleHexGrid.INVALID_CELL:
		return
	controller.lose_life(owner, owner, 5, "血肉派生")
	if not owner.is_alive():
		return
	var state := ChapterTwoEnemyCatalog.create_enemy(&"flesh_spawn", controller.rng.randi())
	if state == null:
		return
	var spawn := controller.spawn_enemy_unit(state, cell, 2, owner)
	if spawn == null:
		return
	spawn.enemy_state.runtime_state["shared_deck_owner_id"] = owner.unit_id
	controller._emit_log("%s 派出血肉衍生物。" % owner.get_display_name())


static func _try_devour(controller: BattleController, unit: BattleUnitState) -> void:
	for ally in controller.enemy_units:
		if ally == null or ally == unit or not ally.is_alive() or _has_tag(ally, "boss") or unit.cell_distance_to(ally) > 1:
			continue
		var health := ally.get_current_health()
		var base_damage := ally.enemy_state.get_active_weapon().base_damage if ally.enemy_state != null and ally.enemy_state.get_active_weapon() != null else 0
		ally.set_current_health(0)
		controller._notify_unit_death(unit, ally, {"reason": "blood_construct_devour"})
		unit.enemy_state.runtime_state["max_health_bonus"] = int(unit.enemy_state.runtime_state.get("max_health_bonus", 0)) + health
		unit.enemy_state.current_health += health
		unit.enemy_state.flat_damage_bonus += base_damage
		controller._emit_log("%s 吞噬%s，获得其生命与武器伤害加值。" % [unit.get_display_name(), ally.get_display_name()])
		return


static func _has_devour_target(controller: BattleController, unit: BattleUnitState) -> bool:
	for ally in controller.enemy_units:
		if ally != null and ally != unit and ally.is_alive() and not _has_tag(ally, "boss") \
				and unit.cell_distance_to(ally) <= 1:
			return true
	return false


static func _resolve_next_badge_miracle(controller: BattleController, unit: BattleUnitState) -> void:
	var badges: PackedStringArray = unit.enemy_state.runtime_state.get("badges", PackedStringArray())
	if badges.is_empty():
		return
	var badge := badges[0]
	badges.remove_at(0)
	unit.enemy_state.runtime_state["badges"] = badges
	match badge:
		"cup":
			controller.heal_unit(unit, unit, 12, "圣杯奇迹")
		"shield":
			unit.gain_armor(12, {"controller": controller, "reason": "shield_miracle"})
		"wing":
			unit.enemy_state.runtime_state["wing_miracle_pending"] = true
			_move_toward_nearest(controller, unit, 3)
			for target in controller.player_units:
				if target != null and target.is_alive() and unit.cell_distance_to(target) <= 1:
					controller.force_move_away(target, unit.cell, 1, unit)
		"sword":
			for target in controller.player_units:
				if target != null and target.is_alive() and unit.cell_distance_to(target) <= unit.get_attack_range():
					controller.perform_strike(unit, target, null, "巨刃奇迹")


static func _move_toward_nearest(controller: BattleController, unit: BattleUnitState, max_distance: int) -> void:
	var target := controller.get_nearest_opponent(unit)
	if target == null:
		return
	var best := unit.cell
	var best_distance := unit.cell_distance_to(target)
	for cell in controller.map_data.get_cells_in_range(unit.cell, max_distance):
		if not controller.targeting.is_unit_cell_clear(unit, cell, false):
			continue
		var distance := controller.map_data.get_distance(cell, target.cell)
		if distance < best_distance:
			best = cell
			best_distance = distance
	if best != unit.cell:
		controller.apply_card_path_movement_to_cell(unit, best, -1, true, "圣翼奇迹")


static func _pull_farthest_player(controller: BattleController, unit: BattleUnitState, distance: int) -> void:
	var targets: Array[BattleUnitState] = []
	for player in controller.player_units:
		if player != null and player.is_alive():
			targets.append(player)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		var da := unit.cell_distance_to(a)
		var db := unit.cell_distance_to(b)
		if da != db:
			return da > db
		if a.get_current_health() != b.get_current_health():
			return a.get_current_health() < b.get_current_health()
		return a.turn_order_index < b.turn_order_index
	)
	controller.force_move_toward(targets[0], unit.cell, distance, unit)


static func _push_adjacent_players(controller: BattleController, unit: BattleUnitState, distance: int) -> void:
	for player in controller.player_units:
		if player != null and player.is_alive() and unit.cell_distance_to(player) <= 1:
			controller.force_move_away(player, unit.cell, distance, unit)


static func _adjacent_military_allies(controller: BattleController, unit: BattleUnitState) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if controller == null or unit == null:
		return result
	for ally in controller.enemy_units:
		if ally != null and ally != unit and ally.is_alive() and _has_tag(ally, "military") and unit.cell_distance_to(ally) <= 1:
			result.append(ally)
	return result


static func _find_enemy(controller: BattleController, archetype: StringName) -> BattleUnitState:
	for unit in controller.enemy_units:
		if unit != null and unit.is_alive() and _id(unit) == archetype:
			return unit
	return null


static func _find_enemy_any(controller: BattleController, archetype: StringName) -> BattleUnitState:
	for unit in controller.enemy_units:
		if unit != null and _id(unit) == archetype:
			return unit
	return null


static func _find_adjacent_clear_cell(controller: BattleController, unit: BattleUnitState) -> Vector2i:
	for cell in controller.map_data.get_cells_in_range(unit.cell, 1):
		if cell != unit.cell and controller.targeting.is_unit_cell_clear(null, cell, false):
			return cell
	return BattleHexGrid.INVALID_CELL


static func _add_temporary_jinx(target: BattleUnitState, controller: BattleController) -> void:
	var template := TEMPORARY_JINX as CardData
	if target == null or template == null:
		return
	var card := template.duplicate(true) as CardData
	target.draw_pile.append(card)
	target.mark_temporary_card(card, 0, false, false)
	target.shuffle_draw_pile(controller.rng)


static func _special_step(action: String, label: String) -> Dictionary:
	return {"type": "chapter_two_special", "action": action, "label": label, "ap": 0, "attack": 0, "defense": 0}


static func _has_tag(unit: BattleUnitState, tag: String) -> bool:
	return unit != null and unit.enemy_state != null and unit.enemy_state.enemy_data != null \
		and unit.enemy_state.enemy_data.unit_tags.has(tag)


static func _has_badge(unit: BattleUnitState, badge: String) -> bool:
	if unit == null or unit.enemy_state == null:
		return false
	var badges: PackedStringArray = unit.enemy_state.runtime_state.get("badges", PackedStringArray())
	return badges.has(badge)


static func _remove_badge(unit: BattleUnitState, badge: String) -> void:
	if unit == null or unit.enemy_state == null:
		return
	var badges: PackedStringArray = unit.enemy_state.runtime_state.get("badges", PackedStringArray())
	badges.erase(badge)
	unit.enemy_state.runtime_state["badges"] = badges


static func _badge_label(badge: String) -> String:
	return {"cup": "杯", "shield": "盾", "wing": "翼", "sword": "剑"}.get(badge, badge)


static func _id(unit: BattleUnitState) -> StringName:
	if unit == null or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return &""
	return unit.enemy_state.enemy_data.archetype_id
