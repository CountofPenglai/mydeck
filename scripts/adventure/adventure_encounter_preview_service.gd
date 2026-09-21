extends RefCounted
class_name AdventureEncounterPreviewService

static func describe(run: PartyRunState, room: AdventureRoomState) -> Dictionary:
	if run == null or run.floor_state == null or room == null or not room.content_revealed:
		return {}
	var payload := _locked_payload(run, room)
	var locked := not payload.is_empty()
	var predicted_danger := int(payload.get("danger_snapshot", {}).get("danger", run.floor_state.danger)) if locked else run.floor_state.danger + (0 if room.visited else 1)
	if not locked:
		var dangerous_event := room.room_type == AdventureEnums.RoomType.EVENT \
			and bool(AdventureEventVariantService.resolve(room.content_id, predicted_danger).get("auto_battle", false))
		var fixed := AdventureEncounterContent.get_encounter(room, dangerous_event)
		if fixed.is_empty():
			return {}
		payload = _preview_payload(run, fixed, predicted_danger)
	var scenario := AdventureBattleScenarioBuilder.build(run, payload)
	if scenario == null:
		return {}
	var snapshot: Dictionary = payload.get("danger_snapshot", {}) as Dictionary
	var assignments: Array = snapshot.get("initial_assignments", []) as Array
	var enemies: Array[Dictionary] = []
	for index in range(scenario.enemies.size()):
		var enemy := scenario.enemies[index] as EnemyState
		if enemy == null:
			continue
		var fields := PackedStringArray()
		for assignment in assignments:
			if assignment is Dictionary and int((assignment as Dictionary).get("slot", -1)) == index:
				fields.append(DistortionCatalog.get_display_name(str((assignment as Dictionary).get("field_id", ""))))
		enemies.append({
			"name": enemy.get_enemy_name(),
			"max_health": enemy.get_max_health_with_danger(int(snapshot.get("bonus_percent", 0))),
			"damage_bonus_percent": int(snapshot.get("bonus_percent", 0)),
			"mutations": fields,
		})
	var label := "本场锁定危险 %d" % predicted_danger if locked else ("预计进入时危险 %d（首次探索 +1）" % predicted_danger if not room.visited else "预计进入时危险 %d" % predicted_danger)
	if room.completed:
		label += "；该固定遭遇已完成，无需再战。"
	return {
		"text": label,
		"enemies": enemies,
		"danger_snapshot": snapshot.duplicate(true),
		"current_danger": run.floor_state.danger,
		"predicted_danger": predicted_danger,
		"damage_bonus_percent": int(snapshot.get("bonus_percent", 0)),
		"locked": locked,
	}

static func _locked_payload(run: PartyRunState, room: AdventureRoomState) -> Dictionary:
	if run.pending_transaction != null and run.pending_transaction.transaction_type == AdventureEnums.TransactionType.BATTLE:
		var payload: Dictionary = run.pending_transaction.payload
		if str(payload.get("room_id", "")) == room.room_id:
			return payload.duplicate(true)
	return {}

static func _preview_payload(run: PartyRunState, encounter: Dictionary, danger: int) -> Dictionary:
	var seed := int(encounter.get("seed", run.run_seed))
	var tier := int(encounter.get("tier", AdventureEnums.EncounterTier.WEAK))
	var chapter := EnemyCatalogRouter.chapter_for_floor(run.floor_index)
	var archetypes: Array = encounter.get("enemies", []) as Array
	var states: Array[EnemyState] = []
	for index in range(archetypes.size()):
		var state := EnemyCatalogRouter.create_enemy(chapter, StringName(archetypes[index]), AdventureMapGenerator.derive_seed(seed, "enemy_deck", index))
		if state != null:
			state.max_health_percent = run.enemy_health_percent
			states.append(state)
	return {"room_id": "", "encounter_tier": tier, "enemy_chapter": chapter, "enemy_archetypes": archetypes.duplicate(), "battle_seed": seed, "enemy_health_percent": run.enemy_health_percent, "danger_snapshot": AdventureBattleDangerService.create_snapshot(danger, chapter, states, AdventureMapGenerator.derive_seed(seed, "danger", 0))}
