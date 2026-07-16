extends RefCounted
class_name AdventureContentCatalog

const EVENT_DEFINITIONS := {
	"hermit_house": {"title": "隐者之家", "risk": "低", "reward": "消耗品", "summary": "隐者允许你从三件消耗品中带走一件。", "options": [{"id": "take_supply", "label": "接受赠礼"}, {"id": "leave", "label": "离开"}]},
	"fallen_altar": {"title": "堕落圣坛", "risk": "高", "reward": "治疗", "summary": "以随机业换取大量治疗。", "options": [{"id": "offer_1", "label": "承受1个业"}, {"id": "offer_2", "label": "承受2个业"}, {"id": "leave", "label": "拒绝"}]},
	"adventurer_remains": {"title": "冒险者遗骨", "risk": "中", "reward": "据点装备", "summary": "带走遗骨，下一座据点会给予回报。", "options": [{"id": "take_remains", "label": "拾取遗骨"}, {"id": "leave", "label": "离开"}]},
	"the_fall": {"title": "堕落", "risk": "高", "reward": "史诗卡牌", "summary": "让负荷最高者获得力量，也承担新的业。", "options": [{"id": "accept_fall", "label": "接受"}, {"id": "leave", "label": "拒绝"}]},
	"cursed_wanderer": {"title": "受咒游荡者", "risk": "中", "reward": "仪式或补给", "summary": "在分担、援助和碰运气之间选择。", "options": [{"id": "share", "label": "分担"}, {"id": "aid", "label": "援助"}, {"id": "gamble", "label": "碰运气"}]},
	"sealed_chapel": {"title": "锁闭圣堂", "risk": "精英", "reward": "封印圣匣", "summary": "挑战专属精英，夺取能扩展负荷的圣匣。", "options": [{"id": "event_battle", "label": "进入圣堂"}, {"id": "leave", "label": "稍后再来"}]},
	"wilderness_merchant": {"title": "荒野游商", "risk": "无", "reward": "交易", "summary": "打开一份不会刷新的小型库存。", "options": [{"id": "open_shop", "label": "查看货物"}, {"id": "leave", "label": "离开"}]},
	"creation_ascetic": {"title": "造物会苦修士", "risk": "高", "reward": "精简牌组", "summary": "移除非诅咒牌，并以业支付代价。", "options": [{"id": "remove_card", "label": "移除一张牌"}, {"id": "leave", "label": "离开"}]},
	"alchemy_lesson": {"title": "炼金术实践教学", "risk": "骰子", "reward": "金币或史诗", "summary": "支付当前费用并掷一枚不会被读档改变的骰子。", "options": [{"id": "alchemy_roll", "label": "支付并投掷"}, {"id": "leave", "label": "离开"}]},
	"nature_blessing": {"title": "大自然的恩惠", "risk": "负荷", "reward": "恢复与净化", "summary": "负荷过高者承受代价，其余角色获得恢复。", "options": [{"id": "nature_resolve", "label": "接受恩惠"}]},
	"trapped_arcanist": {"title": "受困的奥术师", "risk": "专属战斗", "reward": "负荷上限或饰品", "summary": "援助奥术师并在胜利后选择回报。", "options": [{"id": "event_battle", "label": "援助"}, {"id": "leave", "label": "离开"}]},
	"master_forging": {"title": "大师级锻造", "risk": "高难战斗", "reward": "下一档装备", "summary": "完成锻造试炼，取得下一档装备。", "options": [{"id": "event_battle", "label": "接受试炼"}, {"id": "leave", "label": "离开"}]},
	"chaos_gate": {"title": "混乱之门", "risk": "不可撤退", "reward": "下一档装备与卡牌", "summary": "先锁定丰厚奖励，再进入高难遭遇。", "options": [{"id": "event_battle", "label": "穿过门扉"}, {"id": "leave", "label": "离开"}]},
}


static func get_event_definition(event_id: String) -> Dictionary:
	return (EVENT_DEFINITIONS.get(event_id, {
		"title": "未知事件",
		"risk": "未知",
		"reward": "未知",
		"summary": "这处地点尚未完成记录。",
		"options": [{"id": "leave", "label": "离开"}],
	}) as Dictionary).duplicate(true)


static func get_shelter_name(shelter_type: int) -> String:
	match shelter_type:
		AdventureEnums.ShelterType.OUTPOST:
			return "边境据点"
		AdventureEnums.ShelterType.SANCTUARY:
			return "荒野圣所"
		AdventureEnums.ShelterType.ADVENTURER_CAMP:
			return "冒险者营地"
		_:
			return "避难所"
