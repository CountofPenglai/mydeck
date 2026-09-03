extends RefCounted
class_name BattleActionFrame

var callback: Callable
var args: Array = []
var priority: int = 0
var label: String = ""
var context = null
var after_callback: Callable
var after_args: Array = []
var ap_spend_entries: Dictionary = {}


static func create(new_callback: Callable, new_args: Array = [], new_priority: int = 0, new_label: String = "", new_context = null, new_after_callback: Callable = Callable(), new_after_args: Array = []) -> BattleActionFrame:
	var frame := BattleActionFrame.new()
	frame.callback = new_callback
	frame.args = new_args
	frame.priority = new_priority
	frame.label = new_label
	frame.context = new_context
	frame.after_callback = new_after_callback
	frame.after_args = new_after_args
	return frame


func record_ap_spent(unit: BattleUnitState, amount: int) -> void:
	if unit == null or amount <= 0:
		return
	var unit_id := unit.get_instance_id()
	var entry: Dictionary = ap_spend_entries.get(unit_id, {
		"unit": unit,
		"amount": 0,
	})
	entry["amount"] = int(entry.get("amount", 0)) + amount
	ap_spend_entries[unit_id] = entry


func get_ap_spend_entries() -> Array:
	return ap_spend_entries.values()
