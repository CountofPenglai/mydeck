extends RefCounted
class_name ChapterOneEnemyRules

const ABYSS_SHARED_ARMOR := 16
const ABYSS_SHARED_ARMOR_KEY := "abyss_shared_armor"


static func on_battle_started(controller: BattleController) -> void:
	if controller == null:
		return
	for unit in controller.enemy_units:
		if _id(unit) == &"abyss_scale":
			unit.enemy_state.runtime_state["abyss_phase"] = 1
			unit.enemy_state.runtime_state[ABYSS_SHARED_ARMOR_KEY] = ABYSS_SHARED_ARMOR
			for player in controller.player_units:
				if player == null or not player.is_alive():
					continue
				player.remove_status("abyss_shared_armor")
				var shared_armor := AbyssSharedArmorStatus.new()
				shared_armor.boss_unit_id = unit.unit_id
				shared_armor.stacks = ABYSS_SHARED_ARMOR
				player.add_status(shared_armor)
			controller._emit_log("渊鳞展开 %d 点共有护甲，所有冒险者共享该护甲池。" % ABYSS_SHARED_ARMOR)


static func on_turn_started(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or not unit.is_alive():
		return
	if unit.faction == BattleUnitState.Faction.ENEMY and _has_living_priest(controller) and _is_on_water(controller, unit):
		controller.heal_unit(unit, unit, 2, "引潮光环")
	match _id(unit):
		&"fish_priest", &"high_priest":
			controller.apply_base_surface_element(unit.cell, BattleSurfaceState.Element.WATER)
		&"fish_champion":
			if unit.enemy_state.active_weapon_index == 0:
				unit.enemy_state.runtime_state["momentum"] = mini(5, int(unit.enemy_state.runtime_state.get("momentum", 0)) + 1)
		&"kraken":
			var ratio := float(unit.get_current_health()) / float(maxi(1, unit.get_max_health()))
			var slots := 3 if ratio > 0.66 else (2 if ratio > 0.33 else 1)
			unit.current_ap *= slots
			unit.enemy_state.runtime_state["kraken_slots"] = slots
			var extra_draw := slots - 1
			if extra_draw > 0:
				unit.draw_cards(extra_draw, controller.rng, {
					"controller": controller,
					"reason": "kraken_health_threshold",
					"extra_draw": true,
				})


static func on_turn_ended(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or not unit.is_alive():
		return
	if _id(unit) == &"abyss_scale":
		controller.lose_life(unit, unit, 3, "深渊衰竭", {"environmental": true})
		if unit.is_alive() and int(unit.enemy_state.runtime_state.get("abyss_phase", 1)) == 2:
			unit.gain_armor(3, {"controller": controller, "reason": "abyss_phase_two"})


static func on_movement_completed(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	if controller == null or unit == null or _id(unit) != &"harpoon_fish" or bool(context.get("forced", false)):
		return
	if controller.current_unit != unit or int(unit.enemy_state.runtime_state.get("harpoon_ap_turn", -1)) == unit.turn_serial:
		return
	var start_cell := context.get("start_cell", unit.cell) as Vector2i
	var end_cell := context.get("end_cell", unit.cell) as Vector2i
	var started_in_water := _cell_has_water(controller, start_cell)
	var ended_in_water := _cell_has_water(controller, end_cell)
	if started_in_water == ended_in_water:
		return
	unit.enemy_state.runtime_state["harpoon_ap_turn"] = unit.turn_serial
	unit.current_ap += 2
	controller._emit_log("%s 跨越水域边界，获得2 AP。" % unit.get_display_name())


static func on_card_played(controller: BattleController, unit: BattleUnitState, card: CardData) -> void:
	if controller == null or unit == null or card == null or _id(unit) != &"unclean_one" or not card.is_curse_card():
		return
	var corruption := mini(4, int(unit.enemy_state.runtime_state.get("corruption", 0)) + 1)
	var previous := int(unit.enemy_state.runtime_state.get("corruption", 0))
	if corruption <= previous:
		return
	unit.enemy_state.runtime_state["corruption"] = corruption
	unit.enemy_state.runtime_state["max_health_bonus"] = corruption * 2
	unit.enemy_state.flat_damage_bonus += 1
	controller.heal_unit(unit, unit, 2, "污化")
	controller._emit_log("%s 获得污化%d。" % [unit.get_display_name(), corruption])


static func on_armor_changed(_controller: BattleController, _unit: BattleUnitState, _previous: int, _current: int) -> void:
	pass


static func sync_abyss_shared_armor(controller: BattleController, remaining: int) -> void:
	if controller == null:
		return
	for player in controller.player_units:
		if player == null:
			continue
		var status := player.get_status("abyss_shared_armor")
		if status == null:
			continue
		if remaining <= 0:
			player.remove_status("abyss_shared_armor")
		else:
			status.stacks = remaining


static func break_abyss_shared_armor(controller: BattleController, unit: BattleUnitState) -> void:
	if controller == null or unit == null or unit.enemy_state == null \
			or _id(unit) != &"abyss_scale" \
			or int(unit.enemy_state.runtime_state.get("abyss_phase", 1)) >= 2:
		return
	unit.enemy_state.runtime_state[ABYSS_SHARED_ARMOR_KEY] = 0
	sync_abyss_shared_armor(controller, 0)
	unit.enemy_state.runtime_state["abyss_phase"] = 2
	unit.enemy_state.active_weapon_index = 1
	for cell in controller.map_data.get_all_cells():
		controller.surface_state.set_terrain(cell, BattleSurfaceState.Terrain.ABYSS)
	controller._emit_log("渊鳞的共有护甲被击穿，战场坠入深渊。")
	controller.state_changed.emit()


static func try_handle_lethal(controller: BattleController, source: BattleUnitState, target: BattleUnitState, context: Dictionary) -> bool:
	if controller == null or target == null or target.enemy_state == null:
		return false
	if _id(target) == &"hungry_fish" and not bool(target.enemy_state.runtime_state.get("reversed", false)):
		target.enemy_state.runtime_state["reversed"] = true
		target.enemy_state.runtime_state["max_health_override"] = 7
		target.enemy_state.runtime_state["strength_override"] = 0
		target.enemy_state.runtime_state["agility_override"] = 2
		target.enemy_state.runtime_state["base_damage_override"] = 3
		target.enemy_state.runtime_state["range_override"] = 1
		target.clear_armor({"controller": controller, "reason": "reverse_fish"})
		target.statuses.clear()
		target.set_current_health(target.get_max_health())
		target.battle_action_flags.erase("death_notified")
		controller._emit_log("%s 原地逆位，转化为逆位鱼人。" % target.get_display_name())
		return true
	if _id(target) == &"hungry_fish" and bool(target.enemy_state.runtime_state.get("reversed", false)):
		var nearest := controller.get_nearest_opponent(target)
		if nearest != null and target.cell_distance_to(nearest) <= target.get_attack_range():
			var stun := StunStatus.new()
			stun.stacks = 2
			nearest.add_status(stun)
	_notify_high_priests_of_death(controller, source, target, context)
	return false


static func modify_agility(unit: BattleUnitState, current: int) -> int:
	if unit == null or unit.enemy_state == null:
		return current
	if unit.enemy_state.runtime_state.has("agility_override"):
		current = int(unit.enemy_state.runtime_state.agility_override)
	if _id(unit) == &"harpoon_fish" and unit.battle_controller != null and _is_on_water(unit.battle_controller, unit):
		current += 3
	return current


static func modify_damage_bonus(unit: BattleUnitState, current: int) -> int:
	if unit != null and unit.faction == BattleUnitState.Faction.ENEMY and unit.battle_controller != null \
			and _has_living_priest(unit.battle_controller) and _is_on_water(unit.battle_controller, unit):
		return current + 1
	return current


static func modify_max_ap(unit: BattleUnitState, current: int) -> int:
	return current


static func switch_champion_weapon(controller: BattleController, unit: BattleUnitState, target: BattleUnitState) -> bool:
	if controller == null or unit == null or _id(unit) != &"fish_champion" or not unit.enemy_state.switch_weapon():
		return false
	var momentum := int(unit.enemy_state.runtime_state.get("momentum", 0))
	unit.enemy_state.runtime_state["momentum"] = 0
	if target != null and momentum > 0:
		var best := unit.cell
		var best_distance := unit.cell_distance_to(target)
		for cell in controller.map_data.get_cells_in_range(unit.cell, momentum):
			if not controller.targeting.is_unit_cell_clear(unit, cell, false):
				continue
			var distance := controller.map_data.get_distance(cell, target.cell)
			if distance < best_distance:
				best = cell
				best_distance = distance
		if best != unit.cell:
			controller.apply_card_path_movement_to_cell(unit, best, -1, true, "冠军长枪突进")
		unit.gain_next_attack_damage_bonus(momentum * 2)
	controller._emit_log("%s 切换武器并消耗%d势。" % [unit.get_display_name(), momentum])
	return true


static func _notify_high_priests_of_death(controller: BattleController, source: BattleUnitState, target: BattleUnitState, context: Dictionary) -> void:
	if target.faction != BattleUnitState.Faction.ENEMY or _id(target) == &"high_priest":
		return
	for priest in controller.enemy_units:
		if priest == null or not priest.is_alive() or _id(priest) != &"high_priest":
			continue
		priest.statuses.clear()
		priest.curse_wave = 0
		priest.enemy_state.runtime_state.clear()
		controller.lose_life(source, priest, 5, "护卫死亡反噬", context)


static func _has_living_priest(controller: BattleController) -> bool:
	for unit in controller.enemy_units:
		if unit != null and unit.is_alive() and _id(unit) in [&"fish_priest", &"high_priest"]:
			return true
	return false


static func _is_on_water(controller: BattleController, unit: BattleUnitState) -> bool:
	return controller != null and unit != null and _cell_has_water(controller, unit.cell)


static func _cell_has_water(controller: BattleController, cell: Vector2i) -> bool:
	return controller.surface_state.get_readable_elements(cell).has(BattleSurfaceState.Element.WATER)


static func _id(unit: BattleUnitState) -> StringName:
	if unit == null or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return &""
	return unit.enemy_state.enemy_data.archetype_id
