extends CardEffect
class_name StandFirmCardEffect

@export_range(0, 99, 1) var mill_count: int = 3
@export_range(0, 99, 1) var topdeck_count: int = 3
@export_range(0, 99, 1) var armor_per_banished_card: int = 2


func get_target_type_for_mode(_context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return default_target_type


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.NORMAL


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return []

	return user.preview_discard_after_mill(mill_count)


func get_ordered_discard_choice_max_count(_context: Dictionary = {}) -> int:
	return topdeck_count


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择至多 %d 张牌按顺序置于牌库顶" % topdeck_count


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return

	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		_play_momentum(controller, user)
		return

	var milled := user.mill_cards(mill_count)
	if not milled.is_empty():
		controller._emit_log("%s 磨掉 %d 张牌。" % [user.get_display_name(), milled.size()])

	var selected_cards: Array[CardData] = []
	var raw_selected = context.get("ordered_discard_cards", [])
	if raw_selected is Array:
		for card in raw_selected:
			if card is CardData:
				selected_cards.append(card)

	var moved := user.move_discard_cards_to_draw_top(selected_cards, topdeck_count)
	if not moved.is_empty():
		var names := PackedStringArray()
		for card in moved:
			names.append(card.card_name)
		controller._emit_log("%s 将 %s 置于牌库顶。" % [user.get_display_name(), "、".join(names)])


func _play_momentum(controller: BattleController, user: BattleUnitState) -> void:
	var banished_count := user.discard_pile.size()
	if banished_count <= 0:
		return

	var banished := user.banish_discard_cards(banished_count)
	var armor_amount := banished.size() * armor_per_banished_card
	if armor_amount <= 0:
		return

	var armor := ArmorStatus.new()
	armor.stacks = armor_amount
	user.add_status(armor)
	controller._emit_log("%s 放逐弃牌堆中的 %d 张牌，获得 %d 点护甲。" % [
		user.get_display_name(),
		banished.size(),
		armor_amount,
	])
