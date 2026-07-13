extends Resource
class_name BattleConfig

@export var base_ap: int = 4
@export_range(1, 12, 1) var base_move_cells_per_ap: int = 1
@export_range(1, 20, 1) var agility_per_move_cell: int = 5
@export var starting_hand_size: int = 4
@export var intelligence_per_starting_hand_card: int = 2
@export var ap_per_end_turn_draw: int = 2
@export var basic_attack_ap_cost: int = 2
@export var default_token_radius: float = 24.0
