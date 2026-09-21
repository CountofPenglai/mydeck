extends RefCounted
class_name AdventureBattleDangerMutationPool

const CHAPTER_ONE_WEIGHTS := {
	"appendage": 3,
	"mud_lung": 3,
	"rock_scale": 2,
	"night_veil": 1,
	"beast_heart": 1,
}
const CHAPTER_TWO_WEIGHTS := {
	"rock_scale": 3,
	"scorch_throat": 3,
	"empty_eye": 2,
	"enlightenment": 1,
	"irradiation": 1,
}
const WAVE_ARCHETYPES := [
	"unclean_one", "high_priest", "abyss_scale", "standard_bearer", "blood_construct",
]


static func candidates(chapter: int, state: EnemyState) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.enemy_data == null:
		return result
	var archetype := str(state.enemy_data.archetype_id)
	var native := state.enemy_data.permanent_distortion_fields
	var source: Dictionary = CHAPTER_ONE_WEIGHTS if chapter == 1 else CHAPTER_TWO_WEIGHTS
	for field_value in source:
		var field_id := str(field_value)
		if native.has(field_id) or not _is_applicable(chapter, archetype, state.enemy_data.unit_tags, field_id):
			continue
		result.append(field_id)
	return result


static func weight(chapter: int, field_id: String) -> int:
	var source: Dictionary = CHAPTER_ONE_WEIGHTS if chapter == 1 else CHAPTER_TWO_WEIGHTS
	return int(source.get(field_id, 0))


static func _is_applicable(chapter: int, archetype: String, tags: PackedStringArray, field_id: String) -> bool:
	if chapter == 1:
		if field_id == "beast_heart":
			return WAVE_ARCHETYPES.has(archetype)
		return field_id != "night_veil" or not tags.has("support")
	if field_id == "irradiation":
		return tags.has("aberration")
	if field_id == "enlightenment":
		return WAVE_ARCHETYPES.has(archetype)
	if tags.has("statue"):
		return field_id == "empty_eye"
	return true
