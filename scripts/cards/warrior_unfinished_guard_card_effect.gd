extends CardEffect
class_name WarriorUnfinishedGuardCardEffect

@export_range(1, 99, 1) var normal_armor: int = 4
@export_range(1, 99, 1) var block_stacks: int = 1


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var user := context.get("user") as BattleUnitState
	if user == null:
		return
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) != CardEnums.CardPlayMode.MOMENTUM:
		user.gain_armor(normal_armor, context)
		return
	var block := BlockStatus.new()
	block.stacks = block_stacks
	user.add_status(block)
