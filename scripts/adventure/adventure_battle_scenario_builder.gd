extends RefCounted
class_name AdventureBattleScenarioBuilder

## Builds battle-local state from the already persisted encounter payload.
static func build(run: PartyRunState, payload: Dictionary) -> BattleScenario:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		return null
	var scenario := template.duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	for hero in run.get_active_party():
		scenario.players.append(hero)
	scenario.enemies.clear()
	var tier := int(payload.get("encounter_tier", AdventureEnums.EncounterTier.WEAK))
	var archetypes: Array = payload.get("enemy_archetypes", []) as Array
	var fallback_chapter := 1 if not archetypes.is_empty() else EnemyCatalogRouter.chapter_for_floor(run.floor_index)
	var enemy_chapter := int(payload.get("enemy_chapter", fallback_chapter))
	if archetypes.is_empty():
		var encounter := EnemyCatalogRouter.pick_encounter(enemy_chapter, tier, int(payload.get("battle_seed", run.run_seed)))
		archetypes = encounter.get("enemies", []) as Array
	var birth_index := 0
	var enemy_health_percent := clampi(
		int(payload.get("enemy_health_percent", run.enemy_health_percent)), 1, 1000
	)
	for archetype in archetypes:
		var enemy_seed := AdventureMapGenerator.derive_seed(int(payload.get("battle_seed", run.run_seed)), "enemy_deck", birth_index)
		var enemy := EnemyCatalogRouter.create_enemy(enemy_chapter, StringName(archetype), enemy_seed)
		if enemy != null:
			enemy.max_health_percent = enemy_health_percent
			enemy.current_health = enemy.get_max_health()
			scenario.enemies.append(enemy)
		birth_index += 1
	scenario.seed = int(payload.get("battle_seed", run.run_seed))
	scenario.danger_snapshot = (payload.get("danger_snapshot", {}) as Dictionary).duplicate(true)
	scenario.generate_battlefield_features = bool(payload.get("generate_battlefield_features", true))
	scenario.feature_chapter = enemy_chapter
	scenario.feature_encounter_tier = tier
	scenario.feature_seed = int(payload.get("battlefield_seed", scenario.seed))
	scenario.force_abyss_features = bool(payload.get("force_abyss_features", false))
	if scenario.battle_config != null:
		scenario.battle_config = scenario.battle_config.duplicate(true) as BattleConfig
		scenario.battle_config.starting_hand_size += int(payload.get("starting_hand_bonus", 0))
	return scenario
