extends Resource
class_name CardStack

@export var card_data: CardData
@export_range(1, 99, 1) var count: int = 1

func get_display_name() -> String:
	if card_data == null:
		return "空卡牌"

	return "%s x%d" % [card_data.card_name, count]
