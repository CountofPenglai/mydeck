extends RefCounted
class_name EnemyTacticalCardCatalog


static func create_entry(card: CardData, max_copies: int = 1) -> EnemyCardPoolEntry:
	var entry := EnemyCardPoolEntry.new()
	entry.card = card
	entry.card_key = StringName(card.card_name) if card != null else StringName()
	entry.max_copies = max_copies
	entry.intent_ratings = _ratings_for(card)
	entry.base_score = entry.intent_ratings[0].base_score if not entry.intent_ratings.is_empty() else 0
	return entry


static func create_profile(preset: int) -> EnemyAIProfile:
	return EnemyAIProfile.create_preset(preset)


static func _ratings_for(card: CardData) -> Array[EnemyCardIntentRating]:
	if card == null:
		return []
	match card.card_name:
		"逼近啃咬": return [_rating(EnemyIntentCategory.Type.APPROACH, 12, 3, 0, 0, 0, 1), _rating(EnemyIntentCategory.Type.ATTACK, 9, 3), _rating(EnemyIntentCategory.Type.HARVEST, 10, 3)]
		"拖曳撕扯": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 4, 0, 0, 0, 0, 1), _rating(EnemyIntentCategory.Type.UTILITY, 8, 2, 0, 0, 0, 1), _rating(EnemyIntentCategory.Type.HARVEST, 8, 4)]
		"群猎": return [_rating(EnemyIntentCategory.Type.ATTACK, 11, 5), _rating(EnemyIntentCategory.Type.HARVEST, 10, 5)]
		"蜷缩硬皮": return [_rating(EnemyIntentCategory.Type.DEFEND, 10, 0, 5)]
		"污水喷吐": return [_rating(EnemyIntentCategory.Type.ATTACK, 8, 3), _rating(EnemyIntentCategory.Type.UTILITY, 9, 2, 0, 0, 0, 0, 0, 0, 2)]
		"潜泥": return [_rating(EnemyIntentCategory.Type.RETREAT, 12, 0, 3, 0, 0, 4), _rating(EnemyIntentCategory.Type.DEFEND, 8, 0, 3), _rating(EnemyIntentCategory.Type.APPROACH, 7, 0, 0, 0, 0, 4), _rating(EnemyIntentCategory.Type.UTILITY, 6, 0, 2, 0, 0, 3)]
		"护群嘶鸣": return [_rating(EnemyIntentCategory.Type.DEFEND, 11, 0, 4, 0, 1), _rating(EnemyIntentCategory.Type.UTILITY, 9, 0, 3, 0, 1, 0, 0, 0, 2)]
		"空目择食": return [_rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 0, 0, 1, 0, 0, 0, 4)]
		"鞭笞触腕": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 4, 0, 0, 0, 0, 2), _rating(EnemyIntentCategory.Type.UTILITY, 10, 2, 0, 0, 0, 0, 2), _rating(EnemyIntentCategory.Type.HARVEST, 8, 4)]
		"觅血口器": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 4, 0, 4), _rating(EnemyIntentCategory.Type.DEFEND, 9, 2, 0, 4), _rating(EnemyIntentCategory.Type.HARVEST, 11, 4, 0, 4)]
		"增生附肢": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 3), _rating(EnemyIntentCategory.Type.HARVEST, 8, 3)]
		"灼喉囊": return [_rating(EnemyIntentCategory.Type.ATTACK, 9, 4), _rating(EnemyIntentCategory.Type.UTILITY, 8, 2, 0, 0, 0, 0, 0, 0, 2)]
		"启明之瘤": return [_rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 0, 0, 1, 0, 0, 0, 5)]
		"披夜薄膜": return [_rating(EnemyIntentCategory.Type.HARVEST, 11, 6), _rating(EnemyIntentCategory.Type.ATTACK, 8, 5), _rating(EnemyIntentCategory.Type.UTILITY, 6, 2, 0, 0, 0, 0, 0, 0, 3)]
		"辐照腺体": return [_rating(EnemyIntentCategory.Type.CURSE, 12, 0, 0, 0, 0, 0, 1, 4), _rating(EnemyIntentCategory.Type.UTILITY, 8, 0, 0, 0, 0, 0, 0, 2, 3)]
		"奔踏畸足": return [_rating(EnemyIntentCategory.Type.ATTACK, 12, 6), _rating(EnemyIntentCategory.Type.HARVEST, 10, 6)]
		"列阵推进": return [_rating(EnemyIntentCategory.Type.APPROACH, 12, 4, 0, 0, 0, 2, 0, 0, 0, [], ["movement_buff"], [], 4), _rating(EnemyIntentCategory.Type.ATTACK, 9, 4), _rating(EnemyIntentCategory.Type.HARVEST, 10, 4)]
		"盾墙": return [_rating(EnemyIntentCategory.Type.DEFEND, 11, 0, 6)]
		"协同突刺": return [_rating(EnemyIntentCategory.Type.ATTACK, 12, 6), _rating(EnemyIntentCategory.Type.HARVEST, 11, 6)]
		"要塞齐射": return [_rating(EnemyIntentCategory.Type.CURSE, 10, 3, 0, 0, 0, 0, 0, 2), _rating(EnemyIntentCategory.Type.ATTACK, 9, 4), _rating(EnemyIntentCategory.Type.UTILITY, 7, 2, 0, 0, 0, 0, 0, 2)]
		"整队号令": return [_rating(EnemyIntentCategory.Type.DEFEND, 11, 0, 5, 0, 1), _rating(EnemyIntentCategory.Type.UTILITY, 10, 0, 3, 0, 1, 0, 0, 0, 3)]
		"强行军": return [_rating(EnemyIntentCategory.Type.UTILITY, 11, 0, 0, 0, 0, 2, 0, 0, 4, [], [], ["movement_buff"]), _rating(EnemyIntentCategory.Type.APPROACH, 10, 0, 0, 0, 0, 2, 0, 0, 2, [], [], ["movement_buff"]), _rating(EnemyIntentCategory.Type.RETREAT, 6, 0, 0, 0, 0, 2, 0, 0, 1, [], [], ["movement_buff"])]
		"刑罚令": return [_rating(EnemyIntentCategory.Type.HARVEST, 12, 6), _rating(EnemyIntentCategory.Type.ATTACK, 11, 5)]
		"公开戒备": return [_rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 2, 0, 0, 0, 0, 0, 5), _rating(EnemyIntentCategory.Type.DEFEND, 8, 0, 2)]
		"裂片·秘法弹": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 4), _rating(EnemyIntentCategory.Type.HARVEST, 8, 4)]
		"裂片·秘法护盾": return [_rating(EnemyIntentCategory.Type.DEFEND, 11, 0, 5)]
		"裂片·血咒": return [_rating(EnemyIntentCategory.Type.CURSE, 12, 3, 0, 0, 0, 0, 0, 2), _rating(EnemyIntentCategory.Type.ATTACK, 8, 3), _rating(EnemyIntentCategory.Type.UTILITY, 7, 2, 0, 0, 0, 0, 0, 2)]
		"裂片·黑暗交易": return [_rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 0, 0, 2, 0, 0, 0, 4)]
		"裂片·闪避步": return [_rating(EnemyIntentCategory.Type.RETREAT, 12, 0, 2, 0, 0, 2), _rating(EnemyIntentCategory.Type.DEFEND, 8, 0, 2)]
		"裂片·瞄准射击": return [_rating(EnemyIntentCategory.Type.ATTACK, 11, 5), _rating(EnemyIntentCategory.Type.HARVEST, 11, 5)]
		"猛击": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 5, 0, 0, 0, 0, 1), _rating(EnemyIntentCategory.Type.HARVEST, 9, 5)]
		"冲锋": return [_rating(EnemyIntentCategory.Type.APPROACH, 12, 4, 0, 0, 0, 3), _rating(EnemyIntentCategory.Type.ATTACK, 8, 4), _rating(EnemyIntentCategory.Type.HARVEST, 9, 4)]
		"防御架势": return [_rating(EnemyIntentCategory.Type.DEFEND, 12, 0, 6), _rating(EnemyIntentCategory.Type.UTILITY, 7, 0, 3, 0, 0, 0, 0, 0, 2)]
		"险步突袭": return [_rating(EnemyIntentCategory.Type.ATTACK, 10, 4), _rating(EnemyIntentCategory.Type.HARVEST, 9, 4)]
		"弩索牵引": return [_rating(EnemyIntentCategory.Type.ATTACK, 9, 4), _rating(EnemyIntentCategory.Type.UTILITY, 10, 2, 0, 0, 0, 1, 1), _rating(EnemyIntentCategory.Type.HARVEST, 8, 4)]
		"苍翠打击": return [_rating(EnemyIntentCategory.Type.ATTACK, 9, 4, 3), _rating(EnemyIntentCategory.Type.DEFEND, 8, 2, 4), _rating(EnemyIntentCategory.Type.HARVEST, 8, 4)]
		"月光":
			var defend := _rating(EnemyIntentCategory.Type.DEFEND, 10, 0, 0, 5)
			defend.target_preference = EnemyCardPoolEntry.TargetPreference.ALLY
			var utility := _rating(EnemyIntentCategory.Type.UTILITY, 9, 2, 0, 3)
			utility.target_preference = EnemyCardPoolEntry.TargetPreference.ALLY
			var attack := _rating(EnemyIntentCategory.Type.ATTACK, 8, 4)
			attack.target_preference = EnemyCardPoolEntry.TargetPreference.OPPONENT
			return [defend, utility, attack]
		"根系洞察": return [_rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 0, 0, 2, 0, 0, 0, 4)]
		"蓄翠化形": return [_rating(EnemyIntentCategory.Type.UTILITY, 11, 0, 0, 0, 2, 0, 0, 0, 5), _rating(EnemyIntentCategory.Type.DEFEND, 10, 0, 6)]
		"野性变形": return [_rating(EnemyIntentCategory.Type.UTILITY, 11, 0, 0, 0, 1, 0, 0, 0, 5, [], [], ["damage_buff"]), _rating(EnemyIntentCategory.Type.DEFEND, 9, 0, 4)]
		"鲜血之业": return [_rating(EnemyIntentCategory.Type.CURSE, 12, 8, 0, 4, 0, 0, 0, 3), _rating(EnemyIntentCategory.Type.ATTACK, 12, 8), _rating(EnemyIntentCategory.Type.HARVEST, 12, 8), _rating(EnemyIntentCategory.Type.DEFEND, 9, 3, 0, 4)]
		"兼爱之业": return [_rating(EnemyIntentCategory.Type.CURSE, 9, 0, 4, 0, 2, 0, 0, 2), _rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 4, 0, 2, 0, 0, 0, 4), _rating(EnemyIntentCategory.Type.DEFEND, 11, 0, 5)]
		"贪欲之业": return [_rating(EnemyIntentCategory.Type.CURSE, 10, 0, 0, 0, 3, 0, 0, 2), _rating(EnemyIntentCategory.Type.UTILITY, 12, 0, 0, 0, 3, 0, 0, 0, 5)]
		"跛行之业": return [_rating(EnemyIntentCategory.Type.CURSE, 9, 0, 0, 0, 0, 4, 1, 2), _rating(EnemyIntentCategory.Type.UTILITY, 10, 0, 0, 0, 0, 4, 1), _rating(EnemyIntentCategory.Type.RETREAT, 9, 0, 0, 0, 0, 4), _rating(EnemyIntentCategory.Type.APPROACH, 8, 0, 0, 0, 0, 4)]
		"痼病之业": return [_rating(EnemyIntentCategory.Type.CURSE, 12, 0, 0, 0, 0, 0, 1, 5), _rating(EnemyIntentCategory.Type.UTILITY, 8, 0, 0, 0, 0, 0, 1, 2)]
		_:
			return [_rating(EnemyIntentCategory.Type.UTILITY, 5, 0, 0, 0, 0, 0, 0, 0, 1)]


static func _rating(
	category: int,
	base_score: int,
	damage: int = 0,
	defense: int = 0,
	healing: int = 0,
	draw: int = 0,
	movement: int = 0,
	control: int = 0,
	curse: int = 0,
	utility: int = 0,
	required: Array = [],
	preferred: Array = [],
	provided: Array = [],
	combo_bonus: int = 0
) -> EnemyCardIntentRating:
	var rating := EnemyCardIntentRating.new()
	rating.category = category
	rating.base_score = base_score
	rating.damage_value = damage
	rating.defense_value = defense
	rating.healing_value = healing
	rating.draw_value = draw
	rating.movement_value = movement
	rating.control_value = control
	rating.curse_value = curse
	rating.utility_value = utility
	rating.required_tags = PackedStringArray(required)
	rating.preferred_tags = PackedStringArray(preferred)
	rating.provided_tags = PackedStringArray(provided)
	rating.combo_bonus = combo_bonus
	return rating
