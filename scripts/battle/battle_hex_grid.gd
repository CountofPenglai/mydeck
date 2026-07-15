extends RefCounted
class_name BattleHexGrid

const INVALID_CELL := Vector2i(-1, -1)
const SQRT_THREE := 1.7320508075688772
const AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func offset_to_axial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x - (cell.y - (cell.y & 1)) / 2, cell.y)


static func axial_to_offset(axial: Vector2i) -> Vector2i:
	return Vector2i(axial.x + (axial.y - (axial.y & 1)) / 2, axial.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var axial_a := offset_to_axial(a)
	var axial_b := offset_to_axial(b)
	var delta_q := axial_a.x - axial_b.x
	var delta_r := axial_a.y - axial_b.y
	return maxi(abs(delta_q), maxi(abs(delta_r), abs(delta_q + delta_r)))


static func cell_to_map(cell: Vector2i, hex_size: float, origin: Vector2) -> Vector2:
	var x := hex_size * SQRT_THREE * (float(cell.x) + 0.5 * float(cell.y & 1))
	var y := hex_size * 1.5 * float(cell.y)
	return origin + Vector2(x, y)


static func map_to_cell(map_position: Vector2, hex_size: float, origin: Vector2) -> Vector2i:
	if hex_size <= 0.0:
		return INVALID_CELL
	var local := map_position - origin
	var axial_q := (SQRT_THREE / 3.0 * local.x - local.y / 3.0) / hex_size
	var axial_r := (2.0 / 3.0 * local.y) / hex_size
	return axial_to_offset(_round_axial(Vector2(axial_q, axial_r)))


static func polygon(cell: Vector2i, hex_size: float, origin: Vector2) -> PackedVector2Array:
	var center := cell_to_map(cell, hex_size, origin)
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index) - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
	return points


static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var steps := distance(a, b)
	if steps <= 0:
		result.append(a)
		return result

	var axial_a := offset_to_axial(a)
	var axial_b := offset_to_axial(b)
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var interpolated := Vector2(
			lerpf(float(axial_a.x), float(axial_b.x), t),
			lerpf(float(axial_a.y), float(axial_b.y), t)
		)
		var cell := axial_to_offset(_round_axial(interpolated))
		if result.is_empty() or result.back() != cell:
			result.append(cell)
	return result


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var axial := offset_to_axial(cell)
	var result: Array[Vector2i] = []
	for direction in AXIAL_DIRECTIONS:
		result.append(axial_to_offset(axial + direction))
	return result


static func direction_index(origin: Vector2i, target: Vector2i) -> int:
	if origin == target:
		return -1
	var path := line(origin, target)
	if path.size() < 2:
		return -1
	var delta := offset_to_axial(path[1]) - offset_to_axial(origin)
	return AXIAL_DIRECTIONS.find(delta)


static func _round_axial(axial: Vector2) -> Vector2i:
	var x := axial.x
	var z := axial.y
	var y := -x - z
	var rounded_x := roundi(x)
	var rounded_y := roundi(y)
	var rounded_z := roundi(z)
	var x_diff: float = absf(float(rounded_x) - x)
	var y_diff: float = absf(float(rounded_y) - y)
	var z_diff: float = absf(float(rounded_z) - z)
	if x_diff > y_diff and x_diff > z_diff:
		rounded_x = -rounded_y - rounded_z
	elif y_diff > z_diff:
		rounded_y = -rounded_x - rounded_z
	else:
		rounded_z = -rounded_x - rounded_y
	return Vector2i(rounded_x, rounded_z)
