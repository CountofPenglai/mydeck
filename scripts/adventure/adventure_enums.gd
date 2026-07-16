extends RefCounted
class_name AdventureEnums

enum RoomType {
	START,
	NORMAL_BATTLE,
	ELITE_BATTLE,
	BOSS_BATTLE,
	SHELTER,
	SHOP,
	EVENT,
}

enum ShelterType {
	OUTPOST,
	SANCTUARY,
	ADVENTURER_CAMP,
}

enum EncounterTier {
	WEAK,
	MIXED,
	STRONG,
	ELITE,
	BOSS,
	AMBUSH,
}

enum TransactionType {
	NONE,
	MOVE,
	BATTLE,
	REWARD,
	EVENT,
	SHOP,
	CAMP,
}


static func room_type_label(value: int) -> String:
	match value:
		RoomType.START:
			return "起点"
		RoomType.NORMAL_BATTLE:
			return "普通战斗"
		RoomType.ELITE_BATTLE:
			return "精英战斗"
		RoomType.BOSS_BATTLE:
			return "首领战斗"
		RoomType.SHELTER:
			return "避难所"
		RoomType.SHOP:
			return "商店"
		RoomType.EVENT:
			return "事件"
		_:
			return "未知房间"


static func room_symbol(value: int) -> String:
	match value:
		RoomType.START:
			return "旗"
		RoomType.NORMAL_BATTLE:
			return "战"
		RoomType.ELITE_BATTLE:
			return "精"
		RoomType.BOSS_BATTLE:
			return "王"
		RoomType.SHELTER:
			return "营"
		RoomType.SHOP:
			return "店"
		RoomType.EVENT:
			return "?"
		_:
			return "·"


static func encounter_tier_label(value: int) -> String:
	match value:
		EncounterTier.WEAK:
			return "弱敌池"
		EncounterTier.MIXED:
			return "混合敌池"
		EncounterTier.STRONG:
			return "强敌池"
		EncounterTier.ELITE:
			return "精英"
		EncounterTier.BOSS:
			return "首领"
		EncounterTier.AMBUSH:
			return "伏击"
		_:
			return "未知"
