extends RefCounted
class_name BattleResolutionEntry

var callback: Callable
var args: Array = []
var priority: int = 0
var order: int = 0
var label: String = ""
var context = null
var is_trigger: bool = false


static func create(new_callback: Callable, new_args: Array = [], new_priority: int = 0, new_order: int = 0, new_label: String = "", new_context = null, new_is_trigger: bool = false) -> BattleResolutionEntry:
	var entry := BattleResolutionEntry.new()
	entry.callback = new_callback
	entry.args = new_args
	entry.priority = new_priority
	entry.order = new_order
	entry.label = new_label
	entry.context = new_context
	entry.is_trigger = new_is_trigger
	return entry

