extends CardEffect
class_name DamageCardEffect

@export var damage_amount: int = 4
@export var add_damage_bonus: bool = true

func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	if controller == null or user == null:
		return

	var total_damage := damage_amount
	if add_damage_bonus and user.has_method("get_damage_bonus"):
		total_damage += user.get_damage_bonus()

	for target in targets:
		if target != null and controller.has_method("apply_damage"):
			controller.apply_damage(user, target, total_damage, "卡牌伤害")
