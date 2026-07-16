extends Resource
class_name PendingAdventureTransaction

@export var transaction_type: int = AdventureEnums.TransactionType.NONE
@export var transaction_id: String = ""
@export var payload: Dictionary = {}
@export var committed: bool = true


func begin(type: int, id: String, data: Dictionary = {}) -> void:
	transaction_type = type
	transaction_id = id
	payload = data.duplicate(true)
	committed = false


func clear() -> void:
	transaction_type = AdventureEnums.TransactionType.NONE
	transaction_id = ""
	payload.clear()
	committed = true


func to_dict() -> Dictionary:
	return {
		"type": transaction_type,
		"id": transaction_id,
		"payload": payload.duplicate(true),
		"committed": committed,
	}


static func from_dict(data: Dictionary) -> PendingAdventureTransaction:
	var result := PendingAdventureTransaction.new()
	result.transaction_type = int(data.get("type", AdventureEnums.TransactionType.NONE))
	result.transaction_id = str(data.get("id", ""))
	result.payload = (data.get("payload", {}) as Dictionary).duplicate(true)
	result.committed = bool(data.get("committed", true))
	return result
