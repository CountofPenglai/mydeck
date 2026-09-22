extends RefCounted
class_name BattleSelectionService


const ALLOWED_ZONES := ["hand", "draw", "discard", "mana"]


func get_cards(owner: BattleUnitState, zones: PackedStringArray) -> Array[CardData]:
	var cards: Array[CardData] = []
	if owner == null:
		return cards
	for zone in zones:
		match zone:
			"hand": cards.append_array(owner.hand)
			"draw": cards.append_array(owner.draw_pile)
			"discard": cards.append_array(owner.discard_pile)
			"mana": cards.append_array(owner.mana_zone)
	return cards


func are_zones_valid(zones: PackedStringArray) -> bool:
	for zone in zones:
		if not ALLOWED_ZONES.has(zone):
			return false
	return true


func validate(
	owner: BattleUnitState,
	selected: Array[CardData],
	zones: PackedStringArray,
	minimum: int,
	maximum: int,
	excluded: CardData = null
) -> bool:
	if owner == null or minimum < 0 or maximum < minimum:
		return false
	if not are_zones_valid(zones):
		return false
	var live := get_cards(owner, zones)
	var seen := {}
	for card in selected:
		if card == null or card == excluded or not live.has(card) or seen.has(card):
			return false
		seen[card] = true
	return selected.size() >= minimum and selected.size() <= maximum
