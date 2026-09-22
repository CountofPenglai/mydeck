extends Resource
class_name BattleUnitState

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const RangerCombatState = preload("res://scripts/ranger/ranger_combat_state.gd")
const MageCombatState = preload("res://scripts/mage/mage_combat_state.gd")
const WarlockCombatState = preload("res://scripts/warlock/warlock_combat_state.gd")
const DruidCombatState = preload("res://scripts/druid/druid_combat_state.gd")
const BattleCurseSuppression = preload("res://scripts/curses/battle_curse_suppression.gd")
const DRUID_TRANSFORMED_DAMAGE_REDUCTION := 1

enum Faction {
	PLAYER,
	ENEMY,
}

var unit_id: int = -1
var turn_order_index: int = 0
var faction: int = Faction.PLAYER
var character_state: CharacterState
var enemy_state: EnemyState
var position: Vector2 = Vector2.ZERO
var cell: Vector2i = BattleHexGrid.INVALID_CELL
var token_radius: float = 24.0
var is_deployed: bool = false
var current_ap: int = 0
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exiled_pile: Array[CardData] = []
var mana_zone: Array[CardData] = []
var enchant_zone: Array[CardData] = []
var curse_zone: Array[CurseInstance] = []
var curse_wave: int = 0
var curse_runtime_states: Dictionary = {}
var curse_suppression := BattleCurseSuppression.new()
var distortion_state := DistortionBattleState.new()
var statuses: Array[StatusEffect] = []
var battle_action_flags := {}
var card_runtime_states: Dictionary = {}
var equipment_runtime_states: Dictionary = {}
var pending_next_card_damage_bonus: int = 0
var active_card_damage_bonuses: Dictionary = {}
var pending_next_attack_damage_bonus: int = 0
var active_attack_lifesteal_cards: Dictionary = {}
var turn_serial: int = 0
var block_lost_rounds: Dictionary = {}
var druid_transformed: bool = false
var druid_prepare_used: bool = false
var druid_state := DruidCombatState.new()
var druid_max_health_loss: int = 0
var battle_controller: BattleController
var ranger_state := RangerCombatState.new()
var mage_state := MageCombatState.new()
var warlock_state := WarlockCombatState.new()
var is_curse_proxy: bool = false
var curse_proxy_owner: BattleUnitState
var curse_proxy_name: String = ""
var curse_proxy_health: int = 0
var curse_proxy_max_health: int = 0
var curse_proxy_mirrors_damage: bool = false
var curse_proxy_hostile: bool = false
var curse_proxy_depth: int = 1
var threat_level_modifier: int = 0
var trap_limit_modifier: int = 0


func get_threat_level() -> int:
	var modifier := threat_level_modifier
	if is_ranger() and ranger_state.stealth_active:
		modifier -= 1
	return maxi(0, 1 + modifier)


func get_trap_limit() -> int:
	return maxi(0, (1 if is_ranger() else 0) + trap_limit_modifier)

func setup_player(id: int, state: CharacterState, default_token_radius: float) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.PLAYER
	character_state = state
	enemy_state = null
	token_radius = _resolve_token_radius(default_token_radius)
	is_deployed = false
	cell = BattleHexGrid.INVALID_CELL
	battle_action_flags.clear()
	card_runtime_states.clear()
	equipment_runtime_states.clear()
	pending_next_card_damage_bonus = 0
	active_card_damage_bonuses.clear()
	pending_next_attack_damage_bonus = 0
	active_attack_lifesteal_cards.clear()
	turn_serial = 0
	block_lost_rounds.clear()
	curse_wave = 0
	curse_runtime_states.clear()
	curse_suppression.clear()
	distortion_state.reset_for_battle(character_state)
	_reset_druid_state()
	ranger_state.reset_for_battle()
	mage_state.reset_for_battle()
	warlock_state.reset_for_battle()
	if character_state != null:
		ranger_state.load_element_inventory(character_state.ranger_element_inventory)


func setup_enemy(id: int, state: EnemyState, default_token_radius: float) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.ENEMY
	character_state = null
	enemy_state = state
	token_radius = _resolve_token_radius(default_token_radius)
	position = Vector2.ZERO
	cell = BattleHexGrid.INVALID_CELL
	is_deployed = true
	battle_action_flags.clear()
	card_runtime_states.clear()
	equipment_runtime_states.clear()
	pending_next_card_damage_bonus = 0
	active_card_damage_bonuses.clear()
	pending_next_attack_damage_bonus = 0
	active_attack_lifesteal_cards.clear()
	turn_serial = 0
	block_lost_rounds.clear()
	curse_wave = 0
	curse_runtime_states.clear()
	curse_suppression.clear()
	distortion_state.reset_for_battle()
	_reset_druid_state()
	ranger_state.reset_for_battle()
	mage_state.reset_for_battle()
	warlock_state.reset_for_battle()
	if enemy_state != null:
		enemy_state.reset_battle_runtime()
		if enemy_state.enemy_data != null:
			distortion_state.permanent_fields = enemy_state.enemy_data.permanent_distortion_fields.duplicate()
			distortion_state.danger_fields = enemy_state.danger_mutation_fields.duplicate()


func ensure_initialized(config: BattleConfig, rng: RandomNumberGenerator) -> void:
	if character_state != null:
		character_state.ensure_initialized()
		_prepare_deck(character_state.deck, rng, get_starting_hand_size(config))
		_setup_curses_from_character_state(rng)
	elif enemy_state != null:
		enemy_state.ensure_initialized()
		_prepare_deck(enemy_state.deck, rng, get_starting_hand_size(config))


func start_turn(config: BattleConfig) -> void:
	turn_serial += 1
	current_ap = get_max_ap(config)
	druid_prepare_used = false
	druid_max_health_loss = 0
	_reset_curse_turn_runtime()
	distortion_state.start_turn()
	ranger_state.start_turn(turn_serial)
	warlock_state.start_turn()


func record_block_lost(round_index: int = -1) -> void:
	var resolved_round := round_index
	if resolved_round < 0 and battle_controller != null:
		resolved_round = battle_controller.battle_round
	if resolved_round >= 0:
		block_lost_rounds[resolved_round] = true


func lost_block_in_previous_round(current_round: int = -1) -> bool:
	var resolved_round := current_round
	if resolved_round < 0 and battle_controller != null:
		resolved_round = battle_controller.battle_round
	return resolved_round > 0 and block_lost_rounds.has(resolved_round - 1)


func get_display_name() -> String:
	if is_curse_proxy:
		return curse_proxy_name
	if character_state != null:
		return character_state.get_character_name()
	if enemy_state != null:
		return enemy_state.get_enemy_name()

	return "未知单位"


func get_current_health() -> int:
	if is_curse_proxy:
		return curse_proxy_health
	if character_state != null:
		return character_state.current_health
	if enemy_state != null:
		return enemy_state.current_health

	return 0


func set_current_health(value: int) -> void:
	if is_curse_proxy:
		curse_proxy_health = clampi(value, 0, curse_proxy_max_health)
		return
	if character_state != null:
		character_state.current_health = clampi(value, 0, get_max_health())
	elif enemy_state != null:
		enemy_state.current_health = clampi(value, 0, get_max_health())


func apply_damage(amount: int) -> int:
	var requested := maxi(0, amount)
	var before := get_current_health()
	set_current_health(before - requested)
	return before - get_current_health()


func is_alive() -> bool:
	return get_current_health() > 0


func get_max_health() -> int:
	if is_curse_proxy:
		return curse_proxy_max_health
	var result := 0
	if character_state != null:
		result = character_state.get_max_health()
	elif enemy_state != null:
		result = enemy_state.get_max_health()
	if result <= 0:
		return 0
	return maxi(1, result - druid_max_health_loss)


func get_attack() -> int:
	if is_curse_proxy:
		return 3 + curse_proxy_depth
	var profile := build_strike_profile_object()
	var total := profile.primary_base_damage + profile.primary_damage_bonus
	if profile.add_offhand:
		total += profile.offhand_base_damage + profile.offhand_damage_bonus
	return total


func get_damage_bonus(context: Dictionary = {}) -> int:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	var result := 0
	if character_state != null:
		result = character_state.get_damage_bonus(merged_context)
	elif enemy_state != null:
		result = enemy_state.get_damage_bonus(merged_context)
	if battle_controller != null:
		result += battle_controller.get_surface_damage_bonus(self)
	result += get_curse_damage_bonus(merged_context)
	result -= distortion_state.lashing_damage_penalty
	if distortion_state.has_field("night_veil") and not bool(distortion_state.battle_flags.get("night_veil_broken", false)):
		result += _get_night_veil_damage_bonus(merged_context)
	return EnemyRuleDispatcher.modify_damage_bonus(self, result, merged_context) if enemy_state != null else result


func get_damage_reduction(context: Dictionary = {}) -> int:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	var result := get_status_damage_reduction(merged_context) + get_zone_damage_reduction(merged_context)
	if character_state != null:
		result += character_state.get_damage_reduction(merged_context)
	elif enemy_state != null:
		result += enemy_state.get_damage_reduction()
	if is_druid_transformed():
		result += DRUID_TRANSFORMED_DAMAGE_REDUCTION
	if battle_controller != null:
		result += battle_controller.get_surface_damage_reduction(self, merged_context)
	if enemy_state != null:
		result = EnemyRuleDispatcher.modify_damage_reduction(self, result, merged_context)
	return result


func get_character_class() -> int:
	if character_state != null and character_state.character_data != null:
		return character_state.character_data.character_class
	if enemy_state != null:
		return enemy_state.get_class_profile()

	return CardEnums.CardClass.NEUTRAL


func is_ranger() -> bool:
	return get_character_class() == CardEnums.CardClass.RANGER


func is_mage() -> bool:
	return get_character_class() == CardEnums.CardClass.MAGE


func is_mage_adventurer() -> bool:
	return character_state != null and is_mage()


func is_warlock() -> bool:
	return get_character_class() == CardEnums.CardClass.WARLOCK


func is_warlock_adventurer() -> bool:
	return character_state != null and is_warlock()


func setup_curse_proxy(id: int, owner: BattleUnitState, display_name: String, max_health: int, hostile: bool, mirrors_damage: bool, depth: int) -> void:
	unit_id = id
	turn_order_index = id
	is_curse_proxy = true
	curse_proxy_owner = owner
	curse_proxy_name = display_name
	curse_proxy_max_health = maxi(1, max_health)
	curse_proxy_health = curse_proxy_max_health
	curse_proxy_hostile = hostile
	curse_proxy_mirrors_damage = mirrors_damage
	curse_proxy_depth = maxi(1, depth)
	faction = 1 - owner.faction if hostile else owner.faction
	is_deployed = true
	battle_controller = owner.battle_controller


func enter_stealth() -> bool:
	if not is_ranger() or not is_alive() or ranger_state.stealth_active:
		return false
	ranger_state.stealth_active = true
	ranger_state.stealth_expires_turn_serial = turn_serial + 1
	ranger_state.refresh_blend_opportunity()
	_notify_all_equipment_runtime_effects("on_ranger_stealth_entered", [], _with_unit_context({
		"controller": battle_controller,
	}))
	return true


