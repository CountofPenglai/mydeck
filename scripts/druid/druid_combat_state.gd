extends RefCounted
class_name DruidCombatState


var mana: int = 0


func reset_for_battle() -> void:
	mana = 0


func get_mana() -> int:
	return maxi(0, mana)


func gain_mana(amount: int) -> int:
	var actual := maxi(0, amount)
	if actual <= 0:
		return 0
	mana = get_mana() + actual
	return actual


func can_pay_mana(amount: int) -> bool:
	return amount <= 0 or get_mana() >= amount


func pay_mana(amount: int) -> bool:
	var cost := maxi(0, amount)
	if not can_pay_mana(cost):
		return false
	mana = get_mana() - cost
	return true


func clear_mana() -> int:
	var cleared := get_mana()
	mana = 0
	return cleared


func snapshot() -> Dictionary:
	return {"mana": get_mana()}


func restore(snapshot_data: Dictionary) -> void:
	mana = maxi(0, int(snapshot_data.get("mana", 0)))
