extends RefCounted
class_name AdventureContentCatalog

const EVENT_DEFINITIONS := {
	"hermit_house": {
		"title": "隐者之家", "risk": "低", "reward": "消耗品三选一",
		"summary": "林间棚屋里摆着三份贴有旧标签的药剂。隐者允许你选择一份，并指定由谁收入背包。",
		"rules": "从锁定的消耗品候选中选择 1 件。获得者的背包必须有空位。",
		"options": [{"id": "take_supply", "label": "挑选赠礼", "preview": "选择消耗品与获得者；不支付资源。"}, {"id": "leave", "label": "暂时离开", "preview": "保留事件，之后可以回访。"}],
	},
	"fallen_altar": {
		"title": "堕落圣坛", "risk": "高", "reward": "全队治疗",
		"summary": "圣坛回应每个人不同的渴望。每名冒险者都可以独立决定献上多少未来。",
		"rules": "为每名冒险者选择 x=0 至 3：恢复 10x 生命，并获得 x 个随机普通业。确认前显示最终负荷。",
		"options": [{"id": "altar_resolve", "label": "分配献祭", "preview": "一次确认全队选择；选择 0 的角色不受影响。"}, {"id": "leave", "label": "拒绝献祭", "preview": "保留事件，之后可以回访。"}],
	},
	"adventurer_remains": {
		"title": "冒险者遗骨", "risk": "中", "reward": "据点装备",
		"summary": "腐朽行囊里留着一枚身份牌。带走它会占用背包，但下一座据点会认得这位死者。",
		"rules": "遗骨占 1 个背包格。拾取后掷 d6：1-4 无事；5-6 再选择 1 名角色获得随机普通业。抵达下一座据点后可交付换取本层装备三选一。",
		"options": [{"id": "take_remains", "label": "拾取遗骨", "preview": "先选择携带者并掷 d6；只有 5-6 时才继续选择诅咒承受者。"}, {"id": "leave", "label": "不惊扰遗骨", "preview": "保留事件，之后可以回访。"}],
	},
	"the_fall": {
		"title": "堕落", "risk": "两个普通业", "reward": "职业史诗牌",
		"summary": "某种力量愿意把答案交给负荷最沉重的人，但索取的代价也会落在同一人身上。",
		"rules": "从当前未封印负荷最高的角色中选择 1 人；其获得 1 张本职业史诗牌和 2 个随机普通业。",
		"options": [{"id": "accept_fall", "label": "接受堕落", "preview": "选择合法承受者，并预览结算后的负荷。"}, {"id": "leave", "label": "拒绝力量", "preview": "保留事件，之后可以回访。"}],
	},
	"cursed_wanderer": {
		"title": "受咒游荡者", "risk": "可选", "reward": "仪式点、消耗品或随机收益",
		"summary": "游荡者不求怜悯，只把三种交易摆在你面前。选定一项后便不能改选。",
		"rules": "分担：1 个业换 2 仪式点。援助：支付 1 仪式点并从 3 件消耗品中选 1。碰运气：d6 为 6 时继续从 3 张稀有牌中选 1；3-5 获得 5 金币。",
		"options": [
			{"id": "share", "label": "分担诅咒", "preview": "选择 1 名角色获得随机普通业；团队仪式点 +2。"},
			{"id": "aid", "label": "援助游荡者", "preview": "支付 1 仪式点；选择 1 件消耗品和获得者。"},
			{"id": "gamble", "label": "碰运气", "preview": "d6：1-2 获得业；3-5 金币 +5；6 为所选角色展示稀有牌三选一。"},
			{"id": "leave", "label": "暂不交易", "preview": "保留事件，之后可以回访。"},
		],
	},
	"sealed_chapel": {
		"title": "锁闭圣堂", "risk": "精英专属战斗", "reward": "封印圣匣",
		"summary": "圣堂的门闩从内部扣死。封印圣匣仍在祭台上，但守卫也仍在那里。",
		"rules": "进入一场精英标准的专属遭遇；胜利后获得封印圣匣，不发通用精英奖励。",
		"options": [{"id": "event_battle", "label": "进入圣堂", "preview": "立即进入专属战斗，战斗中不能撤退。"}, {"id": "leave", "label": "稍后再来", "preview": "保留事件，之后可以回访。"}],
	},
	"wilderness_merchant": {
		"title": "荒野游商", "risk": "无", "reward": "六格交易库存",
		"summary": "游商把货物摊在防水布上。库存一经揭示便不会刷新，可以稍后回来继续交易。",
		"rules": "3 件消耗品、2 件当前楼层装备、1 份扎营物资；不提供删牌服务。",
		"options": [{"id": "open_shop", "label": "查看货物", "preview": "揭示并保留本房间库存。"}, {"id": "leave", "label": "离开", "preview": "库存保持不变，可以回访。"}],
	},
	"creation_ascetic": {
		"title": "造物会苦修士", "risk": "每张牌换 1 个业", "reward": "永久精简牌组",
		"summary": "苦修士愿意烧掉那些拖累你的旧习，但每一页灰烬都会留下新的债。",
		"rules": "选择同一名角色的 1 至 2 张非诅咒牌永久移除；每移除 1 张，该角色获得 1 个随机普通业。",
		"options": [{"id": "remove_card", "label": "选择要焚毁的牌", "preview": "显式选择角色与 1-2 张牌；牌组不能低于最低张数。"}, {"id": "leave", "label": "拒绝苦修", "preview": "保留事件，之后可以回访。"}],
	},
	"alchemy_lesson": {
		"title": "炼金术实践教学", "risk": "付费 d6", "reward": "金币或史诗牌",
		"summary": "炼金师把坩埚和骰子一并推来。低点数几乎血本无归，高点数则足以改变牌组。",
		"rules": "1-3 获得 1 金；4-5 获得 40 金；首次 6 为所选角色展示史诗牌三选一，之后的 6 获得 60 金。4-6 令以后费用 +10。",
		"options": [{"id": "alchemy_roll", "label": "支付并投掷", "preview": "当前费用会显示在按钮上；结果由事件随机流锁定。"}, {"id": "leave", "label": "停止实验", "preview": "保留当前价格和参与次数，可以回访。"}],
	},
	"nature_blessing": {
		"title": "大自然的恩惠", "risk": "超负荷者失血", "reward": "恢复与诅咒处理",
		"summary": "生长并不区分治愈与剥落。枝叶会抚平尚有余地的人，也会撕开负荷已满的伤口。",
		"rules": "负荷达到上限者失去 10% 最大生命，并选择移除 1 个业或令 1 个报成熟 +1；其他角色恢复 10%。",
		"options": [{"id": "nature_resolve", "label": "接受恩惠", "preview": "为每名超负荷角色选择可用的诅咒处理方式后统一结算。"}],
	},
	"trapped_arcanist": {
		"title": "受困的奥术师", "risk": "专属战斗", "reward": "负荷上限 +2 或奥能坠饰",
		"summary": "奥术师被困在失控的法阵中央。救援成功后，他会用知识或饰品偿还人情。",
		"rules": "胜利后选择：指定 1 名角色本次冒险负荷上限 +2；或获得智力 +2 的奥能坠饰。",
		"options": [{"id": "event_battle", "label": "援助奥术师", "preview": "立即进入专属战斗；胜利后继续选择回报。"}, {"id": "leave", "label": "稍后再来", "preview": "保留事件，之后可以回访。"}],
	},
	"master_forging": {
		"title": "大师级锻造", "risk": "精英高难战斗", "reward": "下一档装备三选一",
		"summary": "炉火只承认经受过试炼的材料。完成战斗，锻造师才会让你从成品中选择一件。",
		"rules": "胜利后从 3 件下一档装备中选择 1 件；不发通用事件战奖励。",
		"options": [{"id": "event_battle", "label": "接受锻造试炼", "preview": "立即进入专属高难战斗。"}, {"id": "leave", "label": "稍后再来", "preview": "保留事件，之后可以回访。"}],
	},
	"chaos_gate": {
		"title": "混乱之门", "risk": "不可撤退的高难战斗", "reward": "下一档装备与全员职业牌",
		"summary": "门后的馈赠先于危险抵达。只要接受，奖励选择与随后的战斗就会成为同一笔不可撤销的交易。",
		"rules": "先选下一档装备，再让每名冒险者各选 1 张职业牌；随后立即进入专属战斗，战败则冒险结束。",
		"options": [{"id": "event_battle", "label": "穿过混乱之门", "preview": "完整奖励选择后强制开战，不能撤退或返回地图。"}, {"id": "leave", "label": "远离门扉", "preview": "保留事件，之后可以回访。"}],
	},
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
