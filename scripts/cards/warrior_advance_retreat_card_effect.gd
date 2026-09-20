extends CardEffect
class_name WarriorAdvanceRetreatCardEffect

const STEADY := "steady"
const ASSAULT := "assault"

@export_range(1, 99, 1) var steady_momentum: int = 1
@export_range(1, 99, 1) var steady_armor: int = 2
@export_range(1, 99, 1) var assault_momentum_cost: int = 2
@export_range(1, 99, 1) var assault_damage_bonus: int = 5


func _init() -> void:
	uses_strike = true


func requires_card_choice(context: Dictionary = {}) -> bool:
	return str(context.get("card_choice", "")).is_empty()


func get_card_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择进退有势的战术"


func get_card_choice_options(context: Dictionary = {}) -> Array[Dictionary]:
	var user := context.get("user") as BattleUnitState
	var can_assault := user != null and user.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) >= assault_momentum_cost
	return [
		{"id": STEADY, "label": "稳进", "description": "获得 1 点势，打击后获得 2 护甲。", "enabled": true},
		{"id": ASSAULT, "label": "强攻", "description": "消耗 2 点势，进行获得 +5 伤害加值的武器打击。", "enabled": can_assault},
	]


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var choice := str(context.get("card_choice", ""))
	if choice == STEADY:
		return true
	if choice == ASSAULT:
		var user := context.get("user") as BattleUnitState
		return user != null and user.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) >= assault_momentum_cost
	return false


func pay_play_cost(context: Dictionary = {}) -> bool:
	if str(context.get("card_choice", "")) != ASSAULT:
		return can_pay_play_cost(context)
	var user := context.get("user") as BattleUnitState
	return user != null and user.consume_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, assault_momentum_cost)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	if str(context.get("card_choice", "")) == STEADY:
		controller.gain_class_resource(user, BattleController.WARRIOR_MOMENTUM_RESOURCE, steady_momentum)
		controller.perform_unit_strike_with_after_effects(user, target, card, "进退有势·稳进", str(context.get("equipment_slot", "")), Callable(self, "_grant_steady_armor").bind(user, context))
	elif str(context.get("card_choice", "")) == ASSAULT:
		controller.perform_strike_with_modifier(user, target, card, assault_damage_bonus, "进退有势·强攻", str(context.get("equipment_slot", "")))


func _grant_steady_armor(user: BattleUnitState, context: Dictionary) -> void:
	if user != null:
		user.gain_armor(steady_armor, context)
