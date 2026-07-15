extends EquipmentEffect
class_name RangerPairedWeaponEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

enum WeaponKind {
	WOLF,
	MARROW,
	BLOOD,
	SEA_DRAGON,
	LEAF_SHADOW,
	SACRED_TREE,
	BELOVED,
	WIND,
}

@export var weapon_kind: WeaponKind = WeaponKind.WOLF

const NEXT_MOVE_BONUS := "next_move_bonus"
const NEXT_MELEE_BONUS := "next_melee_bonus"
const TRANSIENT_TURN := "transient_turn"
const MARKS := "ranger_marks"
const HEAVY_COOLDOWN_UNTIL := "heavy_cooldown_until"
const HEAVY_RELOAD_TURN := "heavy_reload_turn"
const LAST_CARD_ID := "last_card_id"
const LAST_CARD_MELEE := "last_card_melee"
const AMMO := "preloaded_ammo"
const AMMO_NEXT_ID := "ammo_next_id"
const AMMO_COPY_COUNT := "ammo_copy_count"
const AMMO_CONFIG_LOCKED := "ammo_config_locked"
const LOCKED_PAYLOAD := "locked_preloaded_payload"
const REMOTE_BROKEN := "remote_broken"
const WIND_DIRECTION := "wind_direction"
const WIND_SET_TURN := "wind_set_turn"
const WIND_PERMISSION := "wind_permission"
const WIND_PIN_AVAILABLE := "wind_pin_available"
const WIND_PIN_PREPARED := "wind_pin_prepared"
const WIND_PIN_LOCKED := "wind_pin_locked"

const BLENDS: Array[int] = [
	BattleSurfaceState.Element.STEAM,
	BattleSurfaceState.Element.LAVA,
	BattleSurfaceState.Element.BLAZE,
	BattleSurfaceState.Element.POISON_BOG,
	BattleSurfaceState.Element.ICE,
	BattleSurfaceState.Element.SANDSTORM,
]
const DIRECTION_LABELS := ["东", "东北", "西北", "西", "西南", "东南"]


