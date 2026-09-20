extends CardEffect
class_name WarriorDefensivePursuitCardEffect

@export_range(1, 99, 1) var normal_armor: int = 2
@export_range(1, 99, 1) var armor_cap: int = 5
@export_range(1, 99, 1) var damage_per_armor: int = 2


func _init() -> void:
	uses_strike = true


func get_target_type_for_mode(_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return CardEnums.TargetType.SINGLE if play_mode == CardEnums.CardPlayMode.MOMENTUM else default_target_type


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) != CardEnums.CardPlayMode.MOMENTUM:
		user.gain_armor(normal_armor, context)
		return
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var spent := _spend_armor(user, armor_cap, context)
	if spent <= 0:
		return
	controller.perform_strike_with_modifier(user, targets[0] as BattleUnitState, card, spent * damage_per_armor, "护势追击", str(context.get("equipment_slot", "")))


func _spend_armor(user: BattleUnitState, maximum: int, context: Dictionary) -> int:
	var armor := user.get_status("armor")
	if armor == null:
		return 0
	var previous := armor.stacks
	var spent := mini(maximum, previous)
	armor.stacks -= spent
	user.notify_armor_changed(previous, armor.stacks, context)
	user.remove_expired_statuses()
	return spent
