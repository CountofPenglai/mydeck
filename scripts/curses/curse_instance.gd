extends Resource
class_name CurseInstance

enum State {
	INDUSTRY,
	REPORT,
	FRUIT,
}

@export var definition: CurseDefinition
@export_enum("业", "报", "果") var state: int = State.INDUSTRY
@export_range(1, 3, 1) var depth: int = 1
@export_range(0, 99, 1) var maturity: int = 0
@export var sealed: bool = false
@export var persistent_data: Dictionary = {}


func get_curse_id() -> String:
	return definition.curse_id if definition != null else ""


func get_display_name() -> String:
	return definition.display_name if definition != null else "未知诅咒"


func get_state_label() -> String:
	match state:
		State.INDUSTRY:
			return "业"
		State.REPORT:
			return "报"
		State.FRUIT:
			return "果"
		_:
			return "未知"


func get_load_cost() -> int:
	if sealed or state == State.INDUSTRY:
		return 0
	return clampi(depth, 1, 3)


func is_active_in_curse_zone() -> bool:
	return not sealed and (state == State.REPORT or state == State.FRUIT)


func deepen() -> bool:
	if depth >= 3:
		return false
	depth += 1
	if state == State.REPORT:
		maturity += 1
	return true


func transform_to_report() -> bool:
	if state != State.INDUSTRY:
		return false
	state = State.REPORT
	maturity = 0
	sealed = false
	return true


func add_maturity(amount: int = 1) -> bool:
	if state != State.REPORT or sealed or definition == null:
		return false
	maturity = maxi(0, maturity + amount)
	if maturity < definition.maturity_threshold:
		return false
	state = State.FRUIT
	maturity = definition.maturity_threshold
	return true


func get_summary() -> String:
	if definition == null:
		return "未知诅咒"
	var result := "%s · %s · 深度%d" % [definition.display_name, get_state_label(), depth]
	if sealed:
		result += " · 已封印"
	elif state == State.REPORT:
		result += " · 成熟%d/%d" % [maturity, definition.maturity_threshold]
	if get_load_cost() > 0:
		result += " · 负荷%d" % get_load_cost()
	return result
