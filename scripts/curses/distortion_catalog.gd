extends RefCounted
class_name DistortionCatalog

const GRACE_ID := "grace"
const MILESTONES = [2, 5, 8, 11]
const LOW_FIELDS = [
	"lashing",
	"empty_eye",
	"appendage",
	"bloodseeking",
	"mud_lung",
	"beast_heart",
]
const HIGH_FIELDS = [
	"rock_scale",
	"scorch_throat",
	"night_veil",
	"enlightenment",
	"irradiation",
	"stampede",
]

const FIELD_DATA := {
	"lashing": {
		"name": "鞭笞",
		"tier": 0,
		"description": "每回合一次，临时失去1至3点伤害加值，获得等量攻击范围。",
	},
	"empty_eye": {
		"name": "空目",
		"tier": 0,
		"description": "每轮首次成为敌方单目标手牌目标时反制该牌，随后承受施放者属性伤害。",
	},
	"appendage": {
		"name": "附肢",
		"tier": 0,
		"description": "手牌完整结算后，对该牌指定过的每个存活敌人造成1点固定伤害。",
	},
	"bloodseeking": {
		"name": "觅血",
		"tier": 0,
		"description": "主动移动、特殊移动或转移后，下一张手牌必须为攻击牌且AP消耗-1。",
	},
	"mud_lung": {
		"name": "泥肺",
		"tier": 0,
		"description": "每次成功获得一个负面状态时恢复2点生命。",
	},
	"beast_heart": {
		"name": "兽心",
		"tier": 0,
		"description": "抽牌行动改为抽3；每张手牌结算后随机弃1张牌并获得1咒波。",
	},
	"rock_scale": {
		"name": "岩鳞",
		"tier": 1,
		"description": "每轮首次失去最后一张手牌时获得1层抵挡，并可消耗至多2咒波获得护甲。",
	},
	"scorch_throat": {
		"name": "灼喉",
		"tier": 1,
		"description": "极限距离武器打击在目标格施加火；可消耗2咒波扩散到相邻格。",
	},
	"night_veil": {
		"name": "披夜",
		"tier": 1,
		"description": "造成正数伤害前不能成为其他单位手牌目标；破除时可消耗咒波强化伤害。",
	},
	"enlightenment": {
		"name": "启明",
		"tier": 1,
		"description": "抽牌行动后若有咒波，消耗1点再抽1张。",
	},
	"irradiation": {
		"name": "辐照",
		"tier": 1,
		"description": "回合开始时令范围2内其他单位获得异常，并按受影响单位数获得至多3咒波。",
	},
	"stampede": {
		"name": "奔踏",
		"tier": 1,
		"description": "有效敏捷增加当前力量；每回合首次移动后根据咒波对周围所有单位造成敏捷伤害。",
	},
}


static func is_valid_field(field_id: String) -> bool:
	return FIELD_DATA.has(field_id)


static func get_display_name(field_id: String) -> String:
	if field_id == GRACE_ID:
		return "恩典"
	var data: Dictionary = FIELD_DATA.get(field_id, {}) as Dictionary
	return str(data.get("name", field_id))


static func get_description(field_id: String) -> String:
	if field_id == GRACE_ID:
		return "力量、敏捷、智力各永久+1；最大生命提高时同步恢复等量生命。"
	var data: Dictionary = FIELD_DATA.get(field_id, {}) as Dictionary
	return str(data.get("description", ""))


static func get_tier(field_id: String) -> int:
	var data: Dictionary = FIELD_DATA.get(field_id, {}) as Dictionary
	return int(data.get("tier", -1))


static func get_fields_for_milestone_index(milestone_index: int) -> PackedStringArray:
	return PackedStringArray(LOW_FIELDS if milestone_index < 2 else HIGH_FIELDS)


static func get_options_for_tier(milestone_index: int, excluded: PackedStringArray, seed: int) -> PackedStringArray:
	var candidates := get_fields_for_milestone_index(milestone_index)
	var available := PackedStringArray()
	for field_id in candidates:
		if not excluded.has(field_id):
			available.append(field_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shuffled: Array[String] = []
	for field_id in available:
		shuffled.append(field_id)
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = value
	var result := PackedStringArray()
	for index in range(mini(3, shuffled.size())):
		result.append(shuffled[index])
	return result
