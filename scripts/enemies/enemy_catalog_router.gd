extends RefCounted
class_name EnemyCatalogRouter

const CHAPTER_ONE := 1
const CHAPTER_TWO := 2


static func chapter_for_floor(floor_index: int) -> int:
	return CHAPTER_TWO if floor_index >= 1 else CHAPTER_ONE


static func draw_encounter(chapter: int, tier: int, seed: int, remaining_ids: Array, last_id: String = "") -> Dictionary:
	if chapter == CHAPTER_TWO:
		return ChapterTwoEnemyCatalog.draw_encounter(tier, seed, remaining_ids, last_id)
	return ChapterOneEnemyCatalog.draw_encounter(tier, seed, remaining_ids, last_id)


static func pick_encounter(chapter: int, tier: int, seed: int, last_id: String = "") -> Dictionary:
	if chapter == CHAPTER_TWO:
		return ChapterTwoEnemyCatalog.pick_encounter(tier, seed, last_id)
	return ChapterOneEnemyCatalog.pick_encounter(tier, seed, last_id)


static func create_enemy(chapter: int, archetype: StringName, seed: int = -1) -> EnemyState:
	if chapter == CHAPTER_TWO:
		return ChapterTwoEnemyCatalog.create_enemy(archetype, seed)
	return ChapterOneEnemyCatalog.create_enemy(archetype, seed)
