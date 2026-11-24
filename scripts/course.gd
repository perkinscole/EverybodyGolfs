extends Node3D
## One hand-laid golf hole: heights on a one-metre grid, surfaces (fairway,
## sand, path...) on a half-metre grid so their edges are finer.
## The ball and player query the same height/surface data the mesh is built
## from. Trees, props and the clubhouse are added by scenery.gd/clubhouse.gd.

const Blocks = preload("res://scripts/blocks.gd")
const Scenery = preload("res://scripts/scenery.gd")
const Clubhouse = preload("res://scripts/clubhouse.gd")

enum Surface { ROUGH, FAIRWAY, GREEN, BUNKER, TEE, WATER, PATH }

const CELL := 1.0
const SUB := 2          # surface cells per metre
const X_MIN := -100.0
const X_MAX := 120.0
const Z_MIN := -420.0
const Z_MAX := 80.0
const PAR := 4
const CUP_RADIUS := 0.14

var tee := Vector2(0, 0)
var pin := Vector2(40, -335)
var clubhouse := Vector2(16, 50)
var fairway := PackedVector2Array([
	Vector2(0, -45), Vector2(0, -120), Vector2(25, -230), Vector2(38, -312)])
var fairway_half_width := 16.0
var green_radius := 13.0
## Each bunker is [centre, radii].
var bunkers := [
	[Vector2(19, -317), Vector2(6, 4)],
	[Vector2(58, -338), Vector2(5, 7)],
	[Vector2(-15, -148), Vector2(7, 5)],
	[Vector2(30, -203), Vector2(5, 4)],
]
## The river runs right across the hole; the pond is a wide spot on it.
var river := PackedVector2Array([
	Vector2(-100, -150), Vector2(-60, -165), Vector2(-25, -178), Vector2(5, -170),
	Vector2(40, -180), Vector2(80, -168), Vector2(120, -175)])
var river_half_width := 3.5
var pond_center := Vector2(-42, -171)
var pond_radii := Vector2(13, 9)
var water_y := 0.0
## Clubhouse door to the green, crossing the river on the bridge.
var cart_path := PackedVector2Array([
	Vector2(16, 41.5), Vector2(10, 12), Vector2(9, -8), Vector2(22, -55),
	Vector2(23, -120), Vector2(36, -150), Vector2(38, -166), Vector2(38, -193),
	Vector2(48, -218), Vector2(56, -262), Vector2(59, -305), Vector2(57, -321)])
var path_half_width := 1.4
var bridge_center := Vector2(38, -179.5)
var bridge_half := Vector2(1.7, 7.0)
var bridge_top := 0.0
var clubhouse_floor := 0.0
## Each tree: {pos, trunk_r, trunk_h, canopy_c, canopy_r}. Filled by scenery.
var trees: Array = []
var scenery: Node3D

var _nx := 0
var _nz := 0
var _h := PackedFloat32Array()
var _surf := PackedByteArray()
var _sw := 0
var _noise := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _tee_h := 0.0
var _green_h := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.008
	_noise.seed = 7
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.014
	_forest.seed = 99
	_rng.seed = 1234
	_tee_h = _hills(tee)
	clubhouse_floor = _hills(clubhouse)
	_green_h = _hills(pin)
	var total := 0.0
	for p in river:
		total += _hills(p)
	water_y = total / river.size() - 1.0
	bridge_top = water_y + 0.6
	_build_heights()
	_build_terrain()

	scenery = Scenery.new()
	scenery.course = self
	add_child(scenery)
	var house := Clubhouse.new()
	house.position = Vector3(clubhouse.x, clubhouse_floor, clubhouse.y)
	add_child(house)


# ---------------------------------------------------------------- queries

func hole_length() -> float:
	var d := tee.distance_to(fairway[1])
	for i in range(1, fairway.size() - 1):
		d += fairway[i].distance_to(fairway[i + 1])
	return d + fairway[fairway.size() - 1].distance_to(pin)


