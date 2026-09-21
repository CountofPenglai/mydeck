extends RefCounted
class_name AdventureShopStockFactory

static func initial_stock(run: PartyRunState, rng: RandomNumberGenerator) -> Array[Dictionary]:
	return AdventureRewardService.new().generate_shop_stock(run, rng)

static func restock_item(run: PartyRunState, rng: RandomNumberGenerator) -> Dictionary:
	var candidates := initial_stock(run, rng)
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)
