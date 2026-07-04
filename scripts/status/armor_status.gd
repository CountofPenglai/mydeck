extends StatusEffect
class_name ArmorStatus


func _init() -> void:
	status_id = "armor"
	display_name = "护甲"


func on_before_damage(unit: BattleUnitState, damage_context: DamageContext) -> void:
	if unit == null or damage_context == null or stacks <= 0 or damage_context.amount <= 0:
		return

	var absorbed := damage_context.reduce_amount(stacks)
	stacks = maxi(0, stacks - absorbed)

	var controller := damage_context.controller
	if controller != null and absorbed > 0:
		controller._emit_log("%s 的护甲抵挡了 %d 点伤害。" % [unit.get_display_name(), absorbed])