func leave_stealth() -> bool:
	if not ranger_state.stealth_active:
		return false
	ranger_state.stealth_active = false
	_notify_status_effects("on_ranger_stealth_ended", [], {
		"controller": battle_controller,
		"unit": self,
	})
	return true


func is_stealthed() -> bool:
	return ranger_state.stealth_active


func collect_ranger_element(element: int, amount: int = 1) -> int:
	if not is_ranger():
		return 0
	var added := ranger_state.add_element(element, amount)
	sync_ranger_element_inventory()
	return added


func sync_ranger_element_inventory() -> void:
	if character_state != null and is_ranger():
		character_state.ranger_element_inventory = ranger_state.element_inventory.duplicate(true)


func get_class_resource(resource_name: String) -> ResourcePoolState:
	if character_state != null:
		return character_state.get_class_resource(resource_name)

	return null


func get_class_resource_value(resource_name: String) -> int:
	if character_state != null:
		return character_state.get_class_resource_value(resource_name)

	return 0


func gain_class_resource(resource_name: String, amount: int) -> int:
	if character_state != null:
		return character_state.gain_class_resource(resource_name, amount)

	return 0


func consume_class_resource(resource_name: String, amount: int) -> bool:
	if character_state != null:
		return character_state.consume_class_resource(resource_name, amount)

	return false


func get_equipment_runtime_state(equipment: EquipmentData, create: bool = true) -> EquipmentRuntimeState:
	if equipment == null:
		return null
	var key := _equipment_runtime_key(equipment)
	var runtime: EquipmentRuntimeState = equipment_runtime_states.get(key) as EquipmentRuntimeState
	if runtime == null and create:
		runtime = EquipmentRuntimeState.new()
		runtime.equipment = equipment
		equipment_runtime_states[key] = runtime
	return runtime


func snapshot_equipment_runtime_states() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in equipment_runtime_states:
		var runtime := equipment_runtime_states.get(key) as EquipmentRuntimeState
		if runtime == null:
			continue
		snapshot[key] = {
			"equipment": runtime.equipment,
			"counters": runtime.counters.duplicate(true),
			"flags": runtime.flags.duplicate(true),
			"data": runtime.data.duplicate(true),
		}
	return snapshot


func restore_equipment_runtime_states(snapshot: Dictionary) -> void:
	equipment_runtime_states.clear()
	for key in snapshot:
		var data: Dictionary = snapshot.get(key, {}) as Dictionary
		var runtime := EquipmentRuntimeState.new()
		runtime.equipment = data.get("equipment") as EquipmentData
		runtime.counters = (data.get("counters", {}) as Dictionary).duplicate(true)
		runtime.flags = (data.get("flags", {}) as Dictionary).duplicate(true)
		runtime.data = (data.get("data", {}) as Dictionary).duplicate(true)
		equipment_runtime_states[key] = runtime


func get_equipment_effect_damage_bonus(context: Dictionary = {}) -> int:
	var total := 0
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			total += effect.get_damage_bonus(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context)
	return total


func get_equipment_effect_damage_reduction(context: Dictionary = {}) -> int:
	var total := 0
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			total += effect.get_damage_reduction(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context)
	return total


func equipment_preserves_block(context: Dictionary = {}) -> bool:
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null and effect.preserves_block_on_turn_start(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context):
			return true
	return false


func get_equipment_runtime_summary(context: Dictionary = {}) -> String:
	var parts := PackedStringArray()
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		var summary := effect.get_runtime_summary(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context)
		if not summary.is_empty() and not parts.has(summary):
			parts.append(summary)
	return " | ".join(parts)


func get_equipment_actions(context: Dictionary = {}) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		var root := entry.get("root") as EquipmentData
		var component := entry.get("component") as EquipmentData
		var runtime := entry.get("runtime") as EquipmentRuntimeState
		if effect == null:
			continue
		for raw_action in effect.get_activated_actions(self, root, component, runtime, context):
			var action := raw_action.duplicate()
			action["effect"] = effect
			action["root"] = root
			action["component"] = component
			action["runtime"] = runtime
			actions.append(action)
	return actions


func is_equipment_setup_ready(context: Dictionary = {}) -> bool:
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null and not effect.is_battle_setup_ready(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context):
			return false
	return true


func is_equipment_action_active(effect: EquipmentEffect) -> bool:
	if effect == null:
		return false
	for entry in _get_equipment_effect_entries():
		if entry.get("effect") == effect:
			return true
	return false


func gain_next_card_damage_bonus(amount: int) -> int:
	var actual := maxi(0, amount)
	pending_next_card_damage_bonus += actual
	return actual


func gain_next_attack_damage_bonus(amount: int, with_lifesteal: bool = false) -> int:
	var actual := maxi(0, amount)
	pending_next_attack_damage_bonus += actual
	if with_lifesteal:
		battle_action_flags["pending_next_attack_lifesteal"] = true
	return actual


func bind_next_card_damage_bonus(card: CardData) -> void:
	if card == null:
		return
	var bonus := pending_next_card_damage_bonus
	if card.is_attack_card():
		bonus += pending_next_attack_damage_bonus
		pending_next_attack_damage_bonus = 0
		if bool(battle_action_flags.get("pending_next_attack_lifesteal", false)):
			active_attack_lifesteal_cards[card.get_instance_id()] = true
			battle_action_flags.erase("pending_next_attack_lifesteal")
	if bonus > 0:
		active_card_damage_bonuses[card.get_instance_id()] = bonus
		pending_next_card_damage_bonus = 0


func get_next_card_damage_bonus(context: Dictionary = {}) -> int:
	var card := _get_context_card(context)
	if card == null:
		return 0
	return int(active_card_damage_bonuses.get(card.get_instance_id(), 0))


func finish_next_card_damage_bonus(card: CardData) -> void:
	if card != null:
		active_card_damage_bonuses.erase(card.get_instance_id())
		active_attack_lifesteal_cards.erase(card.get_instance_id())


func card_has_active_lifesteal(card: CardData) -> bool:
	return card != null and bool(active_attack_lifesteal_cards.get(card.get_instance_id(), false))


func get_card_ap_cost(card: CardData, context: Dictionary = {}) -> int:
	if card == null:
		return 0

	var merged_context := context.duplicate()
	merged_context["user"] = self
	merged_context["unit"] = self
	merged_context["card"] = card
	if not merged_context.has("druid_orientation"):
		merged_context["druid_orientation"] = get_druid_card_orientation(card)
	var cost := card.get_ap_cost_for_context(merged_context)
	var runtime_state := get_card_runtime_state(card, false)
	if not runtime_state.is_empty():
		cost += int(runtime_state.get("ap_delta", 0))
	for status in statuses:
		if status != null and status.has_method("modify_card_ap_cost"):
			cost = status.modify_card_ap_cost(self, card, cost, merged_context)
	if distortion_state.bloodseeking_ready and card.is_attack_card():
		cost -= 1

	return maxi(0, cost)


func get_card_resonance_cost(card: CardData, context: Dictionary = {}) -> int:
	if card == null:
		return 0
	var cost := maxi(0, card.resonance_cost)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			cost = effect.modify_resonance_cost(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, card, cost, context)
	return maxi(0, cost)


func notify_card_ap_cost_paid(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_card_ap_cost_paid", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_ap_cost_paid", [card], event_context)
	_notify_curse_effects("on_card_play_submitted", [card], event_context)
	notify_action_category_used(CardEnums.action_category_for_card(card.card_type), event_context)


func notify_ap_action_completed(ap_spent: int, context: Dictionary = {}) -> void:
	if ap_spent <= 0:
		return
	var event_context := _with_unit_context(context)
	for status in statuses.duplicate():
		if status != null:
			status.on_ap_action_completed(self, ap_spent, event_context)
	remove_expired_statuses()


func notify_after_card_played(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_card_played", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_after_card_played", [card], event_context)
	_notify_curse_effects("on_after_card_played", [card], event_context)
	_notify_equipment_effects("on_after_card_played", [card], event_context)
	_resolve_distortion_after_card(card, event_context)


