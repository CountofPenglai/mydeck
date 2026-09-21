extends Resource
class_name AdventureEconomyConfig

@export var starting_gold: int = 40
@export var camp_point_cap: int = 12
@export var shelter_camp_points: int = 4
@export var camp_supply_price: int = 15
@export var card_removal_base_price: int = 40
@export var card_removal_price_growth: int = 20
@export var normal_gold_by_floor: PackedInt32Array = [10, 12, 15]
@export var elite_gold_by_floor: PackedInt32Array = [25, 30, 35]
@export var boss_gold_by_floor: PackedInt32Array = [35, 45, 60]


func get_battle_gold(room_type: int, floor_index: int) -> int:
	var values := normal_gold_by_floor
	match room_type:
		AdventureEnums.RoomType.ELITE_BATTLE:
			values = elite_gold_by_floor
		AdventureEnums.RoomType.BOSS_BATTLE:
			values = boss_gold_by_floor
	if values.is_empty():
		return 0
	return values[clampi(floor_index, 0, values.size() - 1)]


func get_card_removal_price(removals_used: int) -> int:
	return card_removal_base_price + maxi(0, removals_used) * card_removal_price_growth
