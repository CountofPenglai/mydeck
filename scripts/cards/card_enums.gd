extends RefCounted
class_name CardEnums

enum Rarity {
	COMMON,
	RARE,
	EPIC,
	LEGENDARY,
	BASIC,
}

enum CardClass {
	NEUTRAL,
	WARRIOR,
	MAGE,
	RANGER,
	DRUID,
	WARLOCK,
}

enum CardType {
	ATTACK,
	SKILL,
	ENCHANTMENT,
	CURSE,
}

enum CardTag {
	PHYSICAL = 1,
	MAGICAL = 2,
}

enum ElementTag {
	FIRE = 1,
	WATER = 2,
	EARTH = 4,
	AIR = 8,
}

enum DamageType {
	STRENGTH,
	AGILITY,
	INTELLIGENCE,
	WEAPON,
}

enum TargetType {
	NONE,
	SINGLE,
	MULTI,
	AREA,
	SELF,
	ALL,
}

enum PlayTiming {
	NORMAL,
	BONUS,
}

enum CardPlayMode {
	NORMAL,
	MOMENTUM,
	COMBO,
}

enum DruidOrientation {
	UPRIGHT,
	INVERTED,
}

enum CardZone {
	NONE,
	HAND,
	DRAW,
	DISCARD,
	EXILE,
	MANA,
	ENCHANT,
}

enum ActionCategory {
	MOVE,
	ATTACK_CARD,
	SKILL_CARD,
	ENCHANTMENT_CARD,
	CURSE_CARD,
}


static func action_category_for_card(card_type: int) -> int:
	match card_type:
		CardType.ATTACK:
			return ActionCategory.ATTACK_CARD
		CardType.ENCHANTMENT:
			return ActionCategory.ENCHANTMENT_CARD
		CardType.CURSE:
			return ActionCategory.CURSE_CARD
		_:
			return ActionCategory.SKILL_CARD


static func action_category_label(value: int) -> String:
	match value:
		ActionCategory.MOVE:
			return "移动"
		ActionCategory.ATTACK_CARD:
			return "攻击牌"
		ActionCategory.SKILL_CARD:
			return "技能牌"
		ActionCategory.ENCHANTMENT_CARD:
			return "附魔牌"
		ActionCategory.CURSE_CARD:
			return "诅咒牌"
		_:
			return "未知行动"

static func rarity_label(value: int) -> String:
	match value:
		Rarity.COMMON:
			return "普通"
		Rarity.RARE:
			return "稀有"
		Rarity.EPIC:
			return "史诗"
		Rarity.LEGENDARY:
			return "传说"
		Rarity.BASIC:
			return "基础"
		_:
			return "未知"


static func class_label(value: int) -> String:
	match value:
		CardClass.NEUTRAL:
			return "中立"
		CardClass.WARRIOR:
			return "战士"
		CardClass.MAGE:
			return "法师"
		CardClass.RANGER:
			return "游侠"
		CardClass.DRUID:
			return "德鲁伊"
		CardClass.WARLOCK:
			return "术士"
		_:
			return "未知"


static func card_type_label(value: int) -> String:
	match value:
		CardType.ATTACK:
			return "攻击"
		CardType.SKILL:
			return "技能"
		CardType.ENCHANTMENT:
			return "附魔"
		CardType.CURSE:
			return "诅咒"
		_:
			return "未知"


static func damage_type_label(value: int) -> String:
	match value:
		DamageType.STRENGTH:
			return "力量"
		DamageType.AGILITY:
			return "敏捷"
		DamageType.INTELLIGENCE:
			return "智力"
		DamageType.WEAPON:
			return "武器"
		_:
			return "未知"


static func target_label(value: int) -> String:
	match value:
		TargetType.NONE:
			return "无需目标"
		TargetType.SINGLE:
			return "单体"
		TargetType.MULTI:
			return "多目标"
		TargetType.AREA:
			return "指定范围"
		TargetType.SELF:
			return "自身"
		TargetType.ALL:
			return "全体"
		_:
			return "未知"


static func action_label(value: int) -> String:
	match value:
		TargetType.NONE, TargetType.SELF, TargetType.ALL:
			return "打出"
		TargetType.SINGLE:
			return "选择目标"
		TargetType.MULTI:
			return "选择多个目标"
		TargetType.AREA:
			return "选择范围"
		_:
			return "打出"


static func play_timing_label(value: int) -> String:
	match value:
		PlayTiming.NORMAL:
			return "标准"
		PlayTiming.BONUS:
			return "附赠"
		_:
			return "未知"


static func play_mode_label(value: int) -> String:
	match value:
		CardPlayMode.NORMAL:
			return "普通"
		CardPlayMode.MOMENTUM:
			return "余势"
		CardPlayMode.COMBO:
			return "连击"
		_:
			return "未知"


static func druid_orientation_label(value: int) -> String:
	match value:
		DruidOrientation.UPRIGHT:
			return "正位"
		DruidOrientation.INVERTED:
			return "逆位"
		_:
			return "未知"
