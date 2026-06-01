extends RefCounted
class_name CardEnums

enum Rarity {
	COMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

enum CardClass {
	NEUTRAL,
	WARRIOR,
	MAGE,
	RANGER,
	DRUID,
	WARLOCK,
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