func notify_ranger_stealth_cancelled(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_ranger_stealth_cancelled", [], event_context)
	_notify_equipment_effects("on_ranger_stealth_cancelled", [], event_context)


func notify_enemy_movement_completed(enemy: BattleUnitState, context: Dictionary = {}) -> void:
	_notify_status_effects("on_enemy_movement_completed", [enemy], _with_unit_context(context))


func notify_enemy_card_completed(enemy: BattleUnitState, card: CardData, context: Dictionary = {}) -> void:
	_notify_status_effects("on_enemy_card_completed", [enemy, card], _with_unit_context(context))


func notify_zone_turn_end(context: Dictionary = {}) -> void:
	_notify_zone_card_effects("on_zone_owner_turn_end", [], _with_unit_context(context))
	_notify_curse_effects("on_turn_end", [], _with_unit_context(context))


func notify_zone_turn_start(context: Dictionary = {}) -> void:
	_notify_zone_card_effects("on_zone_owner_turn_start", [], _with_unit_context(context))


func notify_curse_battle_started(context: Dictionary = {}) -> void:
	_notify_curse_effects("on_battle_started", [], _with_unit_context(context))


func notify_draw_phase_before(context: Dictionary = {}) -> void:
	_notify_curse_effects("on_draw_phase_before", [], _with_unit_context(context))


func notify_action_phase_started(context: Dictionary = {}) -> void:
	_notify_curse_effects("on_action_phase_started", [], _with_unit_context(context))


func notify_curse_battle_finished(victory: bool, context: Dictionary = {}) -> void:
	_notify_curse_effects("on_battle_finished", [victory], _with_unit_context(context))


func notify_life_lost(amount: int, context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	_notify_curse_effects("on_after_life_lost", [amount], _with_unit_context(context))


func notify_after_life_gained(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_life_gained", [], event_context)
	_notify_curse_effects("on_after_life_gained", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_life_gained", [], event_context)


func notify_kill(target: BattleUnitState, context: Dictionary = {}) -> void:
	_notify_curse_effects("on_kill", [target], _with_unit_context(context))


func notify_death(context: Dictionary = {}) -> void:
	_notify_curse_effects("on_death", [], _with_unit_context(context))


func get_curse_actions(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for curse in curse_zone:
		if not is_curse_effect_active(curse) or curse.definition == null or curse.definition.effect == null:
			continue
		for raw_action in curse.definition.effect.get_active_actions(self, curse, context):
			var action := raw_action.duplicate(true)
			action["curse"] = curse
			result.append(action)
	return result


func can_activate_curse_action(curse: CurseInstance, action_id: String, context: Dictionary = {}) -> bool:
	return curse != null and curse in curse_zone and is_curse_effect_active(curse) \
		and curse.definition != null and curse.definition.effect != null \
		and curse.definition.effect.can_activate_action(self, curse, action_id, context)


func activate_curse_action(curse: CurseInstance, action_id: String, context: Dictionary = {}) -> bool:
	if not can_activate_curse_action(curse, action_id, context):
		return false
	return curse.definition.effect.activate_action(self, curse, action_id, context)


func get_status_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := 0
	for status in statuses:
		if status != null and status.has_method("get_damage_bonus"):
			bonus += status.get_damage_bonus(self, context)

	return bonus


func get_status_damage_reduction(context: Dictionary = {}) -> int:
	var reduction := 0
	for status in statuses:
		if status != null and status.has_method("get_damage_reduction"):
			reduction += status.get_damage_reduction(self, context)

	return reduction


func get_curse_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := 0
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			bonus += curse.definition.effect.modify_damage_bonus(self, curse, context)
	return bonus


func get_curse_damage_reduction(context: Dictionary = {}) -> int:
	var reduction := 0
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			reduction += curse.definition.effect.modify_damage_reduction(self, curse, context)
	return reduction


func modify_healing_received(amount: int, context: Dictionary = {}) -> int:
	var result := maxi(0, amount)
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			result = curse.definition.effect.modify_healing_received(self, curse, result, context)
	return maxi(0, result)


func get_lethal_health_floor(context: Dictionary = {}) -> int:
	var result := 0
	for status in statuses:
		if status != null and status.has_method("get_lethal_health_floor"):
			result = maxi(result, int(status.get_lethal_health_floor(self, context)))
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			result = maxi(result, curse.definition.effect.get_lethal_health_floor(self, curse, context))
	return maxi(0, result)


func can_be_friendly_target(source: BattleUnitState, context: Dictionary = {}) -> bool:
	if source == null or source.faction != faction or source == self:
		return true
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if not curse.definition.effect.can_be_friendly_target(self, curse, source, context):
				return false
	return true


func can_be_targeted_by_other_card(source: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> bool:
	if source == null or source == self:
		return true
	return not distortion_state.has_field("night_veil") \
		or bool(distortion_state.battle_flags.get("night_veil_broken", false))


func should_counter_hostile_card(source: BattleUnitState, card: CardData, context: Dictionary = {}) -> bool:
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if curse.definition.effect.should_counter_card(self, curse, source, card, context):
				return true
	if distortion_state.has_field("empty_eye") and card != null and battle_controller != null \
			and not distortion_state.was_round_flag_used("empty_eye", battle_controller.battle_round):
		var target_type := card.get_target_type_for_mode(CardEnums.CardPlayMode.NORMAL, {
			"controller": battle_controller,
			"user": source,
			"card": card,
		})
		if target_type == CardEnums.TargetType.SINGLE:
			distortion_state.mark_round_flag("empty_eye", battle_controller.battle_round)
			battle_action_flags["empty_eye_countered"] = true
			return true
	return false


func can_use_action_category(category: int, context: Dictionary = {}) -> bool:
	if distortion_state.bloodseeking_ready:
		var card := context.get("card") as CardData
		if card != null and not card.is_attack_card():
			return false
	for status in statuses:
		if status != null and status.has_method("can_use_action_category") and not status.can_use_action_category(self, category, context):
			return false
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if not curse.definition.effect.can_use_action_category(self, curse, category, context):
				return false
	return true


func can_auto_reshuffle(context: Dictionary = {}) -> bool:
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if not curse.definition.effect.can_auto_reshuffle(self, curse, context):
				return false
	return true


func notify_action_category_used(category: int, context: Dictionary = {}) -> void:
	_notify_curse_effects("on_action_category_used", [category], _with_unit_context(context))


func get_zone_damage_reduction(context: Dictionary = {}) -> int:
	var reduction := 0
	for zone_name in ["mana", "enchant"]:
		var cards := _get_special_zone(zone_name)
		for zone_card in cards.duplicate():
			if zone_card == null or zone_card.effect == null:
				continue
			var event_context := _with_zone_context(zone_name, zone_card, context)
			reduction += maxi(0, zone_card.effect.get_zone_owner_damage_reduction(self, zone_card, event_context))
	return reduction + get_curse_damage_reduction(context)


func modify_incoming_damage(damage_context: DamageContext) -> void:
	if damage_context == null:
		return
	for status in statuses.duplicate():
		if status != null:
			status.modify_incoming_damage(self, damage_context)
	for curse in curse_zone.duplicate():
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			curse.definition.effect.modify_incoming_damage(self, curse, damage_context)
	remove_expired_statuses()


func modify_outgoing_damage(damage_context: DamageContext) -> void:
	if damage_context == null:
		return
	for status in statuses.duplicate():
		if status != null:
			status.modify_outgoing_damage(self, damage_context)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			effect.modify_outgoing_damage(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, damage_context)
	remove_expired_statuses()


func is_flying() -> bool:
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null and effect.grants_flying(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, {"unit": self}):
			return true
	return false


func get_agility() -> int:
	var result := 0
	if character_state != null:
		result = character_state.get_agility()
	elif enemy_state != null:
		result = enemy_state.get_agility()
	result = _modify_equipment_attribute("agility", result)
	if distortion_state.has_field("stampede"):
		result += maxi(0, get_strength())
	return EnemyRuleDispatcher.modify_agility(self, result) if enemy_state != null else result


func get_strength() -> int:
	var result := 0
	if is_druid() and druid_transformed:
		if character_state != null:
			result = character_state.get_intelligence()
		elif enemy_state != null:
			result = enemy_state.get_intelligence()
	elif character_state != null:
		result = character_state.get_strength()
	elif enemy_state != null:
		result = enemy_state.get_strength()
	return _modify_equipment_attribute("strength", result)


func get_intelligence() -> int:
	var result := 0
	if is_druid() and druid_transformed:
		if character_state != null:
			result = character_state.get_strength()
		elif enemy_state != null:
			result = enemy_state.get_strength()
	elif character_state != null:
		result = character_state.get_intelligence()
	elif enemy_state != null:
		result = enemy_state.get_intelligence()
	return _modify_equipment_attribute("intelligence", result)


func _modify_equipment_attribute(attribute: String, current_value: int) -> int:
	var result := current_value
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result = effect.modify_attribute(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, attribute, result, {"unit": self})
	return result


func get_starting_hand_size(config: BattleConfig) -> int:
	if config == null:
		return 0

	var hand_size := config.starting_hand_size
	if config.intelligence_per_starting_hand_card > 0:
		hand_size += floori(float(get_intelligence()) / float(config.intelligence_per_starting_hand_card))

	return maxi(0, hand_size)


func get_attack_range(equipment_slot: String = "", context: Dictionary = {}) -> int:
	return _get_attack_range(equipment_slot, context, false)


func get_attack_range_for_targeting(equipment_slot: String = "", context: Dictionary = {}) -> int:
	return _get_attack_range(equipment_slot, context, true)


func _get_attack_range(equipment_slot: String, context: Dictionary, range_only: bool) -> int:
	if not range_only and not can_use_attack_mode(equipment_slot, context):
		return 0
	var result := 0
	if character_state != null:
		result = character_state.get_attack_range(equipment_slot, get_active_weapon_face_index())
	elif enemy_state != null:
		result = enemy_state.get_attack_range(equipment_slot)
	if battle_controller != null:
		result = battle_controller.modify_attack_range_for_surface(self, result, equipment_slot)
	var profile := build_strike_profile_object(equipment_slot, {"skip_surface_range": true})
	var range_context := context.merged({"equipment_slot": equipment_slot, "range_type": profile.primary_range_type})
	for status in statuses:
		if status != null:
			result = status.modify_attack_range(self, result, range_context)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result = effect.modify_attack_range(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, result, range_context)
	if not range_only and not ranger_state.active_weapon_lock_slot.is_empty() and ranger_state.active_weapon_lock_slot != equipment_slot:
		return 0
	result += distortion_state.lashing_range_bonus
	return maxi(0, result)


func build_strike_profile_object(equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	if character_state != null:
		merged_context["weapon_face_override"] = get_active_weapon_face_index()
		var profile := character_state.build_strike_profile_object(equipment_slot, merged_context)
		for entry in _get_equipment_effect_entries():
			var effect := entry.get("effect") as EquipmentEffect
			if effect != null:
				effect.modify_strike_profile(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, profile, merged_context)
		return profile
	if enemy_state != null:
		return enemy_state.build_strike_profile_object(equipment_slot, merged_context)

	var profile := StrikeProfile.new()
	profile.primary_slot = "unarmed"
	profile.primary_equipment = null
	profile.primary_base_damage = 1
	profile.primary_range = 0
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = CardEnums.DamageType.STRENGTH
	profile.primary_damage_bonus = 0
	profile.add_offhand = false
	profile.offhand_equipment = null
	profile.offhand_base_damage = 0
	profile.offhand_damage_bonus = 0
	return profile


func needs_weapon_choice() -> bool:
	if character_state != null:
		return character_state.needs_weapon_choice(get_active_weapon_face_index())

	return false


func get_attack_weapon_options() -> Array:
	if character_state != null:
		var available := []
		for option in character_state.get_attack_weapon_options(get_active_weapon_face_index()):
			if can_use_attack_mode(str(option.get("slot", ""))):
				available.append(option)
		return available

	if enemy_state != null:
		var weapon := enemy_state.get_active_weapon()
		return [{
			"slot": "weapon",
			"label": weapon.item_name if weapon != null else "天生武器",
			"weapon": weapon,
			"equipment": weapon,
			"base_damage": weapon.base_damage if weapon != null else enemy_state.enemy_data.innate_base_damage,
			"range": get_attack_range(),
			"range_type": weapon.range_type if weapon != null else EquipmentData.WeaponRangeType.MELEE,
		}]
	return []


func can_use_attack_mode(equipment_slot: String, context: Dictionary = {}) -> bool:
	if not ranger_state.active_weapon_lock_slot.is_empty() and ranger_state.active_weapon_lock_slot != equipment_slot:
		return false
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null and not effect.can_use_attack_mode(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, equipment_slot, context):
			return false
	return true


func get_active_weapon_face_index() -> int:
	if character_state == null or character_state.weapon_equipment == null:
		return 0
	var root := character_state.weapon_equipment
	if is_druid() and root.is_druid_form_linked_weapon():
		return 1 if druid_transformed else 0
	return character_state.weapon_face


func get_active_weapon_equipment() -> EquipmentData:
	if character_state != null:
		return character_state.get_weapon_face(get_active_weapon_face_index())
	if enemy_state != null:
		return enemy_state.get_active_weapon()
	return null


func has_equipment_subcategory(subcategory: String) -> bool:
	if character_state != null:
		return character_state.has_equipment_subcategory(subcategory)

	return false


func get_battle_texture() -> Texture2D:
	if character_state != null and character_state.character_data != null:
		return character_state.character_data.battle_sprite
	if enemy_state != null and enemy_state.enemy_data != null:
		var chapter_one_art := ChapterOneEnemyCatalog.get_art_texture(enemy_state.enemy_data.archetype_id, "battle")
		if chapter_one_art != null:
			return chapter_one_art
		return enemy_state.enemy_data.battle_sprite

	return null


func get_max_ap(config: BattleConfig) -> int:
	if character_state != null:
		return character_state.get_max_ap(config)
	if enemy_state != null:
		return EnemyRuleDispatcher.modify_max_ap(self, enemy_state.get_max_ap(config))

	return config.base_ap


func get_move_distance_per_ap(config: BattleConfig, agility_modifier: int = 0) -> int:
	var effective_agility := maxi(0, get_agility() + agility_modifier)
	var distance := config.base_move_cells_per_ap
	if config.agility_per_move_cell > 0:
		distance += floori(float(effective_agility) / float(config.agility_per_move_cell))
	var context := {
		"config": config,
		"agility_modifier": agility_modifier,
		"effective_agility": effective_agility,
	}
	for status in statuses:
		if status != null and status.has_method("modify_move_distance_per_ap"):
			distance = status.modify_move_distance_per_ap(self, distance, context)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			distance = effect.modify_move_distance_per_ap(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, distance, context)
	if enemy_state != null:
		distance = EnemyRuleDispatcher.modify_move_distance(self, distance)

	return maxi(1, distance)


func get_move_ap_cost(distance: int, config: BattleConfig) -> int:
	var move_per_ap := get_move_distance_per_ap(config)
	var bonus := get_next_move_distance_bonus({"config": config, "distance": distance})
	var cost := ceili(float(maxi(0, distance - bonus)) / float(move_per_ap))
	if distance > 0:
		cost = maxi(1, cost)
	var context := {
		"config": config,
		"distance": distance,
		"move_distance_per_ap": move_per_ap,
	}
	for status in statuses:
		if status != null and status.has_method("modify_move_ap_cost"):
			cost = status.modify_move_ap_cost(self, cost, context)
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			cost = curse.definition.effect.modify_move_ap_cost(self, curse, cost, context)

	return maxi(0, cost)


func get_next_move_distance_bonus(context: Dictionary = {}) -> int:
	var result := 0
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result += effect.get_next_move_distance_bonus(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context)
	return maxi(0, result)


func can_start_voluntary_movement() -> bool:
	for status in statuses:
		if status != null and status.has_method("can_start_voluntary_movement") and not status.can_start_voluntary_movement(self):
			return false
	return true


func notify_move_ap_cost_paid(context: Dictionary = {}) -> void:
	for status in statuses.duplicate():
		if status != null and status.has_method("on_move_ap_cost_paid"):
			status.on_move_ap_cost_paid(self, context)
	notify_action_category_used(CardEnums.ActionCategory.MOVE, context)

	remove_expired_statuses()


func cell_distance_to(other: BattleUnitState) -> int:
	if other == null:
		return 2147483647
	if cell == BattleHexGrid.INVALID_CELL or other.cell == BattleHexGrid.INVALID_CELL:
		return 2147483647
	var distance := BattleHexGrid.distance(cell, other.cell)
	for occupied in other.get_occupied_cells():
		distance = mini(distance, BattleHexGrid.distance(cell, occupied))
	return distance


func get_range_distance_to(other: BattleUnitState, context: Dictionary = {}) -> int:
	var distance := cell_distance_to(other)
	if other == null:
		return distance
	for origin in get_alternate_range_origins(context):
		distance = mini(distance, BattleHexGrid.distance(origin, other.cell))
	return distance


func get_alternate_range_origins(context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for status in statuses:
		if status == null or status.should_remove():
			continue
		for origin in status.get_alternate_range_origins(self, context):
			if origin != BattleHexGrid.INVALID_CELL and not result.has(origin):
				result.append(origin)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		for origin in effect.get_alternate_range_origins(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context):
			if not result.has(origin):
				result.append(origin)
	for curse in curse_zone:
		if not is_curse_effect_active(curse) or curse.definition == null or curse.definition.effect == null:
			continue
		for origin in curse.definition.effect.get_alternate_range_origins(self, curse, context):
			if origin != BattleHexGrid.INVALID_CELL and not result.has(origin):
				result.append(origin)
	return result


func get_equipment_card_duplicate_targets(card: CardData, targets: Array, context: Dictionary = {}) -> Array:
	var result: Array = []
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		for target in effect.get_card_duplicate_targets(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, card, targets, context):
			if not result.has(target):
				result.append(target)
	return result


func get_occupied_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if cell != BattleHexGrid.INVALID_CELL:
		result.append(cell)
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		for occupied in effect.get_additional_occupied_cells(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, {"unit": self}):
			if occupied != BattleHexGrid.INVALID_CELL and not result.has(occupied):
				result.append(occupied)
	return result


func set_hex_cell(new_cell: Vector2i, map_data: BattleMapData) -> void:
	cell = new_cell
	if map_data != null and map_data.is_valid_cell(new_cell):
		position = map_data.cell_to_map(new_cell)


func draw_cards(count: int, rng: RandomNumberGenerator, context: Dictionary = {}) -> int:
	return draw_cards_detailed(count, rng, context).size()


func shuffle_draw_pile(rng: RandomNumberGenerator) -> void:
	_shuffle_cards(draw_pile, rng)


func draw_cards_detailed(count: int, rng: RandomNumberGenerator, context: Dictionary = {}) -> Array[CardData]:
	var drawn_cards: Array[CardData] = []
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty() and not discard_pile.is_empty():
			if not can_auto_reshuffle(context):
				break
			_notify_curse_effects("on_before_reshuffle", [], _with_unit_context(context))
			if not is_alive():
				break
			draw_pile.assign(discard_pile)
			discard_pile.clear()
			_shuffle_cards(draw_pile, rng)

		if draw_pile.is_empty():
			break

		var drawn_card: CardData = draw_pile.pop_back() as CardData
		hand.append(drawn_card)
		drawn_cards.append(drawn_card)
		_notify_card_drawn(drawn_card, context)
	if not drawn_cards.is_empty():
		_notify_draw_action_completed(drawn_cards, context)

	return drawn_cards


func mill_cards(count: int, context: Dictionary = {}) -> Array[CardData]:
	var milled: Array[CardData] = []
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty():
			break

		var card: CardData = draw_pile.pop_back() as CardData
		if card == null:
			continue
		milled.append(card)
		var discard_context := context.duplicate()
		discard_context["reason"] = "mill"
		add_card_to_discard(card, discard_context)

	return milled


func preview_discard_after_mill(count: int) -> Array[CardData]:
	var result: Array[CardData] = discard_pile.duplicate()
	var available := mini(maxi(0, count), draw_pile.size())
	for index in range(available):
		var draw_index := draw_pile.size() - 1 - index
		var card: CardData = draw_pile[draw_index]
		if card != null:
			result.append(card)

	return result


func discard_card(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	var previous_hand_size := hand.size()
	hand.remove_at(index)
	var moved := add_card_to_discard(card, context)
	_notify_hand_size_changed(previous_hand_size, context)
	return moved


func add_card_to_discard(card: CardData, context: Dictionary = {}) -> bool:
	if card == null:
		return false
	var runtime_state := get_card_runtime_state(card, false)
	if bool(runtime_state.get("exile_on_leave_hand", false)) or _should_exile_discarded_card(card, context):
		exiled_pile.append(card)
		clear_card_runtime_state(card)
		if battle_controller != null:
			battle_controller._emit_log("%s 的 %s 改为进入放逐区。" % [get_display_name(), card.card_name])
		return true
	discard_pile.append(card)
	_notify_card_discarded(card, context)
	return true


func add_card_to_mana_zone(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		return

	mana_zone.append(card)
	_notify_card_entered_special_zone(card, "mana", context)


func add_card_to_enchant_zone(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		return

	enchant_zone.append(card)
	distortion_state.register_manifestation(card)
	_notify_card_entered_special_zone(card, "enchant", context)


func move_enchant_card_to_discard(card: CardData, context: Dictionary = {}) -> bool:
	var index := enchant_zone.find(card)
	if index < 0:
		return false

	enchant_zone.remove_at(index)
	distortion_state.unregister_manifestation(card)
	clear_card_runtime_state(card)
	return add_card_to_discard(card, context)


func add_curse_to_zone(curse: CurseInstance, context: Dictionary = {}) -> void:
	if curse == null or curse_zone.has(curse):
		return
	curse_zone.append(curse)
	_notify_curse_state_changed(curse, context)


func remove_curse_from_zone(curse: CurseInstance, context: Dictionary = {}) -> bool:
	if curse == null or not curse_zone.has(curse):
		return false
	curse_zone.erase(curse)
	warlock_state.remove_curse(curse)
	curse_runtime_states.erase(curse)
	_notify_curse_state_changed(curse, context)
	return true


func move_hand_card_to_mana(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	var previous_hand_size := hand.size()
	hand.remove_at(index)
	add_card_to_mana_zone(card, context)
	_notify_hand_size_changed(previous_hand_size, context)
	return true


func move_hand_card_to_enchant(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	var previous_hand_size := hand.size()
	hand.remove_at(index)
	add_card_to_enchant_zone(card, context)
	_notify_hand_size_changed(previous_hand_size, context)
	return true


func get_active_distortion_fields() -> PackedStringArray:
	return distortion_state.get_active_fields()


func get_active_distortion_summary() -> String:
	var labels := PackedStringArray()
	for field_id in get_active_distortion_fields():
		var source_count := distortion_state.get_source_count(field_id)
		var label := DistortionCatalog.get_display_name(field_id)
		labels.append("%s×%d" % [label, source_count] if source_count > 1 else label)
	return "、".join(labels)


func get_manifestable_hand_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for card in hand:
		if card != null and card.has_mutation_fields() and distortion_state.card_adds_new_field(card):
			result.append(card)
	return result


func manifest_cards_from_hand(cards: Array[CardData], context: Dictionary = {}) -> int:
	if cards.size() > 2:
		return 0
	var unique_cards: Array[CardData] = []
	for card in cards:
		if card == null or unique_cards.has(card) or not hand.has(card) \
				or not card.has_mutation_fields() or not distortion_state.card_adds_new_field(card):
			return 0
		unique_cards.append(card)
	var manifested := 0
	for card in unique_cards:
		var manifest_context := context.duplicate()
		manifest_context["reason"] = str(manifest_context.get("reason", "manual_manifest"))
		if move_hand_card_to_enchant(card, manifest_context):
			manifested += 1
	distortion_state.pending_manual_manifest = false
	return manifested


func manifest_card_from_draw_pile(card: CardData, context: Dictionary = {}) -> CardData:
	if card == null or not card.has_mutation_fields():
		return null
	var index := draw_pile.find(card)
	if index < 0:
		return null
	draw_pile.remove_at(index)
	add_card_to_enchant_zone(card, context)
	return card


func release_all_manifestations(context: Dictionary = {}) -> int:
	var released := 0
	for card in distortion_state.manifested_cards.duplicate():
		if card != null and enchant_zone.has(card) and move_enchant_card_to_discard(card, context):
			released += 1
	return released


func decay_turn_start_manifestations(context: Dictionary = {}) -> int:
	var decayed := 0
	for card in distortion_state.decay_snapshot:
		if card != null and enchant_zone.has(card):
			var decay_context := context.duplicate()
			decay_context["reason"] = "mutation_decay"
			if move_enchant_card_to_discard(card, decay_context):
				decayed += 1
	distortion_state.decay_snapshot.clear()
	return decayed


func get_curse(curse_id: String) -> CurseInstance:
	for curse in curse_zone:
		if curse != null and curse.get_curse_id() == curse_id:
			return curse
	return null


func gain_curse_wave(amount: int, context: Dictionary = {}) -> int:
	var actual := maxi(0, amount)
	if actual <= 0:
		return 0
	curse_wave += actual
	_notify_curse_resource_changed("curse_wave", actual, context)
	return actual


func consume_curse_wave(amount: int, context: Dictionary = {}) -> int:
	var actual := mini(curse_wave, maxi(0, amount))
	if actual <= 0:
		return 0
	curse_wave -= actual
	_notify_curse_resource_changed("curse_wave", -actual, context)
	if is_warlock_adventurer() and not bool(context.get("skip_warlock_draw", false)) and battle_controller != null:
		draw_cards(mini(2, actual), battle_controller.rng, {
			"controller": battle_controller,
			"reason": "warlock_curse_wave_spent",
			"draw_source": "warlock_curse_wave",
			"extra_draw": true,
		})
	return actual


func can_pay_warlock_mana(amount: int, curse_wave_amount: int = 0) -> bool:
	if not is_warlock_adventurer():
		return false
	var cost := maxi(0, amount)
	var wave_cost := clampi(curse_wave_amount, 0, cost)
	return curse_wave >= wave_cost and warlock_state.get_mana() >= cost - wave_cost


func pay_warlock_mana(amount: int, curse_wave_amount: int = 0, context: Dictionary = {}) -> bool:
	if not can_pay_warlock_mana(amount, curse_wave_amount):
		return false
	var cost := maxi(0, amount)
	var wave_cost := clampi(curse_wave_amount, 0, cost)
	if not warlock_state.pay_mana(cost - wave_cost):
		return false
	if wave_cost > 0:
		consume_curse_wave(wave_cost, context)
	return true


func is_curse_effect_active(curse: CurseInstance) -> bool:
	return curse != null and curse.is_active_in_curse_zone() \
		and not curse_suppression.is_suppressed(curse) \
		and (not is_warlock_adventurer() or not warlock_state.is_face_down(curse))


func suppress_curse_for_battle(curse: CurseInstance) -> bool:
	return curse != null and curse in curse_zone and curse_suppression.suppress(curse)


func meets_warlock_hex_conditions(minimum_face_down_count: int, required_keywords: PackedStringArray = []) -> bool:
	return is_warlock_adventurer() and warlock_state.meets_hex_conditions(
		curse_zone,
		minimum_face_down_count,
		required_keywords
	)


func set_warlock_curse_face_down(curse: CurseInstance, face_down: bool, context: Dictionary = {}) -> bool:
	if not is_warlock_adventurer() or curse == null or not curse_zone.has(curse):
		return false
	if not warlock_state.set_face_down(curse, face_down):
		return false
	_notify_curse_state_changed(curse, context)
	return true


func add_warlock_curse_counter(curse: CurseInstance, counter_id: String, amount: int = 1, context: Dictionary = {}) -> int:
	if not is_warlock_adventurer() or curse == null or not curse_zone.has(curse) \
			or not warlock_state.is_face_down(curse):
		return 0
	var added := warlock_state.add_curse_counter(curse, counter_id, amount)
	if added > 0:
		_notify_curse_state_changed(curse, context)
	return added


func corrupt_existing_indicators(amount: int = 1) -> int:
	if not is_warlock_adventurer() or amount <= 0:
		return 0
	var changed_types := 0
	for status in statuses.duplicate():
		if status == null or status.should_remove() or not status.is_corruptible_counter or status.stacks <= 0:
			continue
		var increment := status.duplicate(false) as StatusEffect
		increment.stacks = amount
		add_status(increment)
		changed_types += 1
	if curse_wave > 0:
		gain_curse_wave(amount, {
			"controller": battle_controller,
			"reason": "warlock_corruption",
		})
		changed_types += 1
	changed_types += warlock_state.corrupt_face_down_curse_counters(curse_zone, amount)
	return changed_types


func get_curse_runtime_state(curse: CurseInstance, create_if_missing: bool = true) -> Dictionary:
	if curse == null:
		return {}
	if curse_runtime_states.has(curse):
		return curse_runtime_states[curse] as Dictionary
	if not create_if_missing:
		return {}
	var state: Dictionary = {}
	curse_runtime_states[curse] = state
	return state


func get_available_mana() -> int:
	return druid_state.get_mana()


func get_mana_capacity() -> int:
	return get_available_mana()


func get_unspent_persistent_mana() -> int:
	return get_available_mana()


func can_pay_mana(amount: int) -> bool:
	return druid_state.can_pay_mana(amount)


func can_pay_mana_excluding_card(amount: int, excluded_card: CardData) -> bool:
	return can_pay_mana(amount)


func pay_mana(amount: int, context: Dictionary = {}) -> bool:
	var cost := maxi(0, amount)
	if not druid_state.pay_mana(cost):
		return false
	if cost > 0:
		_notify_mana_paid(cost, context)
	return true


func pay_mana_excluding_card(amount: int, excluded_card: CardData, context: Dictionary = {}) -> bool:
	return pay_mana(amount, context)


func remove_card_from_mana_zone(card: CardData) -> bool:
	var index := mana_zone.find(card)
	if index < 0:
		return false
	mana_zone.remove_at(index)
	return true


func gain_mana(amount: int, context: Dictionary = {}) -> int:
	var actual := druid_state.gain_mana(amount)
	if actual > 0:
		_notify_mana_gained(actual, context)
	return actual


func gain_temporary_mana(amount: int, context: Dictionary = {}) -> void:
	gain_mana(amount, context)


func clear_mana(_context: Dictionary = {}) -> int:
	return druid_state.clear_mana()


func is_druid() -> bool:
	return get_character_class() == CardEnums.CardClass.DRUID


func is_druid_transformed() -> bool:
	return is_druid() and druid_transformed


func try_replace_druid_form_change(value: bool, context: Dictionary = {}) -> Dictionary:
	if not is_druid() or value == druid_transformed or bool(context.get("bypass_form_replacement", false)):
		return {}
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		var result := effect.try_replace_druid_form_change(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, value, context)
		if bool(result.get("handled", false)):
			return result
	return {}


func can_replace_druid_form_change(value: bool, context: Dictionary = {}) -> bool:
	if not is_druid() or value == druid_transformed:
		return false
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null and effect.can_replace_druid_form_change(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, value, context):
			return true
	return false


func notify_druid_form_change_requested(value: bool, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_druid_form_change_requested", [value], _with_unit_context(context))


func should_druid_card_enter_mana_after_play(card: CardData, current_value: bool, context: Dictionary = {}) -> bool:
	var result := current_value
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result = effect.modify_druid_card_enters_mana_after_play(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, card, result, context)
	return result


func set_druid_transformed(value: bool, context: Dictionary = {}) -> void:
	var previous := druid_transformed
	var next_value := value if is_druid() else false
	if previous == next_value:
		return
	var root := character_state.weapon_equipment if character_state != null else null
	if root != null:
		_notify_equipment_effects("on_druid_form_exiting", [previous], context.merged({"controller": battle_controller}), root, 1 if previous else 0)
	druid_transformed = next_value
	if root != null:
		_notify_equipment_effects("on_druid_form_entered", [druid_transformed], context.merged({"controller": battle_controller}), root, 1 if druid_transformed else 0)
		_notify_equipment_effects("on_druid_form_changed", [previous, druid_transformed], {
			"controller": battle_controller,
			"previous_form": previous,
			"transformed": druid_transformed,
		}.merged(context), root, 1 if druid_transformed else 0)


func get_druid_card_orientation(card: CardData) -> int:
	if card != null and card.upright_play_ignores_form:
		return CardEnums.DruidOrientation.UPRIGHT
	if is_druid_transformed() and card != null and card.is_druid_dual_card:
		return CardEnums.DruidOrientation.INVERTED

	return CardEnums.DruidOrientation.UPRIGHT


func discard_all_hand(context: Dictionary = {}) -> int:
	var count := hand.size()
	for card in hand.duplicate():
		if card != null:
			add_card_to_discard(card, context)
	hand.clear()
	_notify_hand_size_changed(count, context)
	return count


func move_draw_card_to_discard(card: CardData, context: Dictionary = {}) -> bool:
	var index := draw_pile.find(card)
	if index < 0:
		return false

	draw_pile.remove_at(index)
	var discard_context := context.duplicate()
	if not discard_context.has("reason"):
		discard_context["reason"] = "draw_to_discard"
	return add_card_to_discard(card, discard_context)


func move_discard_card_to_hand(card: CardData) -> bool:
	var index := discard_pile.find(card)
	if index < 0:
		return false

	discard_pile.remove_at(index)
	hand.append(card)
	return true


func move_draw_card_to_hand(card: CardData) -> bool:
	if card == null or not draw_pile.has(card):
		return false
	draw_pile.erase(card)
	hand.append(card)
	return true


func banish_discard_card(card: CardData) -> bool:
	var index := discard_pile.find(card)
	if index < 0:
		return false

	discard_pile.remove_at(index)
	exiled_pile.append(card)
	return true


func move_exiled_card_to_discard(card: CardData, context: Dictionary = {}) -> bool:
	var index := exiled_pile.find(card)
	if index < 0:
		return false

	exiled_pile.remove_at(index)
	var discard_context := context.duplicate()
	if not discard_context.has("reason"):
		discard_context["reason"] = "exile_to_discard"
	return add_card_to_discard(card, discard_context)


func has_pending_curse_choice(context: Dictionary = {}) -> bool:
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if curse.definition.effect.has_pending_choice(self, curse, context):
				return true
	return false


func banish_discard_cards(count: int, excluded_card: CardData = null) -> Array[CardData]:
	var banished: Array[CardData] = []
	if count <= 0:
		return banished

	for card in discard_pile.duplicate():
		if banished.size() >= count:
			break
		if card == null or card == excluded_card:
			continue
		if banish_discard_card(card):
			banished.append(card)

	return banished


func count_discard_cards_excluding(excluded_card: CardData = null) -> int:
	var count := 0
	for card in discard_pile:
		if card != null and card != excluded_card:
			count += 1

	return count


func shuffle_exiled_into_draw_pile(rng: RandomNumberGenerator) -> int:
	if exiled_pile.is_empty():
		return 0

	var returned_count := exiled_pile.size()
	for card in exiled_pile:
		if card != null:
			draw_pile.append(card)
	exiled_pile.clear()
	_shuffle_cards(draw_pile, rng)
	return returned_count


func move_discard_cards_to_draw_top(cards_in_top_order: Array[CardData], max_count: int = 3) -> Array[CardData]:
	var moved: Array[CardData] = []
	for card in cards_in_top_order:
		if moved.size() >= max_count:
			break
		if card == null:
			continue
		var index := discard_pile.find(card)
		if index < 0:
			continue
		discard_pile.remove_at(index)
		moved.append(card)

	for i in range(moved.size() - 1, -1, -1):
		draw_pile.append(moved[i])

	return moved


func has_card_in_hand(card: CardData) -> bool:
	return hand.find(card) >= 0


func has_card_in_discard(card: CardData) -> bool:
	return discard_pile.find(card) >= 0


func has_card_in_exile(card: CardData) -> bool:
	return exiled_pile.find(card) >= 0


func has_card_in_enchant(card: CardData) -> bool:
	return enchant_zone.find(card) >= 0


func get_card_runtime_state(card: CardData, create_if_missing: bool = true) -> Dictionary:
	if card == null:
		return {}
	if card_runtime_states.has(card):
		return card_runtime_states[card] as Dictionary
	if not create_if_missing:
		return {}

	var state: Dictionary = {}
	card_runtime_states[card] = state
	return state


func clear_card_runtime_state(card: CardData) -> void:
	if card != null:
		card_runtime_states.erase(card)


func get_effective_card_elements(card: CardData) -> Array[int]:
	var result: Array[int] = []
	if card == null:
		return result
	for element in card.get_printed_elements():
		if not result.has(element):
			result.append(element)
	var runtime_state := get_card_runtime_state(card, false)
	var infused_element := int(runtime_state.get("adventure_element_infusion", BattleSurfaceState.Element.NONE))
	if BattleSurfaceState.BASE_ELEMENTS.has(infused_element) and not result.has(infused_element):
		result.append(infused_element)
	return result


func initialize_mage_opening_hand() -> Dictionary:
	if not is_mage_adventurer():
		return {}
	var gains: Dictionary = {}
	for card in hand:
		for element in get_effective_card_elements(card):
			gains[element] = int(gains.get(element, 0)) + 1
	return mage_state.gain_mana_batch(gains)


func mark_temporary_card(card: CardData, ap_delta: int, exile_after_play: bool, exile_at_turn_end: bool) -> void:
	var state := get_card_runtime_state(card)
	state["ap_delta"] = ap_delta
	state["exile_after_play"] = exile_after_play
	state["exile_at_turn_end"] = exile_at_turn_end
	state["expire_turn_serial"] = turn_serial


func should_exile_card_after_play(card: CardData) -> bool:
	var state := get_card_runtime_state(card, false)
	return bool(state.get("exile_after_play", false))


func move_card_to_exile(card: CardData, context: Dictionary = {}) -> bool:
	if card == null:
		return false
	if exiled_pile.find(card) >= 0:
		clear_card_runtime_state(card)
		return true

	if remove_card_from_mana_zone(card):
		exiled_pile.append(card)
		clear_card_runtime_state(card)
		return true

	var hand_index := hand.find(card)
	if hand_index >= 0:
		var previous_hand_size := hand.size()
		hand.remove_at(hand_index)
		exiled_pile.append(card)
		clear_card_runtime_state(card)
		_notify_hand_size_changed(previous_hand_size, context.merged({"reason": "move_to_exile"}, false))
		return true
	var simple_zones: Array = [draw_pile, discard_pile]
	for zone_value in simple_zones:
		var zone: Array = zone_value as Array
		var zone_index: int = zone.find(card)
		if zone_index >= 0:
			zone.remove_at(zone_index)
			exiled_pile.append(card)
			clear_card_runtime_state(card)
			return true
	var enchant_index := enchant_zone.find(card)
	if enchant_index >= 0:
		enchant_zone.remove_at(enchant_index)
		distortion_state.unregister_manifestation(card)
		exiled_pile.append(card)
		clear_card_runtime_state(card)
		return true
	return false


func exile_expiring_temporary_cards(controller: BattleController) -> int:
	var exiled_count := 0
	for card_value in card_runtime_states.keys().duplicate():
		var card: CardData = card_value as CardData
		var state := get_card_runtime_state(card, false)
		if not bool(state.get("exile_at_turn_end", false)):
			continue
		if int(state.get("expire_turn_serial", -1)) > turn_serial:
			continue
		if move_card_to_exile(card):
			exiled_count += 1
			if controller != null:
				controller._emit_log("%s 的临时牌 %s 在回合结束时被放逐。" % [get_display_name(), card.card_name])
		else:
			clear_card_runtime_state(card)
	return exiled_count


func has_used_battle_action(action_id: String) -> bool:
	return bool(battle_action_flags.get(action_id, false))


func mark_battle_action_used(action_id: String) -> void:
	if action_id.is_empty():
		return
	battle_action_flags[action_id] = true


func notify_after_damage_dealt(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_damage_dealt", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_damage_dealt", [], event_context)
	_notify_curse_effects("on_after_damage_dealt", [], event_context)
	_notify_equipment_effects("on_after_damage_dealt", [], event_context)
	if enemy_state != null and battle_controller != null:
		EnemyRuleDispatcher.on_after_damage_dealt(battle_controller, self, event_context)
	if distortion_state.has_field("night_veil") and not bool(distortion_state.battle_flags.get("night_veil_broken", false)):
		_reserve_night_veil_break(int(event_context.get("action_id", 0)))


func notify_after_damage_taken(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_damage_taken", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_damage_taken", [], event_context)
	_notify_curse_effects("on_after_damage_taken", [], event_context)
	_notify_equipment_effects("on_after_damage_taken", [], event_context)
	if enemy_state != null and battle_controller != null:
		EnemyRuleDispatcher.on_after_damage_taken(battle_controller, self, event_context)


func notify_after_heal_given(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_heal_given", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_heal_given", [], event_context)


func notify_after_heal_received(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_heal_received", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_heal_received", [], event_context)


func notify_after_strike(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_strike", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_strike", [], event_context)
	_notify_equipment_effects("on_after_strike", [], event_context)
	if enemy_state != null and battle_controller != null:
		EnemyRuleDispatcher.on_after_strike(battle_controller, self, event_context)
	_resolve_distortion_scorch_throat(event_context)
	_finish_night_veil_action(int(event_context.get("action_id", 0)))


func notify_before_strike(context: Dictionary = {}) -> Dictionary:
	var event_context := _with_unit_context(context)
	# Status event hooks are queued; context mutations needed by the resolver use
	# this synchronous query pass so they exist before element/profile selection.
	for status in statuses.duplicate():
		if status != null and _script_defines_method(status, "modify_strike_context"):
			status.modify_strike_context(self, event_context)
	remove_expired_statuses()
	_notify_equipment_effects("on_before_strike", [], event_context)
	return event_context


func notify_movement_completed(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_curse_effects("on_movement_completed", [], event_context)
	_notify_equipment_effects("on_movement_completed", [], event_context)
	if enemy_state != null and battle_controller != null:
		EnemyRuleDispatcher.on_movement_completed(battle_controller, self, event_context)
	for card in discard_pile.duplicate():
		if card != null and card.effect != null and card.effect.has_method("on_discard_owner_movement_completed"):
			card.effect.call("on_discard_owner_movement_completed", self, card, event_context)
	if not bool(event_context.get("forced", false)):
		if distortion_state.has_field("bloodseeking"):
			distortion_state.bloodseeking_ready = true
		_resolve_distortion_stampede(event_context)


func notify_ranger_combo_milestone(threshold: int, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_ranger_combo_milestone", [threshold], _with_unit_context(context))


func notify_ranger_elements_collected(added: int, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_ranger_elements_collected", [added], _with_unit_context(context))


func notify_ranger_payload_completed(context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_ranger_payload_completed", [], _with_unit_context(context))


func consume_equipment_preloaded_payload(context: Dictionary = {}) -> int:
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null:
			continue
		var payload := effect.consume_preloaded_payload_after_strike(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, context)
		if payload != BattleSurfaceState.Element.NONE:
			return payload
	return BattleSurfaceState.Element.NONE


func notify_equipment_battle_started(context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_battle_started", [], _with_unit_context(context))


func modify_ranger_element_collection(current_amount: int, context: Dictionary = {}) -> int:
	var result := current_amount
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result = effect.modify_ranger_element_collection(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, result, context)
	return maxi(0, result)


func modify_ranger_ambush_multiplier(current_multiplier: float, context: Dictionary = {}) -> float:
	var result := current_multiplier
	for entry in _get_equipment_effect_entries():
		var effect := entry.get("effect") as EquipmentEffect
		if effect != null:
			result = effect.modify_ranger_ambush_multiplier(self, entry.get("root") as EquipmentData, entry.get("component") as EquipmentData, entry.get("runtime") as EquipmentRuntimeState, result, context)
	return maxf(1.0, result)


func notify_equipment_switched(switch_result: Dictionary, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["switch_result"] = switch_result
	_notify_zone_card_effects("on_zone_owner_equipment_switched", [switch_result], event_context)


func notify_equipment_turn_start(context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_turn_start", [], _with_unit_context(context))


func notify_observed_unit_turn_start(started_unit: BattleUnitState, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_unit_turn_started", [started_unit], _with_unit_context(context))


func notify_equipment_turn_end(context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_turn_end", [], _with_unit_context(context))


func notify_equipment_before_switch_out(equipment: EquipmentData, face_index: int, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_before_switch_out", [], _with_unit_context(context), equipment, face_index)


func notify_equipment_switched_out(equipment: EquipmentData, face_index: int, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_switched_out", [], _with_unit_context(context), equipment, face_index)


func notify_equipment_switched_in(equipment: EquipmentData, face_index: int, context: Dictionary = {}) -> void:
	_notify_equipment_effects("on_switched_in", [], _with_unit_context(context), equipment, face_index)


func get_armor_stacks() -> int:
	var armor := get_status("armor")
	return armor.stacks if armor != null else 0


func get_shared_armor_stacks() -> int:
	var shared_armor := get_status("abyss_shared_armor")
	return shared_armor.stacks if shared_armor != null else 0


func gain_armor(amount: int, context: Dictionary = {}) -> int:
	var modified_amount := amount
	for status in statuses:
		if status != null:
			modified_amount = status.modify_armor_gain(self, modified_amount, context)
	var actual := maxi(0, modified_amount)
	if actual <= 0:
		return 0
	var previous := get_armor_stacks()
	var armor := get_status("armor")
	if armor == null:
		armor = ArmorStatus.new()
		armor.stacks = actual
		add_status(armor)
	else:
		armor.add_stacks(actual)
	notify_armor_changed(previous, get_armor_stacks(), context)
	return actual


func clear_armor(context: Dictionary = {}) -> int:
	var armor := get_status("armor")
	if armor == null or armor.stacks <= 0:
		return 0
	var previous := armor.stacks
	armor.stacks = 0
	notify_armor_changed(previous, 0, context)
	remove_expired_statuses()
	return previous


func notify_armor_changed(previous: int, current: int, context: Dictionary = {}) -> void:
	if previous == current:
		return
	var event_context := _with_unit_context(context)
	event_context["previous_armor"] = previous
	event_context["current_armor"] = current
	_notify_status_effects("on_armor_changed", [previous, current], event_context)
	_notify_zone_card_effects("on_zone_owner_armor_changed", [previous, current], event_context)
	if enemy_state != null and battle_controller != null:
		EnemyRuleDispatcher.on_armor_changed(battle_controller, self, previous, current)


func _reset_druid_state() -> void:
	mana_zone.clear()
	for card in enchant_zone:
		distortion_state.unregister_manifestation(card)
	enchant_zone.clear()
	curse_zone.clear()
	druid_transformed = false
	druid_prepare_used = false
	druid_state.reset_for_battle()


func add_status(status: StatusEffect) -> void:
	if status == null or status.status_id.is_empty() or status.stacks <= 0:
		return

	var existing := get_status(status.status_id)
	if existing != null:
		existing.add_stacks(status.stacks)
		_notify_distortion_negative_status_added(status)
		return

	statuses.append(status if status.resource_path.is_empty() else status.duplicate(true))
	_notify_distortion_negative_status_added(status)


func get_distortion_draw_count() -> int:
	var result := preview_distortion_draw_count()
	if distortion_state.has_field("enlightenment") and curse_wave > 0:
		consume_curse_wave(1, {"controller": battle_controller, "reason": "distortion_enlightenment"})
	return result


func preview_distortion_draw_count() -> int:
	var result := 3 if distortion_state.has_field("beast_heart") else 1
	if distortion_state.has_field("enlightenment") and curse_wave > 0:
		result += 1
	return result


func resolve_distortion_turn_start() -> void:
	if battle_controller == null or not distortion_state.has_field("irradiation"):
		return
	var affected := 0
	for other in battle_controller.units:
		if other == null or other == self or not other.is_alive() or cell_distance_to(other) > 2:
			continue
		var anomaly := DruidDelayedDamageStatus.new()
		anomaly.stacks = 1
		other.add_status(anomaly)
		affected += 1
	if affected > 0:
		gain_curse_wave(mini(3, affected), {
			"controller": battle_controller,
			"reason": "distortion_irradiation",
		})
		battle_controller._emit_log("%s 的辐照令 %d 个单位获得异常。" % [get_display_name(), affected])


func get_distortion_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if distortion_state.can_use_lashing():
		for amount in range(1, 4):
			result.append({
				"id": "lashing_%d" % amount,
				"label": "鞭笞 %d：伤害加值-%d，攻击范围+%d" % [amount, amount, amount],
			})
	return result


func activate_distortion_action(action_id: String) -> bool:
	if not action_id.begins_with("lashing_"):
		return false
	var amount := int(action_id.trim_prefix("lashing_"))
	if not distortion_state.apply_lashing(amount):
		return false
	if battle_controller != null:
		battle_controller._emit_log("%s 发动鞭笞：本回合伤害加值-%d，攻击范围+%d。" % [get_display_name(), amount, amount])
		battle_controller.state_changed.emit()
	return true


func consume_empty_eye_counter_flag() -> bool:
	if not bool(battle_action_flags.get("empty_eye_countered", false)):
		return false
	battle_action_flags.erase("empty_eye_countered")
	return true


func _resolve_distortion_after_card(card: CardData, context: Dictionary) -> void:
	if battle_controller == null or card == null:
		return
	_notify_hand_size_changed(1, context)
	if distortion_state.bloodseeking_ready and card.is_attack_card():
		distortion_state.bloodseeking_ready = false
	if distortion_state.has_field("appendage"):
		var target_units: Array[BattleUnitState] = []
		for target_value in context.get("targets", []):
			var target := target_value as BattleUnitState
			if target != null and target.is_alive() and target.faction != faction and not target_units.has(target):
				target_units.append(target)
		if not target_units.is_empty():
			battle_controller.enqueue_trigger(
				Callable(self, "_resolve_appendage_targets"),
				[target_units],
				-10,
				"畸变·附肢",
				context
			)
	if distortion_state.has_field("beast_heart") and not hand.is_empty():
		var discard_index := battle_controller.rng.randi_range(0, hand.size() - 1)
		var discarded: CardData = hand[discard_index]
		if discard_card(discarded, {
			"controller": battle_controller,
			"reason": "distortion_beast_heart",
			"source_card": card,
		}):
			gain_curse_wave(1, {"controller": battle_controller, "reason": "distortion_beast_heart"})
			battle_controller._emit_log("%s 的兽心随机弃置了%s。" % [get_display_name(), discarded.card_name])
	_finish_night_veil_action(int(context.get("action_id", 0)))


func _resolve_appendage_targets(targets: Array[BattleUnitState]) -> void:
	if battle_controller == null:
		return
	for target in targets:
		if target != null and target.is_alive():
			battle_controller.apply_damage(self, target, 1, "附肢", {
				"fixed_damage": true,
				"distortion_field": "appendage",
			})


func _resolve_distortion_stampede(context: Dictionary) -> void:
	if battle_controller == null or not distortion_state.has_field("stampede") \
			or bool(distortion_state.turn_flags.get("stampede_used", false)):
		return
	distortion_state.turn_flags["stampede_used"] = true
	var wave_before := curse_wave
	var effect_range := 1
	var base_damage := 1
	if wave_before >= 10:
		consume_curse_wave(10, {"controller": battle_controller, "reason": "distortion_stampede"})
		effect_range = 3
		base_damage = 5
	elif wave_before >= 5:
		consume_curse_wave(wave_before, {"controller": battle_controller, "reason": "distortion_stampede"})
		effect_range = 2
		base_damage = ceili(float(wave_before) / 2.0)
	var damage := maxi(0, base_damage + get_agility() + get_damage_bonus({
		"controller": battle_controller,
		"damage_type": CardEnums.DamageType.AGILITY,
		"distortion_field": "stampede",
	}))
	for other in battle_controller.units:
		if other != null and other != self and other.is_alive() and cell_distance_to(other) <= effect_range:
			battle_controller.apply_damage(self, other, damage, "奔踏", {
				"distortion_field": "stampede",
			})
	battle_controller._emit_log("%s 的奔踏波及范围 %d。" % [get_display_name(), effect_range])


func _resolve_distortion_scorch_throat(context: Dictionary) -> void:
	if battle_controller == null or not distortion_state.has_field("scorch_throat"):
		return
	var target := context.get("target") as BattleUnitState
	if target == null:
		return
	var equipment_slot := str(context.get("equipment_slot", ""))
	var max_range := battle_controller.get_effective_attack_range_against(self, target, equipment_slot)
	if get_range_distance_to(target, {"controller": battle_controller, "equipment_slot": equipment_slot}) != max_range:
		return
	battle_controller.apply_base_surface_element(target.cell, BattleSurfaceState.Element.FIRE)
	if curse_wave < 2:
		return
	consume_curse_wave(2, {"controller": battle_controller, "reason": "distortion_scorch_throat"})
	for neighbor in BattleHexGrid.neighbors(target.cell):
		if battle_controller.map_data.is_valid_cell(neighbor):
			battle_controller.apply_base_surface_element(neighbor, BattleSurfaceState.Element.FIRE)


func _notify_distortion_negative_status_added(status: StatusEffect) -> void:
	if battle_controller == null or not distortion_state.has_field("mud_lung") or not _is_negative_status(status):
		return
	battle_controller.heal_unit(self, self, 2, "泥肺")


func _is_negative_status(status: StatusEffect) -> bool:
	if status == null:
		return false
	var negative_ids := PackedStringArray([
		"stun",
		"breach",
		"cripple",
		"druid_anomaly",
		"druid_weakness",
		"ranger_blind",
		"ranger_move_surcharge",
		"ranger_rooted",
		"ranger_burn",
		"ranger_discard_debt",
		"ranger_dagger_damage_penalty",
		"abyss_card_surcharge",
		"temporary_curse_report",
	])
	return negative_ids.has(status.status_id) or status.status_id.begins_with("curse_disease_pending:")


func _notify_hand_size_changed(previous_size: int, context: Dictionary = {}) -> void:
	_notify_status_effects("on_hand_size_changed", [previous_size], _with_unit_context(context))
	if previous_size <= 0 or not hand.is_empty() or battle_controller == null \
			or battle_controller.battle_round <= 0 or not distortion_state.has_field("rock_scale") \
			or distortion_state.was_round_flag_used("rock_scale", battle_controller.battle_round):
		return
	distortion_state.mark_round_flag("rock_scale", battle_controller.battle_round)
	var block := BlockStatus.new()
	block.stacks = 1
	add_status(block)
	var consumed := consume_curse_wave(2, context.merged({
		"controller": battle_controller,
		"reason": "distortion_rock_scale",
	}))
	if consumed > 0:
		gain_armor(consumed * 2, context.merged({"controller": battle_controller}))
	battle_controller._emit_log("%s 的岩鳞在失去最后一张手牌时生效。" % get_display_name())


func _get_night_veil_damage_bonus(context: Dictionary) -> int:
	var action_id := int(context.get("action_id", battle_controller.get_current_action_id() if battle_controller != null else 0))
	var pending_action := int(distortion_state.battle_flags.get("night_veil_break_action_id", -1))
	if pending_action >= 0:
		if pending_action == action_id:
			return int(distortion_state.battle_flags.get("night_veil_reserved_wave", 0))
		_finish_night_veil_action(pending_action)
		return 0
	return mini(3, curse_wave)


func _reserve_night_veil_break(action_id: int) -> void:
	if distortion_state.battle_flags.has("night_veil_break_action_id"):
		return
	var reserved := consume_curse_wave(mini(3, curse_wave), {
		"controller": battle_controller,
		"reason": "distortion_night_veil",
	})
	distortion_state.battle_flags["night_veil_reserved_wave"] = reserved
	if action_id <= 0:
		distortion_state.battle_flags["night_veil_broken"] = true
	else:
		distortion_state.battle_flags["night_veil_break_action_id"] = action_id


func _finish_night_veil_action(action_id: int) -> void:
	var pending_action := int(distortion_state.battle_flags.get("night_veil_break_action_id", -1))
	if pending_action < 0 or pending_action != action_id:
		return
	distortion_state.battle_flags.erase("night_veil_break_action_id")
	distortion_state.battle_flags.erase("night_veil_reserved_wave")
	distortion_state.battle_flags["night_veil_broken"] = true


func get_status(status_id: String) -> StatusEffect:
	for status in statuses:
		if status != null and status.status_id == status_id:
			return status

	return null


func has_status(status_id: String) -> bool:
	return get_status(status_id) != null


func remove_status(status_id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		var status: StatusEffect = statuses[i]
		if status != null and status.status_id == status_id:
			statuses.remove_at(i)


func remove_expired_statuses() -> void:
	for i in range(statuses.size() - 1, -1, -1):
		var status: StatusEffect = statuses[i]
		if status == null or status.should_remove():
			statuses.remove_at(i)


func _notify_card_drawn(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["drawn_card"] = card
	_notify_status_effects("on_card_drawn", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_drawn", [card], event_context)
	_notify_curse_effects("on_card_drawn", [card], event_context)
	_notify_equipment_effects("on_card_drawn", [card], event_context)
	if card != null and card.effect != null:
		_dispatch_trigger(
			Callable(card.effect, "on_self_drawn"),
			[self, card, event_context],
			card.effect.effect_priority,
			"%s.on_self_drawn" % card.card_name,
			event_context
		)


func _notify_draw_action_completed(cards: Array[CardData], context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["drawn_cards"] = cards.duplicate()
	_notify_curse_effects("on_draw_action_completed", [cards], event_context)


func _notify_card_discarded(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["discarded_card"] = card
	_notify_status_effects("on_card_discarded", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_discarded", [card], event_context)
	_notify_curse_effects("on_card_discarded", [card], event_context)
	_notify_equipment_effects("on_card_discarded", [card], event_context)


func _notify_card_entered_special_zone(card: CardData, zone_name: String, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["entered_card"] = card
	event_context["zone_name"] = zone_name
	_notify_status_effects("on_card_entered_special_zone", [card, zone_name], event_context)
	_notify_zone_card_effects("on_zone_card_entered_special_zone", [card, zone_name], event_context)


func _notify_mana_gained(amount: int, context: Dictionary = {}) -> void:
	var actual := maxi(0, amount)
	if actual <= 0:
		return

	var event_context := _with_unit_context(context)
	event_context["mana_gained"] = actual
	_notify_status_effects("on_mana_gained", [actual], event_context)
	_notify_zone_card_effects("on_zone_owner_mana_gained", [actual], event_context)
	_notify_equipment_effects("on_mana_gained", [actual], event_context)


func _notify_mana_paid(amount: int, context: Dictionary = {}) -> void:
	var actual := maxi(0, amount)
	if actual <= 0:
		return
	var event_context := _with_unit_context(context)
	event_context["mana_paid"] = actual
	event_context["controller"] = event_context.get("controller", battle_controller)
	_notify_equipment_effects("on_mana_paid", [actual], event_context)


func _notify_status_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for status in statuses.duplicate():
		if status == null or not _script_defines_method(status, method_name):
			continue
		var args := [self]
		args.append_array(extra_args)
		args.append(context)
		_dispatch_trigger(
			Callable(self, "_invoke_status_hook"),
			[status, method_name, args],
			status.effect_priority,
			"%s.%s" % [status.display_name, method_name],
			context
		)


func _invoke_status_hook(status: StatusEffect, method_name: String, args: Array) -> void:
	if status == null or not statuses.has(status) or status.should_remove():
		return
	status.callv(method_name, args)
	remove_expired_statuses()


func _get_equipment_effect_entries(root: EquipmentData = null, face_index: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if character_state == null:
		return result
	var resolved_root := root if root != null else character_state.weapon_equipment
	if resolved_root == null:
		return result
	var resolved_face := face_index if face_index >= 0 else get_active_weapon_face_index()
	var runtime := get_equipment_runtime_state(resolved_root)
	for raw_entry in resolved_root.get_effect_entries(resolved_face):
		result.append({
			"effect": raw_entry.get("effect"),
			"component": raw_entry.get("component"),
			"root": resolved_root,
			"runtime": runtime,
		})
	return result


func _notify_equipment_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}, root: EquipmentData = null, face_index: int = -1) -> void:
	for entry in _get_equipment_effect_entries(root, face_index):
		var effect := entry.get("effect") as EquipmentEffect
		if effect == null or not effect.has_method(method_name):
			continue
		var args := [
			self,
			entry.get("root") as EquipmentData,
			entry.get("component") as EquipmentData,
			entry.get("runtime") as EquipmentRuntimeState,
		]
		args.append_array(extra_args)
		args.append(context)
		effect.callv(method_name, args)


func _notify_all_equipment_runtime_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for runtime_value in equipment_runtime_states.values():
		var runtime := runtime_value as EquipmentRuntimeState
		if runtime == null or runtime.equipment == null:
			continue
		for raw_entry in runtime.equipment.get_effect_entries(0):
			var effect := raw_entry.get("effect") as EquipmentEffect
			if effect == null or not effect.has_method(method_name):
				continue
			if character_state != null and runtime.equipment != character_state.weapon_equipment \
					and not effect.receives_inactive_runtime_event(method_name):
				continue
			var args := [self, runtime.equipment, raw_entry.get("component") as EquipmentData, runtime]
			args.append_array(extra_args)
			args.append(context)
			effect.callv(method_name, args)


func _equipment_runtime_key(equipment: EquipmentData) -> String:
	if equipment == null:
		return ""
	return "instance:%d" % equipment.get_instance_id()


func _get_context_card(context: Dictionary) -> CardData:
	var card_value: Variant = context.get("card")
	if card_value is CardData:
		return card_value as CardData
	var source_value: Variant = context.get("source")
	if source_value is CardData:
		return source_value as CardData
	return null


func _notify_zone_card_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	_notify_zone_card_effects_in_zone(mana_zone, "mana", method_name, extra_args, context)
	_notify_zone_card_effects_in_zone(enchant_zone, "enchant", method_name, extra_args, context)


func _notify_zone_card_effects_in_zone(cards: Array[CardData], zone_name: String, method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for zone_card in cards.duplicate():
		if zone_card == null or zone_card.effect == null or not _script_defines_method(zone_card.effect, method_name):
			continue

		var event_context := _with_zone_context(zone_name, zone_card, context)
		var args := [self, zone_card]
		args.append_array(extra_args)
		args.append(event_context)
		_dispatch_trigger(
			Callable(zone_card.effect, method_name),
			args,
			zone_card.effect.effect_priority,
			"%s.%s" % [zone_card.card_name, method_name],
			event_context
		)


func _notify_curse_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for curse in curse_zone.duplicate():
		if not is_curse_effect_active(curse) or curse.definition == null or curse.definition.effect == null:
			continue
		var effect: CurseEffect = curse.definition.effect
		if not effect.has_method(method_name):
			continue
		var event_context := context.duplicate()
		event_context["curse"] = curse
		event_context["curse_id"] = curse.get_curse_id()
		event_context["curse_depth"] = curse.depth
		var args := [self, curse]
		args.append_array(extra_args)
		args.append(event_context)
		_dispatch_trigger(
			Callable(self, "_execute_curse_trigger").bind(curse, effect, method_name, args),
			[],
			effect.effect_priority,
			"%s.%s" % [curse.get_display_name(), method_name],
			event_context
		)


func _execute_curse_trigger(curse: CurseInstance, effect: CurseEffect, method_name: String, args: Array) -> void:
	# A trigger can wait behind other effects. Re-check here so a curse
	# suppressed while it was queued cannot fire later in this battle.
	if not is_curse_effect_active(curse) or effect == null or curse.definition == null \
			or curse.definition.effect != effect or not effect.has_method(method_name):
		return
	effect.callv(method_name, args)


func _dispatch_trigger(callback: Callable, args: Array, priority: int, label: String, context: Dictionary) -> void:
	if bool(context.get("immediate", false)):
		callback.callv(args)
		return
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null and controller.get_current_action_id() > 0:
		controller.enqueue_trigger(callback, args, priority, label, context)
	else:
		callback.callv(args)


func _script_defines_method(resource: Resource, method_name: String) -> bool:
	if resource == null or resource.get_script() == null:
		return false
	for method in resource.get_script().get_script_method_list():
		if str(method.get("name", "")) == method_name:
			return true
	return false


func _with_zone_context(zone_name: String, zone_card: CardData, context: Dictionary = {}) -> Dictionary:
	var event_context := context.duplicate()
	event_context["zone_owner"] = self
	event_context["zone_card"] = zone_card
	event_context["zone_name"] = zone_name
	return event_context


func _get_special_zone(zone_name: String) -> Array[CardData]:
	match zone_name:
		"mana":
			return mana_zone
		"enchant":
			return enchant_zone
		_:
			return []


func _with_unit_context(context: Dictionary = {}) -> Dictionary:
	var event_context := context.duplicate()
	event_context["unit"] = self
	event_context["owner"] = self
	return event_context


func _prepare_deck(stacks: Array[CardStack], rng: RandomNumberGenerator, starting_hand_size: int) -> void:
	if not draw_pile.is_empty() or not hand.is_empty() or not discard_pile.is_empty():
		return

	for stack in stacks:
		if stack == null or stack.card_data == null:
			continue
		for _i in range(stack.count):
			var runtime_card := stack.card_data.duplicate() as CardData
			if runtime_card != null:
				var runtime_state := get_card_runtime_state(runtime_card)
				runtime_state["adventure_stack_id"] = stack.stack_id
				if character_state != null and character_state.card_adventure_modifiers.has(stack.stack_id):
					var adventure_modifiers := character_state.card_adventure_modifiers.get(stack.stack_id, {}) as Dictionary
					if adventure_modifiers.has("element"):
						runtime_state["adventure_element_infusion"] = int(adventure_modifiers["element"])
						runtime_state["adventure_element_infusion_used"] = false
				draw_pile.append(runtime_card)
	if character_state != null:
		for industry_card in character_state.create_industry_cards():
			draw_pile.append(industry_card)

	_shuffle_cards(draw_pile, rng)
	draw_cards(starting_hand_size, rng)


func _setup_curses_from_character_state(_rng: RandomNumberGenerator) -> void:
	curse_zone.clear()
	if character_state == null:
		return
	for curse in character_state.get_active_curses():
		curse_zone.append(curse)


func _reset_curse_turn_runtime() -> void:
	for state_value in curse_runtime_states.values():
		var state := state_value as Dictionary
		if state == null:
			continue
		for key_value in state.keys().duplicate():
			var key := str(key_value)
			if key.begins_with("turn_"):
				state.erase(key_value)


func _notify_curse_state_changed(curse: CurseInstance, context: Dictionary = {}) -> void:
	if curse == null:
		return
	var controller: BattleController = context.get("controller", battle_controller) as BattleController
	if controller != null:
		controller.state_changed.emit()


func _notify_curse_resource_changed(resource_id: String, delta: int, context: Dictionary = {}) -> void:
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			curse.definition.effect.on_curse_resource_changed(self, curse, resource_id, delta, context)
	var controller: BattleController = context.get("controller", battle_controller) as BattleController
	if controller != null:
		controller.state_changed.emit()


func _should_exile_discarded_card(card: CardData, context: Dictionary = {}) -> bool:
	for curse in curse_zone:
		if is_curse_effect_active(curse) and curse.definition != null and curse.definition.effect != null:
			if curse.definition.effect.should_exile_discarded_card(self, curse, card, context):
				return true
	return false


func _shuffle_cards(cards: Array[CardData], rng: RandomNumberGenerator) -> void:
	if cards.size() < 2:
		return

	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: CardData = cards[i]
		cards[i] = cards[j]
		cards[j] = temp


func _resolve_token_radius(default_radius: float) -> float:
	var data_radius := 0.0
	if character_state != null:
		data_radius = character_state.get_battle_token_radius()
	elif enemy_state != null:
		data_radius = enemy_state.get_battle_token_radius()

	if data_radius > 0.0:
		return data_radius

	return default_radius
