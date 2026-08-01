extends StatusEffect
class_name AbyssSharedArmorStatus

const RUNTIME_KEY := "abyss_shared_armor"

var boss_unit_id: int = -1


func _init() -> void:
	status_id = "abyss_shared_armor"
	display_name = "共有护甲"
	effect_priority = -10


func on_before_damage(unit: BattleUnitState, damage_context: DamageContext) -> void:
	if unit == null or damage_context == null or damage_context.amount <= 0 \
			or bool(damage_context.metadata.get("ignore_armor", false)):
		return
	var controller := damage_context.controller
	var boss := _find_boss(controller)
	if boss == null or boss.enemy_state == null:
		return
	var remaining := maxi(0, int(boss.enemy_state.runtime_state.get(RUNTIME_KEY, 0)))
	if remaining <= 0:
		return
	var absorbed := damage_context.reduce_amount(remaining)
	if absorbed <= 0:
		return
	remaining -= absorbed
	boss.enemy_state.runtime_state[RUNTIME_KEY] = remaining
	ChapterOneEnemyRules.sync_abyss_shared_armor(controller, remaining)
	controller._emit_log("共有护甲为 %s 抵挡了 %d 点伤害，剩余 %d。" % [
		unit.get_display_name(), absorbed, remaining,
	])
	if remaining <= 0:
		ChapterOneEnemyRules.break_abyss_shared_armor(controller, boss)


func _find_boss(controller: BattleController) -> BattleUnitState:
	if controller == null:
		return null
	for unit in controller.enemy_units:
		if unit != null and unit.unit_id == boss_unit_id:
			return unit
	return null
