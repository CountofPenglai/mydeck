extends Resource
class_name AdventureRoomState

@export var room_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
@export var back_type: int = AdventureEnums.BackType.MYSTERY
@export var room_type: int = AdventureEnums.RoomType.EVENT
@export var content_id: String = ""
@export var visited: bool = false
@export var completed: bool = false
@export var content_revealed: bool = false
@export var high_value: bool = false
@export var high_value_marked: bool = false
@export var danger_variant_id: String = ""
@export var shop_stock: Array[Dictionary] = []
@export var shop_initialized: bool = false
@export var shop_restock_count: int = 0
@export var camp_visit_closed: bool = false

# Transitional fields retained until the session/UI migration consumes the new fields.
@export var shelter_type: int = AdventureEnums.ShelterType.OUTPOST
@export var rest_used: bool = false
@export var local_event_resolved: bool = false
@export var runtime_data: Dictionary = {}


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
		"back_type": back_type,
		"type": room_type,
		"content_id": content_id,
		"visited": visited,
		"completed": completed,
		"content_revealed": content_revealed,
		"high_value": high_value,
		"high_value_marked": high_value_marked,
		"danger_variant_id": danger_variant_id,
		"shop_stock": shop_stock.duplicate(true),
		"shop_initialized": shop_initialized,
		"shop_restock_count": shop_restock_count,
		"camp_visit_closed": camp_visit_closed,
		"shelter_type": shelter_type,
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
	result.back_type = int(data.get("back_type", _legacy_back_type(data)))
	result.room_type = int(data.get("type", AdventureEnums.RoomType.EVENT))
	result.content_id = str(data.get("content_id", ""))
	result.visited = bool(data.get("visited", false))
	result.completed = bool(data.get("completed", false))
	result.content_revealed = bool(data.get("content_revealed", false))
	result.high_value = bool(data.get("high_value", false))
	result.high_value_marked = bool(data.get("high_value_marked", false))
	result.danger_variant_id = str(data.get("danger_variant_id", ""))
	for stock_entry in data.get("shop_stock", []):
		if stock_entry is Dictionary:
			result.shop_stock.append((stock_entry as Dictionary).duplicate(true))
	result.shop_initialized = bool(data.get("shop_initialized", false))
	result.shop_restock_count = int(data.get("shop_restock_count", 0))
	result.camp_visit_closed = bool(data.get("camp_visit_closed", false))
	result.shelter_type = int(data.get("shelter_type", AdventureEnums.ShelterType.OUTPOST))
	result.rest_used = bool(data.get("rest_used", false))
	result.local_event_resolved = bool(data.get("local_event_resolved", false))
	result.runtime_data = (data.get("runtime_data", {}) as Dictionary).duplicate(true)
	return result


static func _legacy_back_type(data: Dictionary) -> int:
	match int(data.get("type", AdventureEnums.RoomType.EVENT)):
		AdventureEnums.RoomType.START:
			return AdventureEnums.BackType.START
		AdventureEnums.RoomType.NORMAL_BATTLE:
			return AdventureEnums.BackType.BATTLE
		AdventureEnums.RoomType.ELITE_BATTLE:
			return AdventureEnums.BackType.ELITE
		AdventureEnums.RoomType.BOSS_BATTLE:
			return AdventureEnums.BackType.BOSS
		AdventureEnums.RoomType.SHELTER:
			return AdventureEnums.BackType.CAMP
		AdventureEnums.RoomType.SHOP:
			return AdventureEnums.BackType.SHOP
		_:
			return AdventureEnums.BackType.MYSTERY
