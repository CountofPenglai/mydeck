extends CardEffect
class_name AttackDefenseDanceCardEffect


func _init() -> void:
	uses_strike = true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	if not (targets[0] is BattleUnitState):
		return

	var target := targets[0] as BattleUnitState
	controller.enqueue_effect(
		Callable(controller, "perform_strike"),
		[user, target, card, "攻守轮舞（第一击）", str(context.get("equipment_slot", ""))],
		effect_priority,
		"攻守轮舞：第一击",
		context
	)
	controller.enqueue_effect(
		Callable(self, "_switch_and_follow_up"),
		[controller, user, target, card, context],
		effect_priority,
		"攻守轮舞：换武追击",
		context
	)


func _switch_and_follow_up(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, context: Dictionary) -> void:
	if controller == null or user == null or card == null:
		return
	var result := controller.switch_prepared_weapon(user)
	var weapon := user.character_state.get_active_weapon_equipment() if user.character_state != null else null
	var weapon_base_damage := weapon.base_damage if weapon != null else 1
	var can_strike := bool(result.get("success", false)) and target != null and target.is_alive()
	if can_strike:
		can_strike = user.cell_distance_to(target) <= user.get_attack_range("weapon")
	if can_strike:
		controller.enqueue_effect(
			Callable(controller, "perform_strike"),
			[user, target, card, "攻守轮舞（第二击）", "weapon"],
			effect_priority,
			"攻守轮舞：第二击",
			context
		)
		return

	user.gain_armor(weapon_base_damage, context)
	controller._emit_log("%s 的攻守轮舞转入防守，获得 %d 护甲。" % [user.get_display_name(), weapon_base_damage])
