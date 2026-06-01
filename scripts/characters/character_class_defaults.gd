extends RefCounted
class_name CharacterClassDefaults

static func get_resource_pools(character_class: int) -> Array[ResourcePoolData]:
	match character_class:
		CardEnums.CardClass.WARRIOR:
			return [_pool("怒气", 100, 0)]
		CardEnums.CardClass.MAGE:
			return [_pool("火焰法力", 3, 1), _pool("冰霜法力", 3, 1), _pool("奥术法力", 3, 1)]
		CardEnums.CardClass.RANGER:
			return [_pool("专注", 5, 2)]
		CardEnums.CardClass.DRUID:
			return [_pool("自然能量", 5, 2)]
		CardEnums.CardClass.WARLOCK:
			return [_pool("灵魂碎片", 5, 1)]
		_:
			return []


static func _pool(pool_name: String, max_value: int, initial_value: int) -> ResourcePoolData:
	var data := ResourcePoolData.new()
	data.pool_name = pool_name
	data.max_value = max_value
	data.initial_value = initial_value
	return data
