extends RefCounted
class_name CurseCatalog

const ORDINARY_PATHS := [
	"res://resources/curses/blood.tres",
	"res://resources/curses/greed.tres",
	"res://resources/curses/cripple.tres",
	"res://resources/curses/disease.tres",
	"res://resources/curses/passing.tres",
	"res://resources/curses/possession.tres",
	"res://resources/curses/unrest.tres",
	"res://resources/curses/counterfeit.tres",
]
const BOSS_PATHS := [
	"res://resources/curses/universal_love.tres",
	"res://resources/curses/gluttony.tres",
	"res://resources/curses/offspring.tres",
	"res://resources/curses/preservation.tres",
	"res://resources/curses/unbound.tres",
	"res://resources/curses/gospel.tres",
]


static func load_definitions(include_boss: bool = true) -> Array[CurseDefinition]:
	var result: Array[CurseDefinition] = []
	var paths := ORDINARY_PATHS.duplicate()
	if include_boss:
		paths.append_array(BOSS_PATHS)
	for path in paths:
		var definition := load(path) as CurseDefinition
		if definition != null:
			result.append(definition)
	return result


static func get_rebirth_candidates(character: CharacterState) -> Array[CurseDefinition]:
	var result: Array[CurseDefinition] = []
	if character == null:
		return result
	for definition in load_definitions(false):
		var existing := character.get_curse(definition.curse_id)
		if existing == null or existing.depth < 3:
			result.append(definition)
	return result
