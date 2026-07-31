extends Control
class_name BattleHudRoot

signal layout_changed(safe_rect: Rect2)

const COMPACT_WIDTH := 1100.0
const WIDE_WIDTH := 1600.0
const BOTTOM_HEIGHT_RATIO := 0.26
const BOTTOM_MIN_HEIGHT := 176.0
const BOTTOM_MAX_HEIGHT := 224.0
const WIDE_BOTTOM_MAX_WIDTH := 1560.0

var battle_scene: BattleScene
var controller: BattleController
var _compact_mode := false
var _equipment_column_count := 2

@onready var turn_order_bar: Control = %TurnOrderBar
@onready var deployment_panel: Control = %DeploymentPanel
@onready var detail_panel: Control = %DetailPanel
@onready var bottom_hud: Control = %BottomHud
@onready var menu_button: Button = %MenuButton
@onready var equipment_region: Control = %EquipmentRegion


func _ready() -> void:
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func bind_battle(scene: BattleScene, battle_controller: BattleController) -> void:
	battle_scene = scene
	controller = battle_controller
	refresh_view()


func refresh_view() -> void:
	if not is_node_ready():
		return
	_apply_responsive_layout()


func is_compact_mode() -> bool:
	return _compact_mode


func get_equipment_column_count() -> int:
	return _equipment_column_count


func get_battle_safe_rect() -> Rect2:
	if not is_node_ready():
		return Rect2(Vector2.ZERO, size)
	var bottom_top := bottom_hud.position.y
	var left_inset := 132.0 if deployment_panel.visible else 24.0
	var right_inset := 24.0
	if detail_panel.visible and not _compact_mode:
		right_inset = detail_panel.size.x + 32.0
	var top_inset := maxf(92.0, turn_order_bar.position.y + turn_order_bar.size.y + 12.0)
	return Rect2(
		Vector2(left_inset, top_inset),
		Vector2(maxf(1.0, size.x - left_inset - right_inset), maxf(1.0, bottom_top - top_inset - 8.0))
	)


func _apply_responsive_layout() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	_compact_mode = size.x < COMPACT_WIDTH
	_equipment_column_count = 1 if _compact_mode else 2

	var bottom_height := clampf(size.y * BOTTOM_HEIGHT_RATIO, BOTTOM_MIN_HEIGHT, BOTTOM_MAX_HEIGHT)
	var bottom_width := size.x - 32.0
	if size.x > WIDE_WIDTH:
		bottom_width = minf(WIDE_BOTTOM_MAX_WIDTH, size.x - 64.0)
	bottom_hud.position = Vector2((size.x - bottom_width) * 0.5, size.y - bottom_height)
	bottom_hud.size = Vector2(bottom_width, bottom_height)

	menu_button.position = Vector2(16.0, 16.0)
	menu_button.size = Vector2(72.0, 72.0)
	deployment_panel.position = Vector2(16.0, 96.0)
	deployment_panel.size = Vector2(220.0 if not _compact_mode else 188.0, minf(270.0, bottom_hud.position.y - 112.0))

	var turn_width := minf(620.0, maxf(320.0, size.x * 0.44))
	turn_order_bar.position = Vector2((size.x - turn_width) * 0.5, 12.0)
	turn_order_bar.size = Vector2(turn_width, 76.0)

	var detail_width := 300.0 if _compact_mode else clampf(size.x * 0.22, 280.0, 340.0)
	detail_panel.size = Vector2(detail_width, minf(500.0, bottom_hud.position.y - 28.0))
	detail_panel.position = Vector2(size.x - detail_width - 16.0, 16.0 if not _compact_mode else maxf(96.0, bottom_hud.position.y - detail_panel.size.y - 12.0))
	detail_panel.z_index = 30 if _compact_mode else 10

	layout_changed.emit(get_battle_safe_rect())
