extends StatusEffect
class_name TrapAfterStrikeSurfaceStatus

# Diagnostic-only hook.  It changes the attacked trap's surface immediately,
# then queues a descendant that changes it again.  The observer list makes the
# complete-strike boundary visible without asserting queue internals.
var controller: BattleController
var trap: BattleObjectState
var direct_element: int = BattleSurfaceState.Element.BLAZE
var queued_element: int = BattleSurfaceState.Element.LAVA
var observations: Array[String] = []


func on_after_strike(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	observations.append("after_hook_trap_queued=%s" % str(trap != null and trap.trap_explosion_queued))
	if controller == null or trap == null:
		return
	controller.apply_advanced_surface(trap.cell, direct_element)
	controller.enqueue_effect(Callable(self, "_apply_queued_surface"), [], 0, "diagnostic queued after-strike surface")


func _apply_queued_surface() -> void:
	observations.append("queued_descendant_trap_queued=%s" % str(trap != null and trap.trap_explosion_queued))
	if controller != null and trap != null:
		controller.apply_advanced_surface(trap.cell, queued_element)
