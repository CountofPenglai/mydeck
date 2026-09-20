extends EquipmentEffect
class_name DruidWeaponEffect

enum WeaponKind {
	BRUTE_BEAR,
	WIND_CHEETAH,
	RISE_EAGLE,
	LANTERN_FIRE,
	CHAOS_VIPER,
	DRAGON,
	STAR_FIREFLY,
	KALEIDOSCOPE,
	DOUBLE_SLIME,
}

@export var weapon_kind: WeaponKind = WeaponKind.BRUTE_BEAR

const USED_STRIKE_TURN := "used_strike_turn"
const USED_DAMAGE_TURN := "used_damage_turn"
const UPDRAFT_READY := "updraft_ready"
const UPDRAFT_USED_TURN := "updraft_used_turn"
const LANTERN_MODE := "lantern_mode"
const LANTERN_FUEL := "lantern_fuel"
const RETALIATE_ROUND := "retaliate_round"
const AGE := "dragon_age"
const MATURITY := "dragon_maturity"
const STAR_DRAW_COUNT := "star_draw_count"
const STAR_CYCLE := "star_cycle"
const STAR_BONUS_UNTIL := "star_bonus_until"
const STAR_RANGE_UNTIL := "star_range_until"
const SLIME_SEEP_TURN := "slime_seep_turn"
const TWIN_SPELL_TURN := "twin_spell_turn"
const LOCKED_ELEMENT := "locked_element"
const FIREFLY_PROJECTIONS := "firefly_projections"
const PHENOMENA := ["借域", "异职发现", "倒错", "硬币预押", "命运置顶"]
const SLIME_BODY_CELL := "slime_body_cell"


func modify_attribute(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, attribute: String, current_value: int, _context: Dictionary = {}) -> int:
	if attribute != "agility":
		return current_value
	if weapon_kind == WeaponKind.WIND_CHEETAH and not owner.druid_transformed:
		return current_value + 1
	if weapon_kind == WeaponKind.DRAGON and not owner.druid_transformed:
		return current_value - 3
	return current_value


