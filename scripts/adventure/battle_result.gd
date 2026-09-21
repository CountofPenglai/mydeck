extends Resource
class_name BattleResult

@export var victory: bool = false
@export var battle_id: String = ""
@export var encounter_tier: int = AdventureEnums.EncounterTier.WEAK
@export var hero_health: Dictionary = {}
@export var hero_ranger_elements: Dictionary = {}
@export var downed_hero_ids: PackedStringArray = []


static func from_controller(controller: BattleController, won: bool) -> BattleResult:
	var result := BattleResult.new()
	result.victory = won
	if controller == null:
		return result
	for unit in controller.player_units:
		if unit == null or unit.character_state == null:
			continue
		var state := unit.character_state
		var hero_id := state.adventure_character_id
		if hero_id.is_empty():
			hero_id = state.get_character_name()
		result.hero_health[hero_id] = state.current_health
		result.hero_ranger_elements[hero_id] = state.ranger_element_inventory.duplicate(true)
		if not unit.is_alive():
			result.downed_hero_ids.append(hero_id)
	return result
