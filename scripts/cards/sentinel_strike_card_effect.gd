extends CardEffect
class_name SentinelStrikeCardEffect

@export_range(-12, 12, 1) var inner_range_modifier: int = -1
@export var close_damage_multiplier: float = 1.5
@export_range(0, 99, 1) var cripple_stacks: int = 2
@export_range(0, 99, 1) var move_ap_discount: int = 1


func _init() -> void:
	uses_strike = true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null:
		return

	var equipment_slot := str(context.get("equipment_slot", ""))
	var weapon_range := user.get_attack_range(equipment_slot)
	var close_range := maxi(0, weapon_range + inner_range_modifier)

	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue

		var target_unit: BattleUnitState = target as BattleUnitState
		var distance := user.cell_distance_to(target_unit)
		var is_close := distance <= close_range
		var is_in_weapon_range := distance <= weapon_range
		var damage_multiplier := close_damage_multiplier if is_close else 1.0

		controller.perform_strike_with_multiplier(user, target_unit, card, damage_multiplier, "哨卫打击", equipment_slot)

		if is_in_weapon_range:
			if target_unit.is_alive():
				var cripple := CrippleStatus.new()
				cripple.stacks = cripple_stacks
				target_unit.add_status(cripple)
				controller._emit_log("%s 获得 %d 层致残。" % [target_unit.get_display_name(), cripple_stacks])
		else:
			var discount := NextMoveApDiscountStatus.new()
			discount.stacks = 1
			discount.discount_amount = move_ap_discount
			user.add_status(discount)
			controller._emit_log("%s 的下次移动 AP 消耗 -%d。" % [user.get_display_name(), move_ap_discount])