func height_at(x: float, z: float) -> float:
	var gx := clampf((x - X_MIN) / CELL, 0.0, _nx - 1.001)
	var gz := clampf((z - Z_MIN) / CELL, 0.0, _nz - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := _h[j * _nx + i]
	var b := _h[j * _nx + i + 1]
	var c := _h[(j + 1) * _nx + i]
	var d := _h[(j + 1) * _nx + i + 1]
	# Same triangle split as the mesh, so the ball sits exactly on it.
	if fx + fz <= 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	return Vector3(
		height_at(x - e, z) - height_at(x + e, z),
		2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()


func surface_at(x: float, z: float) -> int:
	var i := clampi(int((x - X_MIN) * SUB), 0, _sw - 1)
	var j := clampi(int((z - Z_MIN) * SUB), 0, (_nz - 1) * SUB - 1)
	return _surf[j * _sw + i]


## Top of the bridge deck above this spot, or -INF where there is no bridge.
func deck_at(x: float, z: float) -> float:
	if absf(x - bridge_center.x) < bridge_half.x and absf(z - bridge_center.y) < bridge_half.y:
		return bridge_top
	return -INF


func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	return x > X_MIN + margin and x < X_MAX - margin \
		and z > Z_MIN + margin and z < Z_MAX - margin


func ground_point(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)


func nearest_fairway_point(p: Vector2) -> Vector2:
	var best := fairway[0]
	var best_d := INF
	for i in range(fairway.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, fairway[i], fairway[i + 1])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


## Metres to the water's edge: negative in the river or pond.
func water_distance(p: Vector2) -> float:
	var d := dist_polyline(p, river) - river_half_width
	var e := (_ellipse(p, pond_center, pond_radii) - 1.0) * minf(pond_radii.x, pond_radii.y)
	return minf(d, e)


## > 0 in woodland, < 0 in open meadow.
func forest_at(p: Vector2) -> float:
	return _forest.get_noise_2d(p.x, p.y)


func dist_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in range(line.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(q))
	return best


# ---------------------------------------------------------------- terrain

func _hills(p: Vector2) -> float:
	var amp := lerpf(0.55, 1.0, smoothstep(fairway_half_width,
		fairway_half_width + 25.0, dist_polyline(p, fairway)))
	return _noise.get_noise_2d(p.x, p.y) * 7.0 * amp


func _raw_height(p: Vector2) -> float:
	var h := _hills(p) + _noise.get_noise_2d(p.x * 5.0 + 500.0, p.y * 5.0) * 0.35
	h = _flatten(h, p.distance_to(tee), 6.0, 16.0, _tee_h)
	h = _flatten(h, p.distance_to(clubhouse), 14.0, 27.0, clubhouse_floor)
	# Greens keep a gentle tilt so putts break.
	var g := p - pin
	if g.length() < green_radius + 10.0:
		var green_target := _green_h + g.x * 0.018 + g.y * 0.012 \
			+ _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.12
		h = _flatten(h, g.length(), green_radius, green_radius + 10.0, green_target)
	# River valley: level banks, then the bed.
	var wd := water_distance(p)
	if wd < 14.0:
		h = lerpf(h, water_y + 0.45, 1.0 - smoothstep(1.5, 14.0, wd))
		h = lerpf(h, water_y - 1.4, 1.0 - smoothstep(-2.0, 0.6, wd))
	for b in bunkers:
		h -= 0.7 * (1.0 - smoothstep(0.3, 1.0, _ellipse(p, b[0], b[1])))
	return h


func _flatten(h: float, dist: float, r_in: float, r_out: float, target: float) -> float:
	return lerpf(h, target, 1.0 - smoothstep(r_in, r_out, dist))


func _ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	return Vector2((p.x - c.x) / r.x, (p.y - c.y) / r.y).length()


func _build_heights() -> void:
	_nx = int((X_MAX - X_MIN) / CELL) + 1
	_nz = int((Z_MAX - Z_MIN) / CELL) + 1
	_h.resize(_nx * _nz)
	for j in _nz:
		for i in _nx:
			_h[j * _nx + i] = _raw_height(Vector2(X_MIN + i * CELL, Z_MIN + j * CELL))


func _cell_surface(p: Vector2, centre_h: float) -> int:
	if centre_h < water_y and water_distance(p) < 0.6:
		return Surface.WATER
	for b in bunkers:
		if _ellipse(p, b[0], b[1]) < 1.0:
			return Surface.BUNKER
	var pin_d := p.distance_to(pin)
	if pin_d < green_radius:
		return Surface.GREEN
	if absf(p.x - tee.x) < 3.0 and absf(p.y - tee.y) < 3.0:
		return Surface.TEE
	if pin_d < green_radius + 5.0 or dist_polyline(p, fairway) < fairway_half_width:
		return Surface.FAIRWAY
	if dist_polyline(p, cart_path) < path_half_width:
		return Surface.PATH
	return Surface.ROUGH


func _tile_materials() -> Array:
	var none := Color.BLACK
	return [
		Blocks.mat("t_rough_a", Color(0.16, 0.36, 0.12), 0.035, "grass", Color(0.24, 0.47, 0.16), 1.0, false),
		Blocks.mat("t_rough_b", Color(0.15, 0.34, 0.12), 0.035, "grass", Color(0.21, 0.43, 0.15), 1.0, false),
		Blocks.mat("t_rough_c", Color(0.17, 0.37, 0.13), 0.035, "grass", Color(0.27, 0.49, 0.19), 1.0, false),
		Blocks.mat("t_forest_a", Color(0.12, 0.27, 0.10), 0.035, "spots", Color(0.26, 0.22, 0.12), 1.0, false),
		Blocks.mat("t_forest_b", Color(0.13, 0.28, 0.11), 0.035, "grass", Color(0.19, 0.36, 0.13), 1.0, false),
		Blocks.mat("t_fairway_a", Color(0.33, 0.60, 0.22), 0.02, "grass", Color(0.36, 0.64, 0.24), 1.0, false),
		Blocks.mat("t_fairway_b", Color(0.38, 0.66, 0.25), 0.02, "grass", Color(0.41, 0.70, 0.27), 1.0, false),
		Blocks.mat("t_green_a", Color(0.45, 0.77, 0.32), 0.012, "noise", none, 1.0, false),
		Blocks.mat("t_green_b", Color(0.48, 0.80, 0.34), 0.012, "noise", none, 1.0, false),
		Blocks.mat("t_sand", Color(0.88, 0.80, 0.56), 0.03, "sand", none, 1.0, false),
		Blocks.mat("t_tee", Color(0.42, 0.72, 0.30), 0.015, "noise", none, 1.0, false),
		Blocks.mat("t_bed", Color(0.36, 0.30, 0.20), 0.04, "pebbles", Color(0.46, 0.44, 0.40), 1.0, false),
		Blocks.mat("t_gravel", Color(0.60, 0.57, 0.52), 0.05, "pebbles", Color(0.66, 0.64, 0.60), 1.0, false),
	]


## Which texture a surface cell gets; (i, j) are its half-metre cell indices.
func _tile_for(surface: int, p: Vector2, i: int, j: int) -> int:
	match surface:
		Surface.FAIRWAY:
			return 5 if posmod(int(floor((p.x + p.y) / 8.0)), 2) == 0 else 6
		Surface.GREEN:
			return 7 if posmod(int(floor(p.x / 3.0)) + int(floor(p.y / 3.0)), 2) == 0 else 8
		Surface.BUNKER: return 9
		Surface.TEE: return 10
		Surface.WATER: return 11
		Surface.PATH: return 12
	var pick := ((i >> 1) * 73856093 ^ (j >> 1) * 19349663) & 0xffff
	if forest_at(p) > 0.12:
		return 3 + pick % 2
	return pick % 3


func _build_terrain() -> void:
	var mats := _tile_materials()
	var verts: Array = []
	var normals: Array = []
	var uvs: Array = []
	var indices: Array = []
	for t in mats.size() + 1:      # last slot is the water sheet
		verts.append(PackedVector3Array())
		normals.append(PackedVector3Array())
		uvs.append(PackedVector2Array())
		indices.append(PackedInt32Array())
	var water_slot := mats.size()
	var cw := _nx - 1
	var cd := _nz - 1

	# Classify at one metre first...
	var coarse := PackedByteArray()
	coarse.resize(cw * cd)
	for j in cd:
		for i in cw:
			var avg := (_h[j * _nx + i] + _h[j * _nx + i + 1]
				+ _h[(j + 1) * _nx + i] + _h[(j + 1) * _nx + i + 1]) * 0.25
			coarse[j * cw + i] = _cell_surface(
				Vector2(X_MIN + (i + 0.5) * CELL, Z_MIN + (j + 0.5) * CELL), avg)

	# ...then split only the cells that sit on a boundary into half metres.
	_sw = cw * SUB
	_surf.resize(_sw * cd * SUB)
	var half := CELL / SUB
	for j in cd:
		for i in cw:
			var x0 := X_MIN + i * CELL
			var z0 := Z_MIN + j * CELL
			var surface := coarse[j * cw + i]
			var on_edge := (i > 0 and coarse[j * cw + i - 1] != surface) \
				or (i < cw - 1 and coarse[j * cw + i + 1] != surface) \
				or (j > 0 and coarse[(j - 1) * cw + i] != surface) \
				or (j < cd - 1 and coarse[(j + 1) * cw + i] != surface)
			var ha := _h[j * _nx + i]
			var hb := _h[j * _nx + i + 1]
			var hc := _h[(j + 1) * _nx + i]
			var hd := _h[(j + 1) * _nx + i + 1]
			if not on_edge:
				for sj in SUB:
					for si in SUB:
						_surf[(j * SUB + sj) * _sw + i * SUB + si] = surface
				var t := _tile_for(surface, Vector2(x0 + 0.5, z0 + 0.5), i * SUB, j * SUB)
				_quad(verts[t], normals[t], uvs[t], indices[t],
					Vector3(x0, ha, z0), Vector3(x0 + CELL, hb, z0),
					Vector3(x0, hc, z0 + CELL), Vector3(x0 + CELL, hd, z0 + CELL))
			else:
				for sj in SUB:
					for si in SUB:
						var x := x0 + si * half
						var z := z0 + sj * half
						var mid := Vector2(x + half * 0.5, z + half * 0.5)
						var fine := _cell_surface(mid, height_at(mid.x, mid.y))
						_surf[(j * SUB + sj) * _sw + i * SUB + si] = fine
						var t := _tile_for(fine, mid, i * SUB + si, j * SUB + sj)
						_quad(verts[t], normals[t], uvs[t], indices[t],
							Vector3(x, height_at(x, z), z),
							Vector3(x + half, height_at(x + half, z), z),
							Vector3(x, height_at(x, z + half), z + half),
							Vector3(x + half, height_at(x + half, z + half), z + half))
			if minf(minf(ha, hb), minf(hc, hd)) < water_y \
					and water_distance(Vector2(x0 + 0.5, z0 + 0.5)) < 2.0:
				_quad(verts[water_slot], normals[water_slot], uvs[water_slot], indices[water_slot],
					Vector3(x0, water_y, z0), Vector3(x0 + CELL, water_y, z0),
					Vector3(x0, water_y, z0 + CELL), Vector3(x0 + CELL, water_y, z0 + CELL))

	mats.append(Blocks.mat("t_water", Color(0.20, 0.47, 0.78, 0.78), 0.035, "water",
		Color(0.42, 0.68, 0.92), 1.0, false))
	var mesh := ArrayMesh.new()
	for t in mats.size():
		if verts[t].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts[t]
		arrays[Mesh.ARRAY_NORMAL] = normals[t]
		arrays[Mesh.ARRAY_TEX_UV] = uvs[t]
		arrays[Mesh.ARRAY_INDEX] = indices[t]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[t])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = _nx
	shape.map_depth = _nz
	shape.map_data = _h
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3((X_MIN + X_MAX) * 0.5, 0.0, (Z_MIN + Z_MAX) * 0.5)
	add_child(body)


func _quad(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var base := verts.size()
	var n := (c - a).cross(b - a).normalized()
	for v in [a, b, c, d]:
		verts.append(v)
		normals.append(n)
		uvs.append(Vector2(v.x, v.z))
	indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
