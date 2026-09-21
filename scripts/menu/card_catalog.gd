extends Resource
class_name CardCatalog

const RARITY_ORDER := [CardEnums.Rarity.BASIC, CardEnums.Rarity.COMMON, CardEnums.Rarity.RARE, CardEnums.Rarity.EPIC, CardEnums.Rarity.LEGENDARY]

@export var cards: Array[CardData] = []


func query(class_filter: int = -1, rarity_filter: int = -1, search_text: String = "") -> Array[CardData]:
	var result: Array[CardData] = []
	var seen := {}
	var search := search_text.strip_edges().to_lower()
	for card in cards:
		if card == null:
			continue
		var key := card.resource_path if not card.resource_path.is_empty() else str(card.get_instance_id())
		if seen.has(key):
			continue
		seen[key] = true
		if class_filter >= 0:
			var matches := card.allowed_classes.has(class_filter) if not card.allowed_classes.is_empty() else card.card_class == class_filter
			if not matches:
				continue
		if rarity_filter >= 0 and card.rarity != rarity_filter:
			continue
		if not search.is_empty() and not card.card_name.to_lower().contains(search) and not card.inverted_name.to_lower().contains(search):
			continue
		result.append(card)
	result.sort_custom(func(a: CardData, b: CardData) -> bool:
		var rank_a := RARITY_ORDER.find(a.rarity)
		var rank_b := RARITY_ORDER.find(b.rarity)
		return rank_a < rank_b if rank_a != rank_b else a.card_name.naturalnocasecmp_to(b.card_name) < 0
	)
	return result
