extends RefCounted
class_name AdventureBattleSetupService

## Locks encounter identity, battlefield generation and danger before entering battle.
static func create_payload(run: PartyRunState, room: AdventureRoomState, tier: int, extra: Dictionary = {}) -> Dictionary:
	var payload := extra.duplicate(true)
	var cards_only := str(extra.get("reward_mode", "")) == "cards_only"
	var fixed := AdventureEncounterContent.get_encounter(room, cards_only)
	if not fixed.is_empty() and (room.is_combat_room() or cards_only):
		tier = int(fixed.get("tier", tier))
	else:
		fixed = {}
	var seed := int(fixed.get("seed", AdventureMapGenerator.derive_seed(run.run_seed, "encounter", room.room_id.hash() + run.floor_index * 1000)))
	var chapter := EnemyCatalogRouter.chapter_for_floor(run.floor_index)
	var encounter := fixed if not fixed.is_empty() else EnemyCatalogRouter.pick_encounter(chapter, tier, seed)
	payload.merge({
		"room_id": room.room_id,
		"encounter_tier": tier,
		"battle_seed": seed,
		"enemy_chapter": chapter,
		"encounter_id": str(encounter.get("id", "")),
		"enemy_archetypes": (encounter.get("enemies", []) as Array).duplicate(),
		"enemy_health_percent": run.enemy_health_percent,
		"starting_hand_bonus": 1 if bool(run.adventure_flags.get("tactical_rehearsal", false)) else 0,
		"battlefield_seed": AdventureMapGenerator.derive_seed(seed, "battlefield_layout", 0),
		"battlefield_generation_version": 1,
		"generate_battlefield_features": tier != AdventureEnums.EncounterTier.BOSS,
	}, true)
	payload["force_abyss_features"] = roll_chapter_one_abyss(run, chapter, tier, int(payload.battlefield_seed))
	run.adventure_flags.erase("tactical_rehearsal")
	var scenario := AdventureBattleScenarioBuilder.build(run, payload)
	if scenario != null:
		var danger := run.floor_state.danger if run.floor_state != null else 0
		var enemies: Array[EnemyState] = []
		for resource in scenario.enemies:
			if resource is EnemyState:
				enemies.append(resource)
		payload["danger_snapshot"] = AdventureBattleDangerService.create_snapshot(
			danger, chapter, enemies, AdventureMapGenerator.derive_seed(seed, "danger", 0)
		)
	return payload

static func roll_chapter_one_abyss(run: PartyRunState, chapter: int, tier: int, battlefield_seed: int) -> bool:
	if run == null or chapter != 1 \
			or (tier != AdventureEnums.EncounterTier.STRONG \
			and tier != AdventureEnums.EncounterTier.ELITE):
		return false
	const MISS_KEY := "chapter_1_battlefield_abyss_misses"
	var misses := int(run.adventure_flags.get(MISS_KEY, 0))
	var generated := misses >= 2
	if not generated:
		var rng := RandomNumberGenerator.new()
		rng.seed = AdventureMapGenerator.derive_seed(battlefield_seed, "abyss_roll", misses)
		var chance := 75 if tier == AdventureEnums.EncounterTier.ELITE else 50
		generated = rng.randi_range(1, 100) <= chance
	run.adventure_flags[MISS_KEY] = 0 if generated else misses + 1
	return generated
