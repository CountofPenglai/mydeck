extends Resource
class_name CurseDefinition

@export var curse_id: String = ""
@export var display_name: String = "未命名诅咒"
@export var is_boss_curse: bool = false
@export_range(2, 4, 1) var maturity_threshold: int = 3
@export_multiline var industry_description: String = ""
@export_multiline var report_description: String = ""
@export_multiline var fruit_description: String = ""
@export var hex_keywords: PackedStringArray = []
@export var industry_card: CardData
@export var effect: CurseEffect


func get_description_for_state(state: int) -> String:
	match state:
		CurseInstance.State.INDUSTRY:
			return industry_description
		CurseInstance.State.REPORT:
			return report_description
		CurseInstance.State.FRUIT:
			return fruit_description
		_:
			return ""


func is_valid_definition() -> bool:
	return not curse_id.is_empty() and industry_card != null and effect != null
