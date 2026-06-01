extends RefCounted
class_name EnemyEnums

enum EnemyRank {
	MINION,
	NORMAL,
	ELITE,
	BOSS,
}

static func rank_label(value: int) -> String:
	match value:
		EnemyRank.MINION:
			return "爪牙"
		EnemyRank.NORMAL:
			return "普通"
		EnemyRank.ELITE:
			return "精英"
		EnemyRank.BOSS:
			return "首领"
		_:
			return "未知"
