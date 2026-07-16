extends Resource
class_name CardStack

@export var card_data: CardData
@export_range(1, 99, 1) var count: int = 1
@export var stack_id: String = ""


func ensure_stack_id(fallback_id: String) -> String:
	if stack_id.is_empty():
		stack_id = fallback_id
	return stack_id

func get_display_name() -> String:
	if card_data == null:
		return "空卡牌"

	return "%s x%d" % [card_data.card_name, count]
