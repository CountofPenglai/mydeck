extends Resource
class_name AdventureRoomState

@export var room_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
@export var room_type: int = AdventureEnums.RoomType.EVENT
@export var shelter_type: int = AdventureEnums.ShelterType.OUTPOST
@export var neighbor_ids: PackedStringArray = []
@export var visited: bool = false
@export var completed: bool = false
@export var content_revealed: bool = false
@export var content_id: String = ""
@export var rest_used: bool = false
@export var local_event_resolved: bool = false
@export var runtime_data: Dictionary = {}


func connect_to(other_room_id: String) -> void:
	if other_room_id.is_empty() or neighbor_ids.has(other_room_id):
		return
	neighbor_ids.append(other_room_id)


func is_combat_room() -> bool:
	return room_type in [
		AdventureEnums.RoomType.NORMAL_BATTLE,
		AdventureEnums.RoomType.ELITE_BATTLE,
		AdventureEnums.RoomType.BOSS_BATTLE,
	]


func get_display_name() -> String:
	return AdventureEnums.room_type_label(room_type)


func to_dict() -> Dictionary:
	return {
		"id": room_id,
		"cell": [cell.x, cell.y],
		"type": room_type,
		"shelter_type": shelter_type,
		"neighbors": Array(neighbor_ids),
		"visited": visited,
		"completed": completed,
		"content_revealed": content_revealed,
		"content_id": content_id,
		"rest_used": rest_used,
		"local_event_resolved": local_event_resolved,
		"runtime_data": runtime_data.duplicate(true),
	}


static func from_dict(data: Dictionary) -> AdventureRoomState:
	var result := AdventureRoomState.new()
	result.room_id = str(data.get("id", ""))
	var cell_data: Array = data.get("cell", [0, 0]) as Array
	if cell_data.size() >= 2:
		result.cell = Vector2i(int(cell_data[0]), int(cell_data[1]))
	result.room_type = int(data.get("type", AdventureEnums.RoomType.EVENT))
	result.shelter_type = int(data.get("shelter_type", AdventureEnums.ShelterType.OUTPOST))
	result.neighbor_ids = PackedStringArray(data.get("neighbors", []))
	result.visited = bool(data.get("visited", false))
	result.completed = bool(data.get("completed", false))
	result.content_revealed = bool(data.get("content_revealed", false))
	result.content_id = str(data.get("content_id", ""))
	result.rest_used = bool(data.get("rest_used", false))
	result.local_event_resolved = bool(data.get("local_event_resolved", false))
	result.runtime_data = (data.get("runtime_data", {}) as Dictionary).duplicate(true)
	return result
