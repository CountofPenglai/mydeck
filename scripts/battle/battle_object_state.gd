extends Resource
class_name BattleObjectState

@export var object_id: int = -1
@export var definition: BattleObjectDefinition
@export var cell: Vector2i = Vector2i.ZERO
@export var current_health: int = 1
@export var fall_direction: Vector2i = Vector2i.ZERO

var destruction_queued: bool = false
var destroyed: bool = false
var triggered_action_ids: Dictionary = {}
var owner: BattleUnitState
var owner_faction: int = BattleUnitState.Faction.PLAYER
var threat_level: int = 0
var is_trap: bool = false
var trap_explosion_queued: bool = false


static func create(
	new_id: int,
	object_kind: int,
	at_cell: Vector2i,
	direction: Vector2i = Vector2i.ZERO
) -> BattleObjectState:
	var state := BattleObjectState.new()
	state.object_id = new_id
	state.definition = BattleObjectDefinition.create_builtin(object_kind)
	state.cell = at_cell
	state.current_health = state.definition.max_health
	if object_kind == BattleObjectDefinition.Kind.ELEMENTAL_TRAP:
		state.is_trap = true
		state.threat_level = 1
	state.fall_direction = BattleHexGrid.AXIAL_DIRECTIONS[0] \
		if object_kind == BattleObjectDefinition.Kind.UNSTABLE_PILLAR \
		and not BattleHexGrid.AXIAL_DIRECTIONS.has(direction) \
		else direction
	return state


func is_active() -> bool:
	return not destroyed and definition != null and current_health > 0


func is_targetable() -> bool:
	return is_active() and definition.targetable


func can_be_damaged() -> bool:
	return not destroyed and definition != null and definition.destructible and current_health > 0


func blocks_movement() -> bool:
	return is_active() and definition.blocks_movement


func blocks_line_of_sight() -> bool:
	return is_active() and definition.blocks_line_of_sight


func get_display_name() -> String:
	return definition.display_name if definition != null else "\u6218\u573a\u5bf9\u8c61"


func get_max_health() -> int:
	return definition.max_health if definition != null else 1


func get_health_ratio() -> float:
	return clampf(float(current_health) / float(maxi(1, get_max_health())), 0.0, 1.0)


func get_threat_level() -> int:
	return threat_level if is_trap and is_active() else 0


func mark_triggered(action_id: int) -> bool:
	if triggered_action_ids.has(action_id):
		return false
	triggered_action_ids[action_id] = true
	return true
