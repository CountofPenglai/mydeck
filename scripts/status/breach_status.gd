extends StatusEffect
class_name BreachStatus

var applied_by: BattleUnitState
var expires_on_source_turn: int = 0
var damage_multiplier: float = 1.5


func _init() -> void:
	status_id = "breach"
	display_name = "破绽"


func modify_incoming_damage(_unit: BattleUnitState, damage_context: DamageContext) -> void:
	if stacks <= 0 or damage_context == null or damage_context.amount <= 0:
		return
	if applied_by == null or damage_context.source == null:
		return
	if damage_context.source.faction != applied_by.faction:
		return
	if applied_by.turn_serial >= expires_on_source_turn:
		return

	damage_context.amount = maxi(0, ceili(float(damage_context.amount) * damage_multiplier))
	damage_context.metadata["breach_status"] = self
	stacks = 0


func should_remove() -> bool:
	return stacks <= 0 or applied_by == null or applied_by.turn_serial >= expires_on_source_turn
