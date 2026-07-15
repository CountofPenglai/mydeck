extends Resource
class_name PartyRunState

const STARTING_RITUAL_POINTS := 3
const MIN_RITUAL_DEBT := -2

@export var ritual_points: int = STARTING_RITUAL_POINTS


func gain_ritual_points(amount: int) -> int:
	var actual := maxi(0, amount)
	ritual_points += actual
	return actual


func can_pay_ritual(cost: int, resolves_overload: bool = false) -> bool:
	if cost <= 0:
		return true
	if ritual_points < 0:
		return false
	if ritual_points >= cost:
		return true
	return resolves_overload and ritual_points - cost >= MIN_RITUAL_DEBT


func pay_ritual(cost: int, resolves_overload: bool = false) -> bool:
	if not can_pay_ritual(cost, resolves_overload):
		return false
	ritual_points -= maxi(0, cost)
	return true
