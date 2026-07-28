extends RefCounted
class_name CharacterClassDefaults

static func get_resource_pools(character_class: int) -> Array[ResourcePoolData]:
	match character_class:
		CardEnums.CardClass.WARRIOR:
			return [_pool("势", 5, 1)]
		CardEnums.CardClass.MAGE:
			return []
		CardEnums.CardClass.RANGER:
			return [_pool("专注", 5, 2)]
		CardEnums.CardClass.DRUID:
			return []
		CardEnums.CardClass.WARLOCK:
			return []
		_:
			return []


static func _pool(pool_name: String, max_value: int, initial_value: int) -> ResourcePoolData:
	var data := ResourcePoolData.new()
	data.pool_name = pool_name
	data.max_value = max_value
	data.initial_value = initial_value
	return data
