extends RefCounted
class_name DistortionBattleState

var permanent_fields: PackedStringArray = []
var field_source_counts: Dictionary = {}
var manifested_cards: Array[CardData] = []
var decay_snapshot: Array[CardData] = []
var pending_manual_manifest: bool = false
var selected_manifest_cards: Array[CardData] = []
var turn_flags: Dictionary = {}
var round_flags: Dictionary = {}
var battle_flags: Dictionary = {}
var lashing_damage_penalty: int = 0
var lashing_range_bonus: int = 0
var bloodseeking_ready: bool = false


func reset_for_battle(character: CharacterState = null) -> void:
	permanent_fields.clear()
	if character != null:
		permanent_fields = character.selected_distortion_fields.duplicate()
	field_source_counts.clear()
	manifested_cards.clear()
	decay_snapshot.clear()
	pending_manual_manifest = false
	selected_manifest_cards.clear()
	turn_flags.clear()
	round_flags.clear()
	battle_flags.clear()
	lashing_damage_penalty = 0
	lashing_range_bonus = 0
	bloodseeking_ready = false


func start_turn() -> void:
	decay_snapshot.assign(manifested_cards.duplicate())
	pending_manual_manifest = false
	selected_manifest_cards.clear()
	turn_flags.clear()
	lashing_damage_penalty = 0
	lashing_range_bonus = 0
	bloodseeking_ready = false


func register_manifestation(card: CardData) -> void:
	if card == null or not card.has_mutation_fields():
		return
	if not manifested_cards.has(card):
		manifested_cards.append(card)
	for field_id in card.mutation_fields:
		field_source_counts[field_id] = int(field_source_counts.get(field_id, 0)) + 1


func unregister_manifestation(card: CardData) -> void:
	if card == null:
		return
	manifested_cards.erase(card)
	for field_id in card.mutation_fields:
		var remaining := maxi(0, int(field_source_counts.get(field_id, 0)) - 1)
		if remaining <= 0:
			field_source_counts.erase(field_id)
		else:
			field_source_counts[field_id] = remaining


func has_field(field_id: String) -> bool:
	return permanent_fields.has(field_id) or int(field_source_counts.get(field_id, 0)) > 0


func get_active_fields() -> PackedStringArray:
	var result := permanent_fields.duplicate()
	for field_id in field_source_counts:
		var id := str(field_id)
		if int(field_source_counts[field_id]) > 0 and not result.has(id):
			result.append(id)
	return result


func get_source_count(field_id: String) -> int:
	return int(field_source_counts.get(field_id, 0)) + (1 if permanent_fields.has(field_id) else 0)


func card_adds_new_field(card: CardData) -> bool:
	if card == null or not card.has_mutation_fields():
		return false
	for field_id in card.mutation_fields:
		if not has_field(field_id):
			return true
	return false


func can_use_lashing() -> bool:
	return has_field("lashing") and not bool(turn_flags.get("lashing_used", false))


func apply_lashing(amount: int) -> bool:
	if not can_use_lashing() or amount < 1 or amount > 3:
		return false
	turn_flags["lashing_used"] = true
	lashing_damage_penalty = amount
	lashing_range_bonus = amount
	return true


func mark_round_flag(flag_id: String, round_number: int) -> void:
	round_flags[flag_id] = round_number


func was_round_flag_used(flag_id: String, round_number: int) -> bool:
	return int(round_flags.get(flag_id, -1)) == round_number


func snapshot() -> Dictionary:
	return {
		"permanent_fields": permanent_fields.duplicate(),
		"field_source_counts": field_source_counts.duplicate(true),
		"manifested_cards": manifested_cards.duplicate(),
		"decay_snapshot": decay_snapshot.duplicate(),
		"pending_manual_manifest": pending_manual_manifest,
		"selected_manifest_cards": selected_manifest_cards.duplicate(),
		"turn_flags": turn_flags.duplicate(true),
		"round_flags": round_flags.duplicate(true),
		"battle_flags": battle_flags.duplicate(true),
		"lashing_damage_penalty": lashing_damage_penalty,
		"lashing_range_bonus": lashing_range_bonus,
		"bloodseeking_ready": bloodseeking_ready,
	}


func restore(data: Dictionary) -> void:
	permanent_fields = PackedStringArray(data.get("permanent_fields", []))
	field_source_counts = (data.get("field_source_counts", {}) as Dictionary).duplicate(true)
	manifested_cards.assign(data.get("manifested_cards", []) as Array)
	decay_snapshot.assign(data.get("decay_snapshot", []) as Array)
	pending_manual_manifest = bool(data.get("pending_manual_manifest", false))
	selected_manifest_cards.assign(data.get("selected_manifest_cards", []) as Array)
	turn_flags = (data.get("turn_flags", {}) as Dictionary).duplicate(true)
	round_flags = (data.get("round_flags", {}) as Dictionary).duplicate(true)
	battle_flags = (data.get("battle_flags", {}) as Dictionary).duplicate(true)
	lashing_damage_penalty = int(data.get("lashing_damage_penalty", 0))
	lashing_range_bonus = int(data.get("lashing_range_bonus", 0))
	bloodseeking_ready = bool(data.get("bloodseeking_ready", false))
