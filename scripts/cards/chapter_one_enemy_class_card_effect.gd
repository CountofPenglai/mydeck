extends CardEffect
class_name ChapterOneEnemyClassCardEffect

enum Kind {
	SLAM,
	CHARGE,
	DEFENSIVE_STANCE,
	PERILOUS_ASSAULT,
	CROSSBOW_TETHER,
	VERDANT_STRIKE,
	MOONLIGHT,
	ROOTED_INSIGHT,
	CANOPY_SHAPE,
	WILD_SHAPE,
}

@export var kind: int = Kind.SLAM


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	return user != null and user.faction == BattleUnitState.Faction.ENEMY


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null or not target.is_alive():
		return false
	if kind == Kind.MOONLIGHT:
		return true
	return target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null:
		return false
	if kind in [Kind.DEFENSIVE_STANCE, Kind.ROOTED_INSIGHT, Kind.CANOPY_SHAPE, Kind.WILD_SHAPE]:
		return targets.is_empty() or (targets.size() == 1 and targets[0] == user)
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	var target := targets[0] as BattleUnitState
	if not is_unit_target_allowed(context, target):
		return false
	var card := context.get("card") as CardData
	var allowed_range := card.get_effective_range(user) if card != null else user.get_attack_range()
	return user.cell_distance_to(target) <= allowed_range


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null:
		return
	var target := targets[0] as BattleUnitState if targets.size() == 1 and targets[0] is BattleUnitState else null
	match kind:
		Kind.SLAM:
			controller.perform_strike(user, target, card, "猛击")
			if target != null and target.is_alive() and user.get_armor_stacks() > 0:
				_apply_stun(target, 1)
		Kind.CHARGE:
			_move_toward(controller, user, target, 2)
			if target != null and target.is_alive() \
					and user.cell_distance_to(target) <= controller.get_effective_attack_range_against(user, target):
				controller.perform_strike(user, target, card, "冲锋")
		Kind.DEFENSIVE_STANCE:
			user.gain_armor(6, _context(controller, user, card))
		Kind.PERILOUS_ASSAULT:
			controller.perform_strike(user, target, card, "险步突袭")
			if target != null and user.cell_distance_to(target) <= 1:
				controller.force_move_away(user, target.cell, 1, target)
		Kind.CROSSBOW_TETHER:
			if controller.perform_strike(user, target, card, "弩索牵引") > 0 and target != null and target.is_alive():
				controller.force_move_toward(target, user.cell, 1, user)
		Kind.VERDANT_STRIKE:
			controller.perform_strike(user, target, card, "苍翠打击")
			user.gain_armor(mini(5, user.hand.size()), _context(controller, user, card))
		Kind.MOONLIGHT:
			if target != null and target.faction == user.faction:
				controller.heal_unit(user, target, 4, "月光")
			else:
				_deal_intelligence_damage(controller, user, target, card, 4, "月光")
		Kind.ROOTED_INSIGHT:
			user.draw_cards(2, controller.rng, _context(controller, user, card))
		Kind.CANOPY_SHAPE:
			user.gain_armor(6, _context(controller, user, card))
			user.draw_cards(1, controller.rng, _context(controller, user, card))
		Kind.WILD_SHAPE:
			var status := user.get_status("enemy_turn_damage_bonus") as EnemyTurnDamageBonusStatus
			if status == null:
				status = EnemyTurnDamageBonusStatus.new()
				user.add_status(status)
			status.add_stacks(2)
			user.draw_cards(1, controller.rng, _context(controller, user, card))


func _move_toward(controller: BattleController, user: BattleUnitState, target: BattleUnitState, max_steps: int) -> void:
	if target == null:
		return
	var best := user.cell
	var best_distance := user.cell_distance_to(target)
	for cell in controller.map_data.get_cells_in_range(user.cell, max_steps):
		if not controller.targeting.is_unit_cell_clear(user, cell, false):
			continue
		var distance := controller.map_data.get_distance(cell, target.cell)
		if distance < best_distance:
			best = cell
			best_distance = distance
	if best != user.cell:
		controller.apply_card_path_movement_to_cell(user, best, -1, true, "冲锋")


func _deal_intelligence_damage(
	controller: BattleController,
	user: BattleUnitState,
	target: BattleUnitState,
	card: CardData,
	base_damage: int,
	label: String
) -> int:
	if target == null:
		return 0
	var damage_type := CardEnums.DamageType.INTELLIGENCE
	var total := base_damage + user.get_damage_bonus({
		"controller": controller,
		"card": card,
		"target": target,
		"resolved_damage_type": damage_type,
	})
	return controller.apply_damage(user, target, total, label, {
		"source_card": card,
		"resolved_damage_type": damage_type,
	})


func _apply_stun(target: BattleUnitState, amount: int) -> void:
	var stun := StunStatus.new()
	stun.stacks = amount
	target.add_status(stun)


func _context(controller: BattleController, user: BattleUnitState, card: CardData) -> Dictionary:
	return {"controller": controller, "source": user, "source_card": card}
