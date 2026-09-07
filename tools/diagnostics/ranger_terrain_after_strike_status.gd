extends StatusEffect
class_name RangerTerrainAfterStrikeStatus

# Test-only hook: a real after-strike status queues the surface that Tether
# must observe before its own after-strike continuation collects the target cell.
var controller: BattleController
var cell := Vector2i(-1, -1)
var ran := false

func on_after_strike(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if controller == null or cell == Vector2i(-1, -1):
		return
	controller.enqueue_effect(Callable(self, "_place_collectible_surface"), [], 0, "terrain diagnostic after-strike descendant")

func _place_collectible_surface() -> void:
	ran = true
	controller.surface_state.add_residue(cell, BattleSurfaceState.Element.FIRE, controller.battle_round)
	controller.surface_state.add_residue(cell, BattleSurfaceState.Element.WATER, controller.battle_round)
