extends CardPlayCondition
class_name DiscardHandCondition

@export_range(0, 99, 1) var discard_count: int = 1
@export var discard_all: bool = false


func _init() -> void:
	condition_name = "弃置手牌"


func can_pay(context: Dictionary = {}) -> bool:
	var available := _available_cards(context)
	if discard_all:
		return not available.is_empty()

	return available.size() >= discard_count


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false

	var user := _get_user(context)
	var controller := _get_controller(context)
	var available := _available_cards(context)
	var count := available.size() if discard_all else discard_count
	for i in range(mini(count, available.size())):
		user.discard_card(available[i], context)

	if controller != null:
		controller._emit_log("%s 弃置 %d 张手牌。" % [user.get_display_name(), mini(count, available.size())])
	return true


func get_description() -> String:
	if discard_all:
		return "弃置所有手牌"

	return "弃置 %d 张手牌" % discard_count


func _available_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var user := _get_user(context)
	if user == null:
		return result

	var card_to_exclude = context.get("card")
	for card in user.hand:
		if card == null or card == card_to_exclude:
			continue
		result.append(card)

	return result
