extends RefCounted
class_name BattleTrapController

var controller: BattleController


func setup(new_controller: BattleController) -> void:
	controller = new_controller


func can_place_elemental_trap(owner: BattleUnitState, cell: Vector2i) -> bool:
	return controller != null and owner != null and controller.map_data != null \
		and controller.map_data.is_valid_cell(cell) \
		and controller.get_unit_at_cell(cell) == null \
		and controller.get_battle_object_at_cell(cell) == null \
		and controller.surface_state.get_element(cell) != BattleSurfaceState.Element.NONE


func place_elemental_trap(owner: BattleUnitState, cell: Vector2i) -> BattleObjectState:
	if not can_place_elemental_trap(owner, cell):
		return null
	var trap := controller.spawn_battle_object(BattleObjectDefinition.Kind.ELEMENTAL_TRAP, cell)
	if trap == null:
		return null
	trap.is_trap = true
	trap.owner = owner
	trap.owner_faction = owner.faction
	trap.threat_level = 1
	if get_active_trap_count(owner) > get_trap_limit(owner):
		_resolve_explosion(trap)
	return trap


func get_active_trap_count(owner: BattleUnitState) -> int:
	if controller == null or owner == null:
		return 0
	var count := 0
	for battle_object in controller.battle_objects:
		if battle_object != null and battle_object.is_trap and battle_object.is_active() \
				and battle_object.owner == owner:
			count += 1
	return count


func get_trap_limit(owner: BattleUnitState) -> int:
	return owner.get_trap_limit() if owner != null else 0


func notify_object_attacked(attacker: BattleUnitState, target: BattleObjectState, metadata: Dictionary = {}) -> void:
	if controller == null or target == null or not target.is_trap or target.destroyed or target.trap_explosion_queued \
			or bool(metadata.get("environmental", false)) or not bool(metadata.get("strike", false)):
		return
	queue_explosion(target)


func queue_explosion(trap: BattleObjectState) -> void:
	if controller == null or trap == null or trap.trap_explosion_queued:
		return
	trap.trap_explosion_queued = true
	controller.enqueue_after_current_attack(Callable(self, "_resolve_explosion"), [trap], "元素陷阱爆炸")


func _resolve_explosion(trap: BattleObjectState) -> void:
	if controller == null or trap == null:
		return
	trap.trap_explosion_queued = false
	var element := controller.surface_state.get_element(trap.cell)
	if element != BattleSurfaceState.Element.NONE:
		var cells: Array[Vector2i] = controller.map_data.get_cells_in_range(trap.cell, 1)
		for cell in cells:
			if cell != trap.cell and controller.map_data.is_valid_cell(cell):
				controller.apply_surface_element(cell, element, {"source_cell": trap.cell, "trap_explosion": true})
	trap.current_health = 0
	trap.destroyed = true
	trap.destruction_queued = false
	controller.state_changed.emit()
