extends CardEffect
class_name DamageCardEffect

@export var damage_amount: int = 4
@export var add_damage_bonus: bool = true

func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	var card: CardData = context.get("card") as CardData
	var ranger_attack_multiplier := 1.0
	if user.is_ranger() and user.is_stealthed() and card != null and card.is_attack_card():
		ranger_attack_multiplier = controller.consume_ranger_stealth_for_attack(user)

	for target in targets:
		if target != null and controller.has_method("apply_damage"):
			var total_damage := damage_amount
			if add_damage_bonus and user.has_method("get_damage_bonus"):
				total_damage += user.get_damage_bonus({
					"controller": controller,
					"source": self,
					"card": context.get("card"),
					"target": target,
				})
				if user.has_method("remove_expired_statuses"):
					user.remove_expired_statuses()
			total_damage = ceili(float(total_damage) * ranger_attack_multiplier)
			controller.apply_damage(user, target, total_damage, "卡牌伤害")
