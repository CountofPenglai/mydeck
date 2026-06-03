extends CardEffect
class_name SlamCardEffect

@export var shield_tag: String = "盾牌"
@export_range(0, 99, 1) var stun_stacks: int = 2

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

		controller.perform_strike(user, target, card, "打击", str(context.get("weapon_slot", "")))
		if target.is_alive() and user.has_equipment_tag(shield_tag):
			var stun := StunStatus.new()
			stun.stacks = stun_stacks
			target.add_status(stun)
			if controller.has_method("_emit_log"):
				controller._emit_log("%s 获得 %d 层眩晕。" % [target.get_display_name(), stun_stacks])
