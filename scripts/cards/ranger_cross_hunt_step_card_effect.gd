extends RangerWeaponCardEffect
class_name RangerCrossHuntStepCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const NEXT_DAGGER_STATUS := preload("res://scripts/status/ranger_next_dagger_multiplier_status.gd")

@export_range(1.0, 5.0, 0.1) var next_dagger_multiplier: float = 1.5


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	var target := targets[0] as BattleUnitState
	var legal_cells := _legal_landing_cells(controller, user, target, str(context.get("equipment_slot", "")))
	var requested: Variant = context.get("landing_cell")
	var valid := not legal_cells.is_empty()
	if requested is Vector2i:
		valid = legal_cells.has(requested as Vector2i)
	if not valid and write_log:
		controller._emit_log("交错猎步没有与当前武器模式对应的合法落点。")
	return valid


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	var equipment_slot := str(context.get("equipment_slot", ""))
	var legal_cells := _legal_landing_cells(controller, user, target, equipment_slot)
	if legal_cells.is_empty():
		return
	var landing_cell: Vector2i = legal_cells[0]
	var requested: Variant = context.get("landing_cell")
	if requested is Vector2i and legal_cells.has(requested as Vector2i):
		landing_cell = requested as Vector2i
	controller.enqueue_effect(
		Callable(self, "_resolve_cross_step"),
		[controller, user, target, card, equipment_slot, landing_cell],
		effect_priority,
		"交错猎步：打击",
		context
	)


func _resolve_cross_step(
		controller: BattleController,
		user: BattleUnitState,
		target: BattleUnitState,
		card: CardData,
		equipment_slot: String,
		landing_cell: Vector2i
	) -> void:
	if controller == null or user == null or target == null or card == null:
		return
	var is_crossbow := _is_crossbow_slot(user, equipment_slot)
	_resolve_weapon_strike(
		controller,
		user,
		target,
		card,
		equipment_slot,
		"交错猎步",
		0,
		1.0,
		{}
	)
	controller.enqueue_effect(
		Callable(controller, "apply_card_movement_to_cell"),
		[user, landing_cell, "交错猎步"],
		-10,
		"交错猎步：转移"
	)
	if is_crossbow:
		controller.enqueue_effect(
			Callable(self, "_grant_next_dagger_multiplier"),
			[user],
			-20,
			"交错猎步：强化下次匕首"
		)
	else:
		controller.enqueue_effect(
			Callable(controller, "enter_ranger_stealth"),
			[user, "交错猎步潜行"],
			-20,
			"交错猎步：进入潜行"
		)


func _grant_next_dagger_multiplier(user: BattleUnitState) -> void:
	if user == null:
		return
	user.remove_status("ranger_next_dagger_multiplier")
	var status := NEXT_DAGGER_STATUS.new() as RangerNextDaggerMultiplierStatus
	status.damage_multiplier = next_dagger_multiplier
	status.stacks = 1
	user.add_status(status)


func _legal_landing_cells(
		controller: BattleController,
		user: BattleUnitState,
		target: BattleUnitState,
		equipment_slot: String
	) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if controller == null or user == null or target == null:
		return result
	var crossbow := _is_crossbow_slot(user, equipment_slot)
	for cell: Vector2i in controller.map_data.get_all_cells():
		if cell == user.cell or not controller.targeting.is_unit_cell_clear(user, cell, false):
			continue
		var distance := BattleHexGrid.distance(target.cell, cell)
		if (crossbow and distance == 1) or (not crossbow and distance >= 2 and distance <= 3):
			result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return result