func modify_resonance_cost(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	if weapon_kind == WeaponKind.KALEIDOSCOPE and owner.druid_transformed and card != null \
			and (current_cost > 0 or card.is_choice_one_card):
		return 1
	return current_cost


func get_damage_bonus(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> int:
	var target := context.get("target") as BattleUnitState
	match weapon_kind:
		WeaponKind.BRUTE_BEAR:
			if runtime.get_counter(USED_STRIKE_TURN, -1) == owner.turn_serial:
				return 0
			if owner.druid_transformed:
				return owner.get_armor_stacks()
			if target != null and owner.cell_distance_to(target) == 1:
				return owner.get_strength()
		WeaponKind.STAR_FIREFLY:
			if not owner.druid_transformed:
				var bonus := 3 if not owner.mana_zone.is_empty() else 0
				if runtime.get_counter(STAR_BONUS_UNTIL, -1) >= owner.turn_serial:
					bonus += 3
				return bonus
	return 0


func modify_attack_range(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_range: int, _context: Dictionary = {}) -> int:
	return current_range


func modify_strike_profile(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, profile: StrikeProfile, _context: Dictionary = {}) -> void:
	if profile == null:
		return
	if weapon_kind == WeaponKind.DRAGON and owner.druid_transformed and profile.primary_slot == "weapon":
		profile.primary_base_damage = 1 + runtime.get_counter(MATURITY)
	if weapon_kind == WeaponKind.STAR_FIREFLY and owner.druid_transformed:
		profile.primary_base_damage = owner.get_available_mana()
	if weapon_kind == WeaponKind.STAR_FIREFLY and not owner.druid_transformed and runtime.get_counter(STAR_RANGE_UNTIL, -1) >= owner.turn_serial:
		profile.primary_range = 6
		profile.primary_damage_type = CardEnums.DamageType.INTELLIGENCE
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed and runtime.get_counter("swap_profile_turn", -1) == owner.turn_serial:
		var previous_damage := profile.primary_base_damage
		profile.primary_base_damage = profile.primary_range
		profile.primary_range = previous_damage


func modify_outgoing_damage(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, damage_context: DamageContext) -> void:
	if damage_context == null or damage_context.amount <= 0:
		return
	if damage_context.source != owner:
		return
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed:
		var runtime := _runtime
		if runtime.get_counter("mirror_damage_action_id", -1) == int(damage_context.metadata.get("action_id", -2)):
			var anomaly := DruidDelayedDamageStatus.new()
			anomaly.stacks = damage_context.amount
			damage_context.target.add_status(anomaly)
			damage_context.target.gain_curse_wave(damage_context.amount, {"controller": damage_context.controller, "reason": "kaleidoscope_mirror"})
			damage_context.metadata["converted_to_status"] = true
			return
	if weapon_kind != WeaponKind.CHAOS_VIPER or not bool(damage_context.metadata.get("strike", false)):
		return
	if owner.druid_transformed:
		damage_context.target.gain_curse_wave(damage_context.amount, {"controller": damage_context.controller, "reason": "viper_strike"})
	else:
		var status := DruidDelayedDamageStatus.new()
		status.stacks = damage_context.amount
		damage_context.target.add_status(status)
	damage_context.metadata["converted_to_status"] = true
	var controller := damage_context.controller
	if controller != null:
		controller._emit_log("%s 将 %d 点伤害转化为%s。" % [owner.get_display_name(), damage_context.amount, "咒波" if owner.druid_transformed else "异常"])


func grants_flying(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return owner.druid_transformed and weapon_kind in [
		WeaponKind.RISE_EAGLE,
		WeaponKind.LANTERN_FIRE,
		WeaponKind.DRAGON,
		WeaponKind.KALEIDOSCOPE,
	]


func get_alternate_range_origins(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed:
		if runtime.get_counter("borrow_range_turn", -1) == owner.turn_serial:
			var borrowed_unit := runtime.get_data("borrow_range_unit") as BattleUnitState
			if borrowed_unit != null and borrowed_unit.is_alive() and borrowed_unit.is_deployed:
				result.append(borrowed_unit.cell)
		return result
	if weapon_kind != WeaponKind.STAR_FIREFLY or not owner.druid_transformed:
		return result
	for value in runtime.get_data(FIREFLY_PROJECTIONS, []) as Array:
		if value is Vector2i:
			result.append(value as Vector2i)
	return result


func get_card_duplicate_targets(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, card: CardData, targets: Array, context: Dictionary = {}) -> Array:
	if weapon_kind != WeaponKind.KALEIDOSCOPE or owner.druid_transformed or card == null or targets.size() != 1:
		return []
	if runtime.get_counter("swap_profile_turn", -1) != owner.turn_serial or runtime.get_counter("mirror_card_turn", -1) == owner.turn_serial:
		return []
	if not (targets[0] is BattleUnitState):
		return []
	var controller := context.get("controller") as BattleController
	if controller == null:
		return []
	var candidates: Array[BattleUnitState] = []
	for candidate in controller.units:
		if candidate == null or candidate == targets[0] or not candidate.is_alive() or not candidate.is_deployed:
			continue
		if controller._targets_are_valid(owner, card, [candidate], false, str(context.get("equipment_slot", "")), int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)), context):
			candidates.append(candidate)
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(left: BattleUnitState, right: BattleUnitState) -> bool:
		var left_distance := owner.get_range_distance_to(left, context)
		var right_distance := owner.get_range_distance_to(right, context)
		return left_distance < right_distance or (left_distance == right_distance and left.unit_id < right.unit_id)
	)
	runtime.set_counter("mirror_card_turn", owner.turn_serial)
	runtime.set_counter("mirror_damage_action_id", controller.get_current_action_id())
	return [candidates[0]]


func get_additional_occupied_cells(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if weapon_kind != WeaponKind.DOUBLE_SLIME:
		return result
	var proxy: Vector2i = runtime.get_data(SLIME_BODY_CELL, BattleHexGrid.INVALID_CELL) as Vector2i
	if proxy != BattleHexGrid.INVALID_CELL:
		result.append(proxy)
	return result


func modify_move_distance_per_ap(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_distance: int, context: Dictionary = {}) -> int:
	if weapon_kind != WeaponKind.DOUBLE_SLIME or not owner.druid_transformed:
		return current_distance
	var controller := owner.battle_controller
	var round_number := controller.battle_round if controller != null else owner.turn_serial
	return current_distance + mini(3, maxi(0, round_number))


func can_use_attack_mode(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _equipment_slot: String, context: Dictionary = {}) -> bool:
	if weapon_kind == WeaponKind.STAR_FIREFLY and owner.druid_transformed:
		var target := context.get("target") as BattleUnitState
		return target == null or owner.cell_distance_to(target) != 1
	return true


func on_turn_start(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed:
		_ensure_phenomena(runtime, owner, context)
	if weapon_kind == WeaponKind.STAR_FIREFLY:
		runtime.set_counter(STAR_DRAW_COUNT, 0)
		if owner.druid_transformed:
			runtime.set_data(FIREFLY_PROJECTIONS, [])
	if weapon_kind == WeaponKind.DRAGON and owner.druid_transformed:
		var armor := owner.clear_armor({"controller": context.get("controller"), "reason": "dragon_shed"})
		var controller := context.get("controller") as BattleController
		var target := controller.get_nearest_opponent(owner) if controller != null else null
		if armor > 0 and target != null and owner.cell_distance_to(target) <= 2:
			controller.enqueue_effect(Callable(controller, "apply_damage"), [owner, target, armor, "蜕甲", {"fixed_damage": true}], effect_priority, "巨龙蜕甲", context)


func on_switched_in(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed:
		_ensure_phenomena(runtime, owner, context)


func on_battle_started(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.DOUBLE_SLIME or owner.cell == BattleHexGrid.INVALID_CELL:
		return
	var controller := context.get("controller") as BattleController
	if controller == null:
		return
	var candidates := controller.map_data.get_cells_in_range(owner.cell, 2)
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := BattleHexGrid.distance(owner.cell, left)
		var right_distance := BattleHexGrid.distance(owner.cell, right)
		return left_distance < right_distance or (left_distance == right_distance and (left.y < right.y or (left.y == right.y and left.x < right.x)))
	)
	for candidate in candidates:
		if candidate != owner.cell and controller.targeting.is_unit_cell_clear(owner, candidate, false):
			runtime.set_data(SLIME_BODY_CELL, candidate)
			return


func on_unit_turn_started(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, started_unit: BattleUnitState, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.CHAOS_VIPER or not owner.druid_transformed or started_unit == null or started_unit.faction == owner.faction:
		return
	if owner.cell_distance_to(started_unit) <= 3:
		_inject_corrosion(owner, started_unit, runtime, context)


func on_card_drawn(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, card: CardData, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.STAR_FIREFLY or owner.druid_transformed:
		return
	var count := runtime.add_counter(STAR_DRAW_COUNT, 1)
	if count >= 2 and owner.has_card_in_hand(card):
		owner.move_hand_card_to_mana(card, context.merged({"reason": "night_ring_draw_replacement"}))


func on_after_card_played(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, card: CardData, context: Dictionary = {}) -> void:
	match weapon_kind:
		WeaponKind.RISE_EAGLE:
			if not owner.druid_transformed and runtime.get_counter(UPDRAFT_USED_TURN, -1) != owner.turn_serial:
				runtime.set_flag(UPDRAFT_READY, true)
		WeaponKind.DRAGON:
			if not owner.druid_transformed:
				runtime.add_counter(AGE, 1, 5)
		WeaponKind.STAR_FIREFLY:
			if card != null:
				owner.get_card_runtime_state(card).erase("played_from_mana")
			if owner.druid_transformed and card != null:
				_consume_projection_for_card(owner, runtime, card, context)
		WeaponKind.DOUBLE_SLIME:
			if owner.druid_transformed and card != null and card.is_twin_spell and runtime.get_counter(TWIN_SPELL_TURN, -1) != owner.turn_serial:
				runtime.set_counter(TWIN_SPELL_TURN, owner.turn_serial)
				owner.current_ap += 2


func on_before_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.RISE_EAGLE and owner.druid_transformed:
		context["ignore_armor"] = true
	if weapon_kind == WeaponKind.LANTERN_FIRE and owner.druid_transformed:
		context["surface_element"] = BattleSurfaceState.Element.FIRE
	if weapon_kind == WeaponKind.DRAGON and owner.druid_transformed and str(context.get("equipment_slot", "")) == "paired":
		context["surface_element"] = BattleSurfaceState.Element.AIR
	if weapon_kind == WeaponKind.KALEIDOSCOPE and owner.druid_transformed:
		context["surface_element"] = runtime.get_counter(LOCKED_ELEMENT, BattleSurfaceState.Element.FIRE)
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not owner.druid_transformed:
		var wager_elements := runtime.get_data("wager_elements", []) as Array
		if not wager_elements.is_empty():
			context["surface_element"] = int(wager_elements.pop_front())
			runtime.set_data("wager_elements", wager_elements)
	if weapon_kind == WeaponKind.CHAOS_VIPER and not owner.druid_transformed and runtime.get_counter("strike_element_until", -1) >= owner.turn_serial:
		context["surface_element"] = runtime.get_counter("strike_element", BattleSurfaceState.Element.NONE)
	if weapon_kind == WeaponKind.STAR_FIREFLY and owner.druid_transformed:
		var target := context.get("target") as BattleUnitState
		if target != null:
			for origin in get_alternate_range_origins(owner, _root, _component, runtime, context):
				if BattleHexGrid.distance(origin, target.cell) <= owner.get_attack_range(str(context.get("equipment_slot", ""))):
					context["firefly_projection"] = origin
					break


func on_after_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	var options := context.get("strike_options", {}) as Dictionary
	match weapon_kind:
		WeaponKind.BRUTE_BEAR:
			var target := context.get("target") as BattleUnitState
			var qualifies := owner.druid_transformed or (target != null and owner.cell_distance_to(target) == 1)
			if qualifies and runtime.get_counter(USED_STRIKE_TURN, -1) != owner.turn_serial:
				runtime.set_counter(USED_STRIKE_TURN, owner.turn_serial)
				if owner.druid_transformed:
					owner.gain_armor(owner.hand.size(), {"controller": context.get("controller"), "reason": "bear_hand_armor"})
		WeaponKind.WIND_CHEETAH:
			if owner.druid_transformed and runtime.get_counter(USED_STRIKE_TURN, -1) != owner.turn_serial and not bool(options.get("druid_cheetah_repeat", false)):
				runtime.set_counter(USED_STRIKE_TURN, owner.turn_serial)
				var controller := context.get("controller") as BattleController
				var target := context.get("target") as BattleUnitState
				if controller != null and target != null and target.is_alive() and owner.cell_distance_to(target) <= owner.get_attack_range(str(context.get("equipment_slot", ""))):
					controller.enqueue_effect(Callable(controller, "perform_strike_with_options"), [owner, target, context.get("source"), 0, 1.0, "猎豹追击", str(context.get("equipment_slot", "")), {"druid_cheetah_repeat": true}], effect_priority, "猎豹追击", context)
		WeaponKind.DRAGON:
			if owner.druid_transformed and int(context.get("actual_damage", 0)) > 0:
				owner.gain_armor(runtime.get_counter(MATURITY), {"controller": context.get("controller"), "reason": "dragon_maturity"})
		WeaponKind.STAR_FIREFLY:
			if context.has("firefly_projection"):
				var projections := runtime.get_data(FIREFLY_PROJECTIONS, []) as Array
				projections.erase(context.get("firefly_projection"))
				runtime.set_data(FIREFLY_PROJECTIONS, projections)


func on_movement_completed(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.STAR_FIREFLY or not owner.druid_transformed or bool(context.get("forced", false)):
		return
	var start_cell: Vector2i = context.get("start_cell", BattleHexGrid.INVALID_CELL) as Vector2i
	if start_cell == BattleHexGrid.INVALID_CELL:
		return
	var projections := runtime.get_data(FIREFLY_PROJECTIONS, []) as Array
	projections.append(start_cell)
	while projections.size() > 3:
		projections.pop_front()
	runtime.set_data(FIREFLY_PROJECTIONS, projections)


func on_after_damage_dealt(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.WIND_CHEETAH and not owner.druid_transformed and int(context.get("amount", 0)) > 0 and runtime.get_counter(USED_DAMAGE_TURN, -1) != owner.turn_serial:
		runtime.set_counter(USED_DAMAGE_TURN, owner.turn_serial)
		var controller := context.get("controller") as BattleController
		controller.enqueue_effect(Callable(owner, "draw_cards"), [1, controller.rng, context.merged({"reason": "wind_staff_damage"})], effect_priority, "疾风抽牌", context)
	if weapon_kind == WeaponKind.STAR_FIREFLY and not owner.druid_transformed and int(context.get("amount", 0)) > 0:
		var damage_context := context.get("damage_context") as DamageContext
		var source_card: CardData = damage_context.metadata.get("source_card") as CardData if damage_context != null else null
		if source_card != null:
			var state := owner.get_card_runtime_state(source_card, false)
			var action_id := int(context.get("action_id", -1))
			if bool(state.get("played_from_mana", false)) and int(state.get("star_cycle_action_id", -2)) != action_id:
				state["star_cycle_action_id"] = action_id
				_advance_star_cycle(owner, runtime, context)


func on_after_damage_taken(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.LANTERN_FIRE or not owner.druid_transformed or int(context.get("amount", 0)) <= 0:
		return
	var controller := context.get("controller") as BattleController
	var source := context.get("source") as BattleUnitState
	if controller == null or source == null or source.faction == owner.faction or owner.cell_distance_to(source) > owner.get_attack_range():
		return
	if runtime.get_counter(RETALIATE_ROUND, -1) == controller.battle_round:
		return
	var fuel := runtime.get_data(LANTERN_FUEL) as CardData
	if fuel == null or not owner.discard_card(fuel, {"controller": controller, "reason": "fire_spirit_fuel"}):
		return
	runtime.set_data(LANTERN_FUEL, null)
	runtime.set_counter(RETALIATE_ROUND, controller.battle_round)
	controller.enqueue_effect(Callable(controller, "perform_strike_with_options"), [owner, source, null, 0, 1.0, "不熄反击", "weapon", {"equipment_automatic": true}], effect_priority, "不熄反击", context)


func on_mana_gained(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _amount: int, _context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.KALEIDOSCOPE:
		runtime.set_counter("mana_gained_turn", owner.turn_serial)


func on_mana_paid(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _amount: int, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.KALEIDOSCOPE or not owner.druid_transformed:
		return
	if runtime.get_counter("mana_refund_turn", -1) == owner.turn_serial or runtime.get_counter("mana_gained_turn", -1) == owner.turn_serial:
		return
	runtime.set_counter("mana_refund_turn", owner.turn_serial)
	owner.gain_mana(1, context.merged({"reason": "unifier_refund"}))


func on_druid_form_changed(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, was_transformed: bool, is_transformed: bool, _context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.DRAGON:
		if not was_transformed and is_transformed:
			runtime.set_counter(MATURITY, runtime.get_counter(AGE))
			runtime.set_counter(AGE, 0)
		elif was_transformed and not is_transformed:
			runtime.set_counter(MATURITY, 0)
	if weapon_kind == WeaponKind.KALEIDOSCOPE and not was_transformed and is_transformed:
		runtime.set_counter(LOCKED_ELEMENT, runtime.get_counter(LOCKED_ELEMENT, BattleSurfaceState.Element.FIRE))
	if weapon_kind == WeaponKind.DOUBLE_SLIME and was_transformed != is_transformed:
		var proxy: Vector2i = runtime.get_data(SLIME_BODY_CELL, BattleHexGrid.INVALID_CELL) as Vector2i
		var controller := _context.get("controller") as BattleController
		if proxy != BattleHexGrid.INVALID_CELL and controller != null:
			var previous := _owner.cell
			_owner.set_hex_cell(proxy, controller.map_data)
			runtime.set_data(SLIME_BODY_CELL, previous)


func on_druid_form_change_requested(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, target_transformed: bool, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.DRAGON and target_transformed and not owner.druid_transformed and context.get("source_card") is CardData:
		runtime.add_counter(AGE, 1, 5)


func modify_druid_card_enters_mana_after_play(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, current_value: bool, _context: Dictionary = {}) -> bool:
	if weapon_kind == WeaponKind.STAR_FIREFLY and owner.druid_transformed:
		return false
	return current_value


func can_replace_druid_form_change(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, target_transformed: bool, _context: Dictionary = {}) -> bool:
	return weapon_kind == WeaponKind.LANTERN_FIRE and target_transformed and not owner.druid_transformed and not owner.draw_pile.is_empty()


func try_replace_druid_form_change(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, target_transformed: bool, context: Dictionary = {}) -> Dictionary:
	if not can_replace_druid_form_change(owner, _root, _component, runtime, target_transformed, context):
		return {}
	var controller := context.get("controller") as BattleController
	var mode := runtime.get_counter(LANTERN_MODE)
	if mode == 1:
		owner.draw_cards(1, controller.rng, context.merged({"reason": "lantern_revelation"}))
		return {"handled": true, "success": true, "log": "%s 的提灯启示牌库顶，普通变形被替代。" % owner.get_display_name()}
	var top: CardData = owner.draw_pile.pop_back() as CardData
	owner.add_card_to_mana_zone(top, context.merged({"reason": "lantern_store"}))
	return {"handled": true, "success": true, "log": "%s 的提灯收纳牌库顶，普通变形被替代。" % owner.get_display_name()}


func get_activated_actions(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> Array[Dictionary]:
	if str(context.get("phase", "battle")) == "deployment":
		return []
	var result: Array[Dictionary] = []
	match weapon_kind:
		WeaponKind.RISE_EAGLE:
			if not owner.druid_transformed:
				result.append(_action("updraft", "升流", runtime.get_flag(UPDRAFT_READY) and not owner.hand.is_empty()))
		WeaponKind.LANTERN_FIRE:
			if not owner.druid_transformed:
				result.append(_action("lantern_mode", "切换提灯预设", true))
				result.append(_action("ignite", "点燃（3法力）", owner.can_pay_mana(3) and not owner.druid_prepare_used))
			else:
				result.append(_action("add_fuel", "添薪", not owner.hand.is_empty()))
		WeaponKind.CHAOS_VIPER:
			if not owner.druid_transformed:
				result.append(_action("transmute", "混沌转化", true))
			else:
				result.append(_action("consume_wave", "蛊爆", _has_wave_target(owner, context)))
		WeaponKind.STAR_FIREFLY:
			if not owner.druid_transformed:
				result.append(_action("mana_play", "取出法力区牌", not owner.mana_zone.is_empty() and runtime.get_counter("mana_play_turn", -1) != owner.turn_serial))
		WeaponKind.KALEIDOSCOPE:
			if not owner.druid_transformed:
				var options := runtime.get_data("phenomena", []) as Array
				for index in range(options.size()):
					var phenomenon := int(options[index])
					result.append(_action("phenomenon_%d" % index, "万象：%s" % PHENOMENA[phenomenon], runtime.get_counter("phenomenon_turn", -1) != owner.turn_serial))
				if runtime.get_flag("wager_pending"):
					for count in range(1, 4):
						result.append(_action("wager_%d" % count, "赌运：预押%d次" % count, true))
				result.append(_action("element", "切换预设元素", true))
		WeaponKind.DOUBLE_SLIME:
			if owner.druid_transformed and runtime.get_counter(SLIME_SEEP_TURN, -1) != owner.turn_serial:
				for count in range(1, mini(3, owner.discard_pile.size()) + 1):
					result.append(_action("seep_%d" % count, "渗流：%d张" % count, true))
	return result


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> bool:
	var action_id := str(context.get("equipment_action_id", ""))
	var controller := context.get("controller") as BattleController
	match action_id:
		"updraft":
			if owner.hand.is_empty(): return false
			runtime.set_flag(UPDRAFT_READY, false)
			runtime.set_counter(UPDRAFT_USED_TURN, owner.turn_serial)
			return owner.move_hand_card_to_mana(owner.hand[0], {"controller": controller, "reason": "updraft"})
		"lantern_mode":
			runtime.set_counter(LANTERN_MODE, 1 - runtime.get_counter(LANTERN_MODE))
			return true
		"ignite":
			if owner.druid_transformed or owner.druid_prepare_used or not owner.pay_mana(3): return false
			owner.set_druid_transformed(true, {"controller": controller, "reason": "lantern_ignite", "bypass_form_replacement": true})
			owner.druid_prepare_used = true
			var target := controller.get_nearest_opponent(owner)
			var damage := owner.get_available_mana()
			if target != null and damage > 0:
				controller.apply_damage(owner, target, damage, "点燃", {"fixed_damage": true, "surface_element": BattleSurfaceState.Element.FIRE})
			return true
		"add_fuel":
			if owner.hand.is_empty(): return false
			runtime.set_data(LANTERN_FUEL, owner.hand[0])
			return true
		"transmute":
			return _transmute_surface(owner, runtime, controller)
		"consume_wave":
			return _consume_wave(owner, controller)
		"mana_play":
			if owner.mana_zone.is_empty(): return false
			var card: CardData = owner.mana_zone.back() as CardData
			owner.remove_card_from_mana_zone(card)
			owner.hand.append(card)
			owner.get_card_runtime_state(card)["played_from_mana"] = true
			runtime.set_counter("mana_play_turn", owner.turn_serial)
			return true
		"element":
			var element := runtime.get_counter(LOCKED_ELEMENT, BattleSurfaceState.Element.FIRE) + 1
			if element > BattleSurfaceState.Element.AIR: element = BattleSurfaceState.Element.FIRE
			runtime.set_counter(LOCKED_ELEMENT, element)
			return true
	if action_id.begins_with("seep_"):
		return _resolve_seep(owner, runtime, int(action_id.trim_prefix("seep_")), controller)
	if action_id.begins_with("wager_"):
		if not runtime.get_flag("wager_pending"):
			return false
		var wager_count := int(action_id.trim_prefix("wager_"))
		if wager_count < 1 or wager_count > 3:
			return false
		runtime.set_flag("wager_pending", false)
		return _resolve_wager(owner, runtime, wager_count, controller)
	if action_id.begins_with("phenomenon_"):
		var option_index := int(action_id.trim_prefix("phenomenon_"))
		var options := runtime.get_data("phenomena", []) as Array
		if option_index < 0 or option_index >= options.size() or runtime.get_counter("phenomenon_turn", -1) == owner.turn_serial:
			return false
		if not _activate_phenomenon(owner, runtime, int(options[option_index]), controller):
			return false
		runtime.set_counter("phenomenon_turn", owner.turn_serial)
		return true
	return false


func get_runtime_summary(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	match weapon_kind:
		WeaponKind.LANTERN_FIRE:
			var top_name := "空"
			if not owner.draw_pile.is_empty():
				top_name = (owner.draw_pile.back() as CardData).card_name
			return "提灯：%s / 顶牌：%s" % [("启示" if runtime.get_counter(LANTERN_MODE) == 1 else "收纳"), top_name]
		WeaponKind.DRAGON: return "岁月 %d / 成熟度 %d" % [runtime.get_counter(AGE), runtime.get_counter(MATURITY)]
		WeaponKind.STAR_FIREFLY: return "星辉轮换 %d" % runtime.get_counter(STAR_CYCLE)
		WeaponKind.KALEIDOSCOPE: return "预设元素：%s / 赌运充能：%d" % [BattleSurfaceState.label(runtime.get_counter(LOCKED_ELEMENT, BattleSurfaceState.Element.FIRE)), (runtime.get_data("wager_elements", []) as Array).size()]
		_: return "飞行" if owner.is_flying() else ""


func _action(id: String, label: String, enabled: bool) -> Dictionary:
	return {"action_id": id, "label": label, "momentum_cost": 0, "enabled": enabled}


func _ensure_phenomena(runtime: EquipmentRuntimeState, owner: BattleUnitState, context: Dictionary) -> void:
	if runtime.get_counter("phenomena_options_turn", -1) == owner.turn_serial:
		return
	if PHENOMENA.is_empty():
		runtime.set_data("phenomena", [])
		runtime.set_counter("phenomena_options_turn", owner.turn_serial)
		return
	if PHENOMENA.size() == 1:
		runtime.set_data("phenomena", [0])
		runtime.set_counter("phenomena_options_turn", owner.turn_serial)
		return
	var controller := context.get("controller") as BattleController
	var first := controller.rng.randi_range(0, PHENOMENA.size() - 1) if controller != null else 0
	var second := first
	while second == first:
		second = controller.rng.randi_range(0, PHENOMENA.size() - 1) if controller != null else (first + 1) % PHENOMENA.size()
	runtime.set_data("phenomena", [first, second])
	runtime.set_counter("phenomena_options_turn", owner.turn_serial)


func _activate_phenomenon(owner: BattleUnitState, runtime: EquipmentRuntimeState, phenomenon: int, controller: BattleController) -> bool:
	match phenomenon:
		0:
			var allies := controller.get_units_by_filter(owner, BattleController.UnitFilter.ALLIES)
			if allies.is_empty():
				return false
			allies.sort_custom(func(left: BattleUnitState, right: BattleUnitState) -> bool:
				var left_distance := owner.cell_distance_to(left)
				var right_distance := owner.cell_distance_to(right)
				return left_distance < right_distance or (left_distance == right_distance and left.unit_id < right.unit_id)
			)
			runtime.set_counter("borrow_range_turn", owner.turn_serial)
			var borrowed_ally := allies[0] as BattleUnitState
			runtime.set_data("borrow_range_unit", borrowed_ally)
			var reciprocal := DruidBorrowedOriginStatus.new()
			reciprocal.status_id = "druid_borrowed_origin_%d" % owner.unit_id
			reciprocal.source_unit = owner
			reciprocal.source_turn_serial = owner.turn_serial
			borrowed_ally.remove_status(reciprocal.status_id)
			borrowed_ally.add_status(reciprocal)
		1:
			var template := load("res://resources/cards/battle_slam.tres") as CardData
			if template == null: return false
			var discovered := template.duplicate(true) as CardData
			owner.hand.append(discovered)
			owner.mark_temporary_card(discovered, 0, true, true)
		2:
			runtime.set_counter("swap_profile_turn", owner.turn_serial)
		3:
			runtime.set_flag("wager_pending", true)
		4:
			if owner.draw_pile.is_empty(): return false
			var chosen: CardData = owner.draw_pile.pop_front() as CardData
			owner.draw_pile.append(chosen)
		_:
			return false
	return true


func _resolve_wager(owner: BattleUnitState, runtime: EquipmentRuntimeState, count: int, controller: BattleController) -> bool:
	if controller == null or count < 1 or count > 3:
		return false
	var successes := 0
	var wager_elements := runtime.get_data("wager_elements", []) as Array
	for _i in range(count):
		if controller.rng.randi_range(0, 1) == 1:
			successes += 1
			wager_elements.append(BattleSurfaceState.BASE_ELEMENTS[controller.rng.randi_range(0, BattleSurfaceState.BASE_ELEMENTS.size() - 1)])
	if successes > 0:
		owner.draw_cards(successes, controller.rng, {"controller": controller, "reason": "kaleidoscope_wager"})
		runtime.set_data("wager_elements", wager_elements)
	if successes < count:
		owner.current_ap = 0
	return true


func _resolve_seep(owner: BattleUnitState, runtime: EquipmentRuntimeState, count: int, controller: BattleController) -> bool:
	if not owner.druid_transformed or runtime.get_counter(SLIME_SEEP_TURN, -1) == owner.turn_serial:
		return false
	if count < 1 or count > mini(3, owner.discard_pile.size()):
		return false
	for _i in range(count):
		var card := owner.discard_pile.pop_back() as CardData
		owner.add_card_to_mana_zone(card, {"controller": controller, "reason": "slime_seep"})
	owner.gain_armor(count * 2, {"controller": controller, "reason": "slime_seep"})
	var weak := DruidWeaknessStatus.new()
	weak.stacks = count
	weak.expires_on_turn_serial = owner.turn_serial + 1
	owner.remove_status(weak.status_id)
	owner.add_status(weak)
	runtime.set_counter(SLIME_SEEP_TURN, owner.turn_serial)
	return true


func _advance_star_cycle(owner: BattleUnitState, runtime: EquipmentRuntimeState, context: Dictionary) -> void:
	var cycle := runtime.get_counter(STAR_CYCLE) % 3
	runtime.set_counter(STAR_CYCLE, (cycle + 1) % 3)
	if cycle == 0:
		var controller := context.get("controller") as BattleController
		controller.enqueue_effect(Callable(owner, "draw_cards"), [1, controller.rng, context.merged({"reason": "star_cycle"})], effect_priority, "星辉抽牌", context)
	elif cycle == 1:
		runtime.set_counter(STAR_BONUS_UNTIL, owner.turn_serial + 1)
	else:
		runtime.set_counter(STAR_RANGE_UNTIL, owner.turn_serial + 1)


func _consume_projection_for_card(owner: BattleUnitState, runtime: EquipmentRuntimeState, card: CardData, context: Dictionary) -> void:
	var targets := context.get("targets", []) as Array
	if targets.is_empty() or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	var card_range := card.get_effective_range(owner, str(context.get("equipment_slot", "")))
	if BattleHexGrid.distance(owner.cell, target.cell) <= card_range:
		return
	var projections := runtime.get_data(FIREFLY_PROJECTIONS, []) as Array
	for origin_value in projections.duplicate():
		var origin: Vector2i = origin_value as Vector2i
		if BattleHexGrid.distance(origin, target.cell) <= card_range:
			projections.erase(origin)
			runtime.set_data(FIREFLY_PROJECTIONS, projections)
			return


func _transmute_surface(owner: BattleUnitState, runtime: EquipmentRuntimeState, controller: BattleController) -> bool:
	if controller == null:
		return false
	var candidates: Array[Vector2i] = []
	for cell in controller.map_data.get_cells_in_range(owner.cell, owner.get_attack_range()):
		if not controller.surface_state.get_readable_elements(cell).is_empty():
			candidates.append(cell)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := BattleHexGrid.distance(owner.cell, left)
		var right_distance := BattleHexGrid.distance(owner.cell, right)
		return left_distance < right_distance or (left_distance == right_distance and (left.y < right.y or (left.y == right.y and left.x < right.x)))
	)
	var target_cell := candidates[0]
	var elements := controller.surface_state.get_readable_elements(target_cell)
	var current := elements[0]
	var replacements := BattleSurfaceState.BASE_ELEMENTS.duplicate()
	replacements.erase(current)
	var next: int = replacements[controller.rng.randi_range(0, replacements.size() - 1)]
	controller.surface_state.add_residue(target_cell, next, controller.battle_round)
	runtime.set_counter("strike_element_until", owner.turn_serial)
	runtime.set_counter("strike_element", next)
	return true


func _has_wave_target(owner: BattleUnitState, context: Dictionary) -> bool:
	var controller := context.get("controller") as BattleController
	if controller == null: return false
	for target in controller.get_opposing_units(owner):
		if target.curse_wave >= 10 and owner.cell_distance_to(target) <= owner.get_attack_range(): return true
	return false


func _consume_wave(owner: BattleUnitState, controller: BattleController) -> bool:
	if controller == null: return false
	for target in controller.get_opposing_units(owner):
		if target.curse_wave < 10 or owner.cell_distance_to(target) > owner.get_attack_range(): continue
		target.consume_curse_wave(10, {"controller": controller, "reason": "viper_detonation"})
		var loss := ceili(float(target.get_current_health()) * 0.5)
		controller.lose_life(owner, target, loss, "咒波引爆", {"curse_wave": true})
		var stun := StunStatus.new()
		stun.stacks = maxi(1, target.get_max_ap(controller.config))
		target.add_status(stun)
		controller._emit_log("%s 引爆咒波，%s 失去 %d 点生命并眩晕。" % [owner.get_display_name(), target.get_display_name(), loss])
		return true
	return false


func _inject_corrosion(owner: BattleUnitState, enemy: BattleUnitState, runtime: EquipmentRuntimeState, context: Dictionary) -> void:
	var controller := context.get("controller") as BattleController
	if controller == null or enemy == null: return
	var key := "corrosion_%d_%d" % [enemy.unit_id, controller.battle_round]
	if runtime.get_flag(key): return
	runtime.set_flag(key, true)
	var curse := CardData.new()
	curse.card_name = "咒害·蛊蚀"
	curse.description = "本牌不能打出。持有者的回合结束时，若本牌仍在其手牌中，将本牌移入放逐区，然后持有者失去 1 点生命并获得 1 点咒波。"
	curse.card_class = CardEnums.CardClass.NEUTRAL
	curse.card_type = CardEnums.CardType.CURSE
	curse.ap_cost = 99
	curse.effect = DruidCorrosionCurseEffect.new()
	enemy.add_card_to_discard(curse, {"controller": controller, "reason": "corrosion_harm"})
