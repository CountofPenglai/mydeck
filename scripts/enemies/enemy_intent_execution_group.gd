extends RefCounted
class_name EnemyIntentExecutionGroup

var category: int = -1
var first_slot: int = -1
var last_slot: int = -1
var allocated_ap: int = 0
var remaining_ap: int = 0
var action_count: int = 0
var is_fallback: bool = false
var combo_tags: PackedStringArray = []


static func create(
	new_category: int,
	new_first_slot: int,
	new_last_slot: int,
	new_allocated_ap: int,
	new_is_fallback: bool = false
) -> EnemyIntentExecutionGroup:
	var group := EnemyIntentExecutionGroup.new()
	group.category = new_category
	group.first_slot = new_first_slot
	group.last_slot = new_last_slot
	group.allocated_ap = maxi(0, new_allocated_ap)
	group.remaining_ap = group.allocated_ap
	group.is_fallback = new_is_fallback
	return group


func consume(ap_cost: int) -> int:
	var spent := mini(remaining_ap, maxi(0, ap_cost))
	remaining_ap -= spent
	action_count += 1
	return spent
