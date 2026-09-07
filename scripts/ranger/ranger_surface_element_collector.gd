extends RefCounted
class_name RangerSurfaceElementCollector

# One collection implementation backs both capped inventory collection and the
# bottle's uncapped temporary batch.  The caller decides where the yielded
# tokens go; source commit and notification semantics stay identical.
static func preview(
	controller: BattleController,
	unit: BattleUnitState,
	cells: Array[Vector2i],
	label: String,
	context: Dictionary = {}
) -> Dictionary:
	var result := {"total": 0, "elements": {}}
	if controller == null or unit == null or not unit.is_ranger():
		return result
	var collector_id := "unit:%d" % unit.unit_id
	for cell in cells:
		if controller.map_data == null or not controller.map_data.is_valid_cell(cell):
			continue
		var entries: Array[Dictionary] = controller.surface_state.get_collectible_entries(cell, collector_id)
		for element in _collectible_components(entries):
			var amount := _modified_amount(controller, unit, cell, element, label, context)
			if amount <= 0:
				continue
			result.elements[element] = int(result.elements.get(element, 0)) + amount
			result.total = int(result.total) + amount
	return result


static func collect(
	controller: BattleController,
	unit: BattleUnitState,
	cells: Array[Vector2i],
	label: String,
	context: Dictionary = {},
	store_in_inventory: bool = true
) -> Dictionary:
	var result := {"total": 0, "elements": {}, "cells": []}
	if controller == null or unit == null or not unit.is_ranger():
		return result
	var collector_id := "unit:%d" % unit.unit_id
	for cell in cells:
		if controller.map_data == null or not controller.map_data.is_valid_cell(cell):
			continue
		var entries: Array[Dictionary] = controller.surface_state.get_collectible_entries(cell, collector_id)
		var successful: Array[int] = []
		var cell_total := 0
		for element in _collectible_components(entries):
			var amount := _modified_amount(controller, unit, cell, element, label, context)
			if amount <= 0:
				continue
			var stored := amount
			if store_in_inventory:
				stored = unit.collect_ranger_element(element, amount)
			if stored > 0:
				successful.append(element)
				cell_total += stored
				result.elements[element] = int(result.elements.get(element, 0)) + stored
		if not store_in_inventory and cell_total > 0:
			unit.ranger_state.elements_collected_this_turn += cell_total
		controller.surface_state.commit_collection(cell, collector_id, entries, successful)
		if cell_total > 0:
			unit.notify_ranger_elements_collected(cell_total, context.merged({"controller": controller, "cell": cell, "label": label}))
			result.total = int(result.total) + cell_total
			(result.cells as Array).append(cell)
	if int(result.total) > 0:
		unit.sync_ranger_element_inventory()
		controller._emit_log("%s 从%s采集 %d 枚元素。" % [unit.get_display_name(), label, int(result.total)])
		controller.state_changed.emit()
	return result


static func _collectible_components(entries: Array[Dictionary]) -> Array[int]:
	var components: Array[int] = []
	for entry in entries:
		var entry_components: Array = entry.get("components", [entry.get("element", BattleSurfaceState.Element.NONE)]) as Array
		for value in entry_components:
			var element := int(value)
			if BattleSurfaceState.BASE_ELEMENTS.has(element) and not components.has(element):
				components.append(element)
	components.sort_custom(func(left: int, right: int) -> bool:
		return BattleSurfaceState.BASE_ELEMENTS.find(left) < BattleSurfaceState.BASE_ELEMENTS.find(right)
	)
	return components


static func _modified_amount(
	controller: BattleController,
	unit: BattleUnitState,
	cell: Vector2i,
	element: int,
	label: String,
	context: Dictionary
) -> int:
	return unit.modify_ranger_element_collection(1, context.merged({
		"controller": controller,
		"cell": cell,
		"element": element,
		"label": label,
	}))
