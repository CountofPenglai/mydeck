extends CardEffect
class_name DefensiveStanceCardEffect

@export_range(1, 99, 1) var block_stacks: int = 1

func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	if user == null:
		return

	var block := BlockStatus.new()
	block.stacks = block_stacks
	user.add_status(block)

	var switch_on_block := WeaponSwitchOnBlockStatus.new()
	switch_on_block.stacks = 1
	user.add_status(switch_on_block)

	if controller != null and controller.has_method("_emit_log"):
		controller._emit_log("%s 获得 %d 层抵挡，并准备在下次抵挡成功时切换武器。" % [user.get_display_name(), block_stacks])
