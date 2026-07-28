extends RefCounted
class_name EnemyRuleDispatcher


static func on_battle_started(controller: BattleController) -> void:
	ChapterOneEnemyRules.on_battle_started(controller)
	ChapterTwoEnemyRules.on_battle_started(controller)


static func on_turn_started(controller: BattleController, unit: BattleUnitState) -> void:
	ChapterOneEnemyRules.on_turn_started(controller, unit)
	ChapterTwoEnemyRules.on_turn_started(controller, unit)


static func on_turn_ended(controller: BattleController, unit: BattleUnitState) -> void:
	ChapterOneEnemyRules.on_turn_ended(controller, unit)
	ChapterTwoEnemyRules.on_turn_ended(controller, unit)


static func on_card_played(controller: BattleController, unit: BattleUnitState, card: CardData) -> void:
	ChapterOneEnemyRules.on_card_played(controller, unit, card)
	ChapterTwoEnemyRules.on_card_played(controller, unit, card)


static func on_movement_completed(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	ChapterOneEnemyRules.on_movement_completed(controller, unit, context)
	ChapterTwoEnemyRules.on_movement_completed(controller, unit, context)


static func on_armor_changed(controller: BattleController, unit: BattleUnitState, previous: int, current: int) -> void:
	ChapterOneEnemyRules.on_armor_changed(controller, unit, previous, current)
	ChapterTwoEnemyRules.on_armor_changed(controller, unit, previous, current)


static func on_after_damage_dealt(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	ChapterTwoEnemyRules.on_after_damage_dealt(controller, unit, context)


static func on_after_damage_taken(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	ChapterTwoEnemyRules.on_after_damage_taken(controller, unit, context)


static func on_after_strike(controller: BattleController, unit: BattleUnitState, context: Dictionary) -> void:
	ChapterTwoEnemyRules.on_after_strike(controller, unit, context)


static func modify_agility(unit: BattleUnitState, current: int) -> int:
	return ChapterTwoEnemyRules.modify_agility(
		unit,
		ChapterOneEnemyRules.modify_agility(unit, current)
	)


static func modify_damage_bonus(unit: BattleUnitState, current: int, context: Dictionary = {}) -> int:
	return ChapterTwoEnemyRules.modify_damage_bonus(
		unit,
		ChapterOneEnemyRules.modify_damage_bonus(unit, current),
		context
	)


static func modify_damage_reduction(unit: BattleUnitState, current: int, context: Dictionary = {}) -> int:
	return ChapterTwoEnemyRules.modify_damage_reduction(unit, current, context)


static func modify_max_ap(unit: BattleUnitState, current: int) -> int:
	return ChapterTwoEnemyRules.modify_max_ap(
		unit,
		ChapterOneEnemyRules.modify_max_ap(unit, current)
	)


static func modify_move_distance(unit: BattleUnitState, current: int) -> int:
	return ChapterTwoEnemyRules.modify_move_distance(unit, current)


static func try_handle_lethal(controller: BattleController, source: BattleUnitState, target: BattleUnitState, context: Dictionary) -> bool:
	if ChapterOneEnemyRules.try_handle_lethal(controller, source, target, context):
		return true
	return ChapterTwoEnemyRules.try_handle_lethal(controller, source, target, context)


static func execute_intent_step(controller: BattleController, unit: BattleUnitState, step: Dictionary) -> bool:
	if str(step.get("type", "")) == "switch":
		return ChapterOneEnemyRules.switch_champion_weapon(
			controller,
			unit,
			_find_unit(controller, int(step.get("target_id", -1)))
		)
	return ChapterTwoEnemyRules.execute_intent_step(controller, unit, step)


static func can_take_turn(unit: BattleUnitState) -> bool:
	return not ChapterTwoEnemyRules.is_support_unit(unit)


static func _find_unit(controller: BattleController, unit_id: int) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit.unit_id == unit_id and unit.is_alive():
			return unit
	return null
