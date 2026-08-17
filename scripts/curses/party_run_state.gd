extends Resource
class_name PartyRunState

const STARTING_RITUAL_POINTS := 3
const MIN_RITUAL_DEBT := -2
const SAVE_VERSION := 6

@export var ritual_points: int = STARTING_RITUAL_POINTS
@export_group("Adventure")
@export var save_version: int = SAVE_VERSION
@export var run_seed: int = 0
@export var floor_index: int = 0
@export var floor_count: int = 2
@export var gold: int = 40
@export var provisions: int = 14
@export var camp_points: int = 0
@export var camp_supplies: int = 0
@export var card_removals_used: int = 0
@export_range(1, 1000, 1) var enemy_health_percent: int = 100
@export var run_complete: bool = false
@export var run_failed: bool = false
@export var party: Array[CharacterState] = []
@export var floor_state: AdventureFloorState
@export var pending_transaction: PendingAdventureTransaction
@export var adventure_flags: Dictionary = {}
@export var equipment_reward_drawn_paths: PackedStringArray = []
@export var equipment_reward_offers: Dictionary = {}
@export var equipment_class_miss_streaks: Dictionary = {}


func initialize_adventure(seed_value: int, heroes: Array[CharacterState], definition: AdventureDefinition) -> void:
	var resolved_definition := definition if definition != null else AdventureDefinition.new()
	var economy := resolved_definition.get_economy()
	save_version = SAVE_VERSION
	run_seed = seed_value
	floor_index = 0
	floor_count = resolved_definition.floor_count
	gold = economy.starting_gold
	provisions = economy.first_floor_provisions
	camp_points = 0
	camp_supplies = 0
	ritual_points = STARTING_RITUAL_POINTS
	card_removals_used = 0
	enemy_health_percent = 100
	run_complete = false
	run_failed = false
	party = heroes
	pending_transaction = PendingAdventureTransaction.new()
	adventure_flags.clear()
	equipment_reward_drawn_paths.clear()
	equipment_reward_offers.clear()
	equipment_class_miss_streaks.clear()
	for index in range(party.size()):
		var hero := party[index]
		if hero != null:
			hero.ensure_initialized()
			hero.ensure_adventure_instance_ids(index)


func get_active_party() -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for hero in party:
		if hero != null and hero.current_health > 0 and not hero.is_curse_overloaded():
			result.append(hero)
	return result


func add_gold(amount: int) -> int:
	var actual := maxi(0, amount)
	gold += actual
	return actual


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	return true


func add_provisions(amount: int) -> int:
	var actual := maxi(0, amount)
	provisions += actual
	if actual > 0 and floor_state != null:
		floor_state.ambush_chance = 0
	return actual


func spend_provision() -> bool:
	if provisions <= 0:
		return false
	provisions -= 1
	return true


func add_camp_points(amount: int, cap: int = 12) -> int:
	var before := camp_points
	camp_points = clampi(camp_points + maxi(0, amount), 0, cap)
	return camp_points - before


func spend_camp_points(amount: int) -> bool:
	if amount < 0 or camp_points < amount:
		return false
	camp_points -= amount
	return true


func mark_equipment_reward_drawn(item_path: String) -> bool:
	if item_path.is_empty() or equipment_reward_drawn_paths.has(item_path):
		return false
	equipment_reward_drawn_paths.append(item_path)
	return true


func begin_transaction(type: int, id: String, payload: Dictionary = {}) -> void:
	if pending_transaction == null:
		pending_transaction = PendingAdventureTransaction.new()
	pending_transaction.begin(type, id, payload)


func commit_transaction() -> void:
	if pending_transaction == null:
		pending_transaction = PendingAdventureTransaction.new()
	else:
		pending_transaction.clear()


func gain_ritual_points(amount: int) -> int:
	var actual := maxi(0, amount)
	ritual_points += actual
	return actual


func can_pay_ritual(cost: int, resolves_overload: bool = false) -> bool:
	if cost <= 0:
		return true
	if ritual_points < 0:
		return false
	if ritual_points >= cost:
		return true
	return resolves_overload and ritual_points - cost >= MIN_RITUAL_DEBT


func pay_ritual(cost: int, resolves_overload: bool = false) -> bool:
	if not can_pay_ritual(cost, resolves_overload):
		return false
	ritual_points -= maxi(0, cost)
	return true
