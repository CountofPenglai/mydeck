extends RefCounted
class_name AdventureBattleDangerService

const MutationPool := preload("res://scripts/adventure/adventure_battle_danger_mutation_pool.gd")


static func create_snapshot(danger: int, chapter: int, enemies: Array[EnemyState], seed: int) -> Dictionary:
	var bonus := AdventureDangerService.bonus_percent(danger)
	var snapshot := {
		"danger": danger,
		"bonus_percent": bonus,
		"seed": seed,
		"chapter": chapter,
		"initial_assignments": [],
		"reinforcement_assignments": [],
		"spawn_serial": 0,
	}
	if bonus <= 0 or enemies.is_empty():
		return snapshot
	var slots: Array[int] = []
	if danger < 12:
		var highest := -1
		for slot in range(enemies.size()):
			var state := enemies[slot]
			if state == null:
				continue
			var health := state.get_max_health_with_danger(bonus)
			if health > highest:
				highest = health
				slots = [slot]
			elif health == highest:
				slots.append(slot)
		if slots.size() > 1:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			slots = [slots[rng.randi_range(0, slots.size() - 1)]]
	else:
		for slot in range(enemies.size()):
			if enemies[slot] != null:
				slots.append(slot)
	var assignments: Array[Dictionary] = []
	for slot in slots:
		var assignment := _assignment(chapter, enemies[slot], seed, slot)
		if assignment.is_empty():
			push_error("Danger mutation pool has no valid candidate for initial enemy slot %d." % slot)
			continue
		assignment["slot"] = slot
		assignments.append(assignment)
	snapshot["initial_assignments"] = assignments
	return snapshot


static func apply_enemy(state: EnemyState, snapshot: Dictionary, slot: int, reinforcement: bool = false) -> void:
	if state == null:
		return
	var bonus := int(snapshot.get("bonus_percent", 0))
	var seed := int(snapshot.get("seed", 0))
	if state.danger_snapshot_seed == seed and state.danger_bonus_percent == bonus:
		return
	state.danger_snapshot_seed = seed
	state.danger_bonus_percent = bonus
	state.danger_damage_bonus_percent = bonus
	state.danger_mutation_fields.clear()
	if bonus <= 0:
		return
	var assignment := _find_assignment(snapshot.get("initial_assignments", []) as Array, slot)
	if reinforcement:
		if int(snapshot.get("danger", 0)) < 12:
			return
		var serial := int(snapshot.get("spawn_serial", 0))
		snapshot["spawn_serial"] = serial + 1
		var history: Array = snapshot.get("reinforcement_assignments", []) as Array
		assignment = _find_reinforcement_assignment(history, serial)
		if assignment.is_empty():
			assignment = _assignment(int(snapshot.get("chapter", 1)), state, seed, serial + 100000)
			if assignment.is_empty():
				push_error("Danger mutation pool has no valid candidate for reinforcement %d." % serial)
				return
			assignment["serial"] = serial
			history.append(assignment.duplicate(true))
			snapshot["reinforcement_assignments"] = history
	if assignment.is_empty():
		return
	var field_id := str(assignment.get("field_id", ""))
	if not field_id.is_empty():
		state.danger_mutation_fields.append(field_id)


static func scale_damage(amount: int, source: BattleUnitState, metadata: Dictionary = {}) -> int:
	if amount <= 0 or source == null or source.enemy_state == null or source == metadata.get("target"):
		return amount
	if bool(metadata.get("environmental", false)) or bool(metadata.get("life_loss", false)) or bool(metadata.get("danger_scaled", false)):
		return amount
	var bonus := source.enemy_state.danger_damage_bonus_percent
	if bonus <= 0:
		return amount
	return maxi(1, roundi(float(amount) * float(100 + bonus) / 100.0))


static func transfer_form(old_state: EnemyState, new_state: EnemyState) -> void:
	if old_state == null or new_state == null:
		return
	new_state.danger_snapshot_seed = old_state.danger_snapshot_seed
	new_state.danger_bonus_percent = old_state.danger_bonus_percent
	new_state.danger_damage_bonus_percent = old_state.danger_damage_bonus_percent
	new_state.danger_mutation_fields = old_state.danger_mutation_fields.duplicate()


static func _assignment(chapter: int, state: EnemyState, seed: int, index: int) -> Dictionary:
	var candidates := MutationPool.candidates(chapter, state)
	if candidates.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(seed, "danger_mutation", index)
	var total := 0
	for field_id in candidates:
		total += MutationPool.weight(chapter, field_id)
	var needle := rng.randi_range(1, total)
	for field_id in candidates:
		needle -= MutationPool.weight(chapter, field_id)
		if needle <= 0:
			return {"field_id": field_id}
	return {"field_id": candidates.back()}


static func _find_assignment(assignments: Array, slot: int) -> Dictionary:
	for entry in assignments:
		if entry is Dictionary and int((entry as Dictionary).get("slot", -1)) == slot:
			return (entry as Dictionary).duplicate(true)
	return {}


static func _find_reinforcement_assignment(assignments: Array, serial: int) -> Dictionary:
	for entry in assignments:
		if entry is Dictionary and int((entry as Dictionary).get("serial", -1)) == serial:
			return (entry as Dictionary).duplicate(true)
	return {}
