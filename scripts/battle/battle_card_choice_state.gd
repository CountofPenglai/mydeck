extends RefCounted
class_name BattleCardChoiceState

const SELECTION_SERVICE := preload("res://scripts/battle/battle_selection_service.gd")

var owner: BattleUnitState
var source_card: CardData
var min_count: int = 0
var max_count: int = 0
var prompt: String = ""
var continuation: Callable
var zones: PackedStringArray = PackedStringArray(["hand"])
var card_filter: Callable
var cancel_submits_empty := false


static func create(
	new_owner: BattleUnitState,
	new_source_card: CardData,
	new_min_count: int,
	new_max_count: int,
	new_prompt: String,
	new_continuation: Callable
):
	var state = new()
	state.owner = new_owner
	state.source_card = new_source_card
	state.min_count = new_min_count
	state.max_count = new_max_count
	state.prompt = new_prompt
	state.continuation = new_continuation
	return state


func get_live_cards() -> Array[CardData]:
	var live_cards := SELECTION_SERVICE.new().get_cards(owner, zones)
	live_cards.erase(source_card)
	if card_filter.is_valid():
		live_cards = live_cards.filter(func(card: CardData) -> bool: return card_filter.call(card))
	return live_cards
