extends CardEffect
class_name SlamCardEffect

@export var shield_tag: String = "盾牌"
@export_range(0, 99, 1) var stun_stacks: int = 2
@export_range(0, 99, 1) var two_handed_damage_bonus: int = 2

func _init() -> void:
	uses_strike = true

func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	var card = context.get("card")
	if controller == null or user == null:
		return

	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue

		var equipment_slot := str(context.get("equipment_slot", ""))
		controller.perform_strike_with_modifier(
			user,
			target,
			card,
			_two_handed_bonus(user, equipment_slot),
			"猛击",
			equipment_slot
		)
		if target.is_alive() and user.has_equipment_subcategory(shield_tag):
			var stun := StunStatus.new()
			stun.stacks = stun_stacks
			target.add_status(stun)
			if controller.has_method("_emit_log"):
				controller._emit_log("%s 获得 %d 层眩晕。" % [target.get_display_name(), stun_stacks])


func play_on_object(context: Dictionary = {}, target: BattleObjectState = null) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or target == null or not target.can_be_damaged():
		return
	var equipment_slot := str(context.get("equipment_slot", ""))
	controller.perform_object_strike_with_modifier(
		user,
		target,
		card,
		_two_handed_bonus(user, equipment_slot),
		"猛击",
		equipment_slot
	)


func _two_handed_bonus(user: BattleUnitState, equipment_slot: String) -> int:
	if user == null:
		return 0
	var profile := user.build_strike_profile_object(equipment_slot)
	return two_handed_damage_bonus if profile.primary_equipment != null \
		and profile.primary_equipment.is_two_handed() else 0
