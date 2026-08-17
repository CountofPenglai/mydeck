extends CardEffect
class_name DefensiveStanceCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

@export_range(1, 99, 1) var block_stacks: int = 1


func can_play(context: Dictionary = {}) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	return controller != null and controller.can_switch_prepared_weapon(user)


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	var switch_result := controller.switch_prepared_weapon(user)
	if not bool(switch_result.get("success", false)):
		return

	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM:
		_strike_nearest_enemy(controller, user, card, str(context.get("equipment_slot", "")))
		return

	var block := BlockStatus.new()
	block.stacks = block_stacks
	user.add_status(block)
	controller._emit_log("%s 获得 %d 层抵挡。" % [user.get_display_name(), block_stacks])


func _strike_nearest_enemy(
	controller: BattleController,
	user: BattleUnitState,
	card: CardData,
	equipment_slot: String
) -> void:
	var profile := user.build_strike_profile_object(equipment_slot)
	var nearest: BattleUnitState
	var nearest_distance := 999999
	for target in controller.get_units_in_attack_range(
		user,
		0,
		BattleController.UnitFilter.OPPONENTS,
		equipment_slot
	):
		if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
				and not controller.targeting.has_line_of_sight_between_units(user, target):
			continue
		var distance := BattleHexGrid.distance(user.cell, target.cell)
		if nearest == null or distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	if nearest != null:
		controller.perform_strike(user, nearest, card, "防御架势余势", equipment_slot)
		return
	controller._emit_log("%s 切换武器后，范围内没有可打击的敌人。" % user.get_display_name())