func get_damage_bonus(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> int:
	if not (context.get("equipment") is EquipmentData):
		return 0
	var slot := _context_slot(context)
	if weapon_kind == WeaponKind.WOLF and slot == "weapon" and runtime.get_flag(NEXT_MELEE_BONUS) and _is_current_turn(owner, runtime):
		return 1
	if weapon_kind == WeaponKind.BELOVED and slot == "weapon" and runtime.get_flag(REMOTE_BROKEN):
		return 3
	if weapon_kind == WeaponKind.WIND and slot == "paired":
		return 1 if _is_downwind(owner, runtime, context.get("target") as BattleUnitState) else -1
	return 0


func modify_attack_range(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, current_range: int, context: Dictionary = {}) -> int:
	if weapon_kind != WeaponKind.WIND or str(context.get("equipment_slot", "")) != "paired":
		return current_range
	var target := context.get("target") as BattleUnitState
	var target_cell: Vector2i = target.cell if target != null else context.get("target_cell", BattleHexGrid.INVALID_CELL) as Vector2i
	if target_cell == BattleHexGrid.INVALID_CELL:
		return current_range
	return maxi(1, current_range + (1 if _is_downwind_cell(owner, runtime, target_cell) else -1))


func get_next_move_distance_bonus(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	if weapon_kind == WeaponKind.WOLF and runtime.get_flag(NEXT_MOVE_BONUS) and _is_current_turn(_owner, runtime):
		return 1
	if weapon_kind == WeaponKind.WIND and runtime.get_flag(NEXT_MOVE_BONUS) and _is_current_turn(_owner, runtime):
		return 2
	return 0


func modify_ranger_element_collection(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_amount: int, context: Dictionary = {}) -> int:
	if weapon_kind == WeaponKind.MARROW and bool(context.get("from_melee_strike", false)):
		return current_amount * 2
	return current_amount


func modify_ranger_ambush_multiplier(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_multiplier: float, context: Dictionary = {}) -> float:
	if weapon_kind == WeaponKind.LEAF_SHADOW and str(context.get("equipment_slot", "")) != "paired":
		return maxf(current_multiplier, 2.0)
	return current_multiplier


func can_use_attack_mode(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, equipment_slot: String, _context: Dictionary = {}) -> bool:
	if equipment_slot != "paired":
		return true
	if weapon_kind == WeaponKind.SEA_DRAGON:
		return owner.turn_serial > runtime.get_counter(HEAVY_COOLDOWN_UNTIL, -1)
	if weapon_kind == WeaponKind.BELOVED:
		return not runtime.get_flag(REMOTE_BROKEN) and not _ammo(runtime).is_empty()
	return true


func is_battle_setup_ready(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return weapon_kind != WeaponKind.BELOVED or _ammo(runtime).size() == 3


func receives_inactive_runtime_event(event_name: String) -> bool:
	return weapon_kind == WeaponKind.SEA_DRAGON and event_name == "on_ranger_stealth_entered"


func get_runtime_summary(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	match weapon_kind:
		WeaponKind.BLOOD:
			var total := 0
			for value in _marks(runtime).values():
				total += int(value)
			return "游侠印记 %d" % total
		WeaponKind.SEA_DRAGON:
			return "重弩%s" % ("冷却中" if owner.turn_serial <= runtime.get_counter(HEAVY_COOLDOWN_UNTIL, -1) else "就绪")
		WeaponKind.BELOVED:
			return "弹仓 %d / 复制 %d/2%s" % [_ammo(runtime).size(), runtime.get_counter(AMMO_COPY_COUNT), " / 远程报废" if runtime.get_flag(REMOTE_BROKEN) else ""]
		WeaponKind.WIND:
			var direction := runtime.get_counter(WIND_DIRECTION, -1)
			if not _is_current_turn(owner, runtime):
				direction = -1
			return "风向 %s / 风钉%s" % [DIRECTION_LABELS[direction] if direction >= 0 else "未定", "已预备" if runtime.get_flag(WIND_PIN_PREPARED) else "可用" if runtime.get_flag(WIND_PIN_AVAILABLE, true) else "已用"]
		_:
			return ""


func on_battle_started(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.SACRED_TREE:
		var elements := BattleSurfaceState.BASE_ELEMENTS.duplicate()
		elements.sort_custom(func(a: int, b: int) -> bool:
			var left := int(owner.ranger_state.element_inventory.get(a, 0))
			var right := int(owner.ranger_state.element_inventory.get(b, 0))
			return left < right or (left == right and a < b)
		)
		for index in range(mini(2, elements.size())):
			owner.collect_ranger_element(elements[index], 1)
	elif weapon_kind == WeaponKind.WIND:
		runtime.set_flag(WIND_PIN_AVAILABLE, true)
	var controller := context.get("controller") as BattleController
	if controller != null:
		controller.state_changed.emit()


func on_turn_start(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.WIND and runtime.get_counter(WIND_SET_TURN, -1) < owner.turn_serial:
		runtime.set_counter(WIND_DIRECTION, -1)


func on_turn_end(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if weapon_kind in [WeaponKind.WOLF, WeaponKind.WIND]:
		runtime.set_flag(NEXT_MOVE_BONUS, false)
		runtime.set_flag(NEXT_MELEE_BONUS, false)


func on_before_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if _context_slot(context) != "paired":
		return
	if weapon_kind == WeaponKind.BELOVED:
		var ammo := _ammo(runtime)
		if not ammo.is_empty():
			runtime.set_flag(AMMO_CONFIG_LOCKED, true)
			var entry: Dictionary = ammo.pop_front()
			runtime.set_data(AMMO, ammo)
			runtime.set_counter(LOCKED_PAYLOAD, int(entry.get("blend", BattleSurfaceState.Element.NONE)))
	elif weapon_kind == WeaponKind.WIND:
		var target := context.get("target") as BattleUnitState
		var downwind := _is_downwind(owner, runtime, target)
		if downwind and runtime.get_flag(WIND_PIN_PREPARED):
			runtime.set_flag(WIND_PIN_PREPARED, false)
			runtime.set_flag(WIND_PIN_LOCKED, true)


func on_after_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	var profile := context.get("strike_profile_object") as StrikeProfile
	var target := context.get("target") as BattleUnitState
	if profile == null:
		return
	var melee := profile.primary_range_type == EquipmentData.WeaponRangeType.MELEE
	var actual_damage := int(context.get("actual_damage", 0))
	var source: Variant = context.get("source")
	if source is CardData:
		runtime.set_counter(LAST_CARD_ID, (source as CardData).get_instance_id())
		runtime.set_flag(LAST_CARD_MELEE, melee)
	match weapon_kind:
		WeaponKind.WOLF:
			if melee:
				runtime.set_flag(NEXT_MELEE_BONUS, false)
			else:
				runtime.set_flag(NEXT_MOVE_BONUS, true)
				runtime.set_counter(TRANSIENT_TURN, owner.turn_serial)
		WeaponKind.MARROW:
			if not melee and target != null and target.is_alive():
				var controller := context.get("controller") as BattleController
				if controller != null:
					var element := controller.surface_state.get_element(owner.cell)
					if BattleSurfaceState.BASE_ELEMENTS.has(element):
						controller.apply_base_surface_element(target.cell, element)
		WeaponKind.BLOOD:
			if actual_damage > 0 and target != null:
				_add_mark(runtime, target.unit_id, 1, not melee)
		WeaponKind.SEA_DRAGON:
			if not melee:
				runtime.set_counter(HEAVY_COOLDOWN_UNTIL, owner.turn_serial + 1)
		WeaponKind.BELOVED:
			if melee and actual_damage > 0:
				_copy_front_ammo(runtime)
		WeaponKind.WIND:
			if melee:
				runtime.set_flag(NEXT_MOVE_BONUS, true)
				runtime.set_counter(TRANSIENT_TURN, owner.turn_serial)
			elif runtime.get_flag(WIND_PIN_LOCKED):
				runtime.set_flag(WIND_PIN_LOCKED, false)
				if target != null and target.is_alive():
					var rooted := RangerRootedStatus.new()
					rooted.expires_on_turn_serial = target.turn_serial + 1
					target.remove_status(rooted.status_id)
					target.add_status(rooted)


func on_movement_completed(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if bool(context.get("forced", false)):
		return
	if weapon_kind == WeaponKind.WOLF:
		runtime.set_flag(NEXT_MOVE_BONUS, false)
		runtime.set_flag(NEXT_MELEE_BONUS, true)
		runtime.set_counter(TRANSIENT_TURN, _owner.turn_serial)
	elif weapon_kind == WeaponKind.WIND:
		runtime.set_flag(NEXT_MOVE_BONUS, false)
		runtime.set_counter(WIND_DIRECTION, -1)
		runtime.set_flag(WIND_PERMISSION, true)
		runtime.set_counter(TRANSIENT_TURN, _owner.turn_serial)


func on_ranger_combo_milestone(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, threshold: int, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.BLOOD and threshold in [2, 4, 6]:
		var key := "volley_%d_%d" % [owner.turn_serial, threshold]
		if runtime.get_flag(key):
			return
		runtime.set_flag(key, true)
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.enqueue_effect(Callable(self, "_resolve_mark_volley"), [controller, owner, runtime], effect_priority, "逐血齐射", context)
	elif weapon_kind == WeaponKind.SEA_DRAGON and threshold == 4:
		var card := context.get("card") as CardData
		if card == null or runtime.get_counter(LAST_CARD_ID, -1) != card.get_instance_id() or not runtime.get_flag(LAST_CARD_MELEE):
			return
		if int(context.get("play_mode", -1)) != CardEnums.CardPlayMode.COMBO:
			return
		if owner.turn_serial > runtime.get_counter(HEAVY_COOLDOWN_UNTIL, -1) or runtime.get_counter(HEAVY_RELOAD_TURN, -1) == owner.turn_serial:
			return
		runtime.set_counter(HEAVY_RELOAD_TURN, owner.turn_serial)
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.enqueue_effect(Callable(controller, "enter_ranger_stealth"), [owner, "潜鳞重装"], effect_priority - 10, "潜鳞重装", context)


func on_ranger_stealth_entered(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.SEA_DRAGON:
		runtime.set_counter(HEAVY_COOLDOWN_UNTIL, -1)


func on_ranger_stealth_cancelled(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.LEAF_SHADOW:
		return
	var controller := context.get("controller") as BattleController
	var source := context.get("source") as BattleUnitState
	if controller == null or source == null or not source.is_alive() or source.faction == owner.faction:
		return
	if owner.cell_distance_to(source) > controller.get_effective_attack_range_against(owner, source, "paired"):
		return
	controller.enqueue_effect(
		Callable(controller, "perform_strike_with_options"),
		[owner, source, owner.character_state.weapon_equipment, 0, 1.0, "树海猎手反击", "paired", {"equipment_automatic": true, "skip_ranger_ambush": true}],
		effect_priority,
		"树海猎手反击",
		context
	)


func on_ranger_elements_collected(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, added: int, context: Dictionary = {}) -> void:
	if weapon_kind != WeaponKind.MARROW or not bool(context.get("from_melee_strike", false)) or added <= 0:
		return
	var controller := context.get("controller") as BattleController
	if controller != null:
		controller.heal_unit(owner, owner, added, "食髓者")


func on_ranger_payload_completed(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if weapon_kind == WeaponKind.SACRED_TREE:
		if bool(context.get("is_melee", false)):
			var block := BlockStatus.new()
			block.stacks = 1
			owner.add_status(block)
		else:
			_refund_recipe_element(owner, context.get("ingredients", []) as Array)
	elif weapon_kind == WeaponKind.BELOVED and bool(context.get("final_for_strike", false)) and _ammo(runtime).is_empty() and not runtime.get_flag(REMOTE_BROKEN):
		runtime.set_flag(REMOTE_BROKEN, true)
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.enter_ranger_stealth(owner, "弹尽变形")


func consume_preloaded_payload_after_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	if weapon_kind != WeaponKind.BELOVED:
		return BattleSurfaceState.Element.NONE
	var blend := runtime.get_counter(LOCKED_PAYLOAD, BattleSurfaceState.Element.NONE)
	runtime.set_counter(LOCKED_PAYLOAD, BattleSurfaceState.Element.NONE)
	return blend


func get_activated_actions(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var phase_name := str(context.get("phase", ""))
	var can_configure_ammo := weapon_kind == WeaponKind.BELOVED \
		and phase_name in ["deployment", "battle"] \
		and not runtime.get_flag(AMMO_CONFIG_LOCKED) \
		and not runtime.get_flag(REMOTE_BROKEN)
	if can_configure_ammo:
		if _ammo(runtime).size() < 3:
			for blend in BLENDS:
				actions.append({"action_id": "ammo_%d" % blend, "label": "装填：%s" % BattleSurfaceState.label(blend), "momentum_cost": 0, "enabled": true})
		if not _ammo(runtime).is_empty():
			actions.append({"action_id": "ammo_reset", "label": "清空预装弹", "momentum_cost": 0, "enabled": true})
	elif weapon_kind == WeaponKind.WIND and phase_name == "battle":
		if runtime.get_flag(WIND_PERMISSION) and _is_current_turn(owner, runtime):
			for index in range(BattleHexGrid.AXIAL_DIRECTIONS.size()):
				actions.append({"action_id": "wind_%d" % index, "label": "定风：%s" % DIRECTION_LABELS[index], "momentum_cost": 0, "enabled": true})
		if runtime.get_flag(WIND_PIN_AVAILABLE, true) and not runtime.get_flag(WIND_PIN_PREPARED):
			actions.append({"action_id": "wind_pin", "label": "预备风钉弹", "momentum_cost": 0, "enabled": true})
	return actions


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> bool:
	var action_id := str(context.get("equipment_action_id", ""))
	if action_id.begins_with("ammo_"):
		if action_id == "ammo_reset":
			runtime.set_data(AMMO, [])
			runtime.set_counter(AMMO_NEXT_ID, 0)
			return true
		if _ammo(runtime).size() >= 3:
			return false
		_append_original_ammo(runtime, int(action_id.trim_prefix("ammo_")))
		return true
	if action_id.begins_with("wind_") and action_id != "wind_pin":
		if not runtime.get_flag(WIND_PERMISSION):
			return false
		var direction := int(action_id.trim_prefix("wind_"))
		if direction < 0 or direction >= BattleHexGrid.AXIAL_DIRECTIONS.size():
			return false
		runtime.set_flag(WIND_PERMISSION, false)
		runtime.set_counter(WIND_DIRECTION, direction)
		runtime.set_counter(WIND_SET_TURN, owner.turn_serial)
		return true
	if action_id == "wind_pin" and runtime.get_flag(WIND_PIN_AVAILABLE, true) and not runtime.get_flag(WIND_PIN_PREPARED):
		runtime.set_flag(WIND_PIN_AVAILABLE, false)
		runtime.set_flag(WIND_PIN_PREPARED, true)
		return true
	return false


func _context_slot(context: Dictionary) -> String:
	var slot := str(context.get("equipment_slot", ""))
	var equipment := context.get("equipment") as EquipmentData
	if slot.is_empty() and equipment != null:
		slot = "paired" if equipment.range_type == EquipmentData.WeaponRangeType.RANGED else "weapon"
	if slot.is_empty():
		var profile := context.get("strike_profile_object") as StrikeProfile
		if profile != null:
			slot = profile.primary_slot
	return "paired" if slot == "paired" else "weapon"


func _marks(runtime: EquipmentRuntimeState) -> Dictionary:
	return (runtime.get_data(MARKS, {}) as Dictionary).duplicate()


func _add_mark(runtime: EquipmentRuntimeState, unit_id: int, amount: int, only_if_empty: bool) -> void:
	var marks := _marks(runtime)
	var current := int(marks.get(unit_id, 0))
	if only_if_empty and current > 0:
		return
	marks[unit_id] = mini(3, current + amount)
	runtime.set_data(MARKS, marks)


func _resolve_mark_volley(controller: BattleController, owner: BattleUnitState, runtime: EquipmentRuntimeState) -> void:
	var marks := _marks(runtime)
	var targets: Array[BattleUnitState] = []
	for unit in controller.units:
		if unit != null and unit.is_alive() and unit.faction != owner.faction and int(marks.get(unit.unit_id, 0)) > 0:
			targets.append(unit)
	targets.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool: return a.unit_id < b.unit_id)
	if not targets.is_empty() and owner.is_stealthed():
		owner.leave_stealth()
	for target in targets:
		controller.apply_damage(owner, target, 2, "逐血齐射", {"equipment_automatic": true, "fixed_damage": true, "damage_type": CardEnums.DamageType.AGILITY})
		var remaining := int(marks.get(target.unit_id, 0)) - 1
		if remaining <= 0:
			marks.erase(target.unit_id)
		else:
			marks[target.unit_id] = remaining
	runtime.set_data(MARKS, marks)


func _ammo(runtime: EquipmentRuntimeState) -> Array:
	return (runtime.get_data(AMMO, []) as Array).duplicate(true)


func _append_original_ammo(runtime: EquipmentRuntimeState, blend: int) -> void:
	var ammo := _ammo(runtime)
	var next_id := runtime.get_counter(AMMO_NEXT_ID)
	ammo.append({"id": next_id, "blend": blend, "copied": false, "copied_once": false})
	runtime.set_counter(AMMO_NEXT_ID, next_id + 1)
	runtime.set_data(AMMO, ammo)


func _copy_front_ammo(runtime: EquipmentRuntimeState) -> void:
	if runtime.get_counter(AMMO_COPY_COUNT) >= 2:
		return
	var ammo := _ammo(runtime)
	if ammo.is_empty():
		return
	var front: Dictionary = ammo[0]
	if bool(front.get("copied", false)) or bool(front.get("copied_once", false)):
		return
	front["copied_once"] = true
	ammo[0] = front
	ammo.append({"id": -1, "blend": int(front.get("blend", 0)), "copied": true, "copied_once": true})
	runtime.set_data(AMMO, ammo)
	runtime.add_counter(AMMO_COPY_COUNT, 1, 2)


func _refund_recipe_element(owner: BattleUnitState, ingredients: Array) -> void:
	if ingredients.is_empty():
		return
	var selected := int(ingredients[0])
	for raw_element in ingredients:
		var element := int(raw_element)
		var selected_count := int(owner.ranger_state.element_inventory.get(selected, 0))
		var count := int(owner.ranger_state.element_inventory.get(element, 0))
		if count < selected_count or (count == selected_count and element < selected):
			selected = element
	owner.collect_ranger_element(selected, 1)


func _is_downwind(owner: BattleUnitState, runtime: EquipmentRuntimeState, target: BattleUnitState) -> bool:
	if owner == null or target == null:
		return false
	return _is_downwind_cell(owner, runtime, target.cell)


func _is_downwind_cell(owner: BattleUnitState, runtime: EquipmentRuntimeState, target_cell: Vector2i) -> bool:
	if owner == null or target_cell == BattleHexGrid.INVALID_CELL:
		return false
	if runtime.get_counter(WIND_SET_TURN, -1) != owner.turn_serial:
		return false
	var direction := runtime.get_counter(WIND_DIRECTION, -1)
	return direction >= 0 and BattleHexGrid.direction_index(owner.cell, target_cell) == direction


func _is_current_turn(owner: BattleUnitState, runtime: EquipmentRuntimeState) -> bool:
	return owner != null and runtime.get_counter(TRANSIENT_TURN, -1) == owner.turn_serial
