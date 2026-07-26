extends EquipmentEffect
class_name AdventureAccessoryEffect

@export var intelligence_bonus: int = 0
@export var first_curse_armor: int = 0

const CURSE_ARMOR_TRIGGERED := "curse_armor_triggered"


func modify_attribute(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, attribute: String, current_value: int, _context: Dictionary = {}) -> int:
	if attribute == "intelligence":
		return current_value + intelligence_bonus
	return current_value


func on_after_card_played(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, card: CardData, _context: Dictionary = {}) -> void:
	if owner == null or card == null or not card.is_curse_card() or first_curse_armor <= 0:
		return
	if runtime.get_flag(CURSE_ARMOR_TRIGGERED):
		return
	runtime.set_flag(CURSE_ARMOR_TRIGGERED, true)
	owner.gain_armor(first_curse_armor, {"source": "sealed_reliquary", "card": card})
