extends Node3D
## One procedurally generated golf hole: terrain, surfaces, trees, clubhouse.
## Everything is built from code so the ball and player can query the same
## height/surface functions the mesh was made from.

enum Surface { ROUGH, FAIRWAY, GREEN, BUNKER, TEE, WATER }

const CELL := 2.0
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
	[Vector2(-15, -150), Vector2(7, 5)],
	[Vector2(34, -196), Vector2(6, 5)],
]
var pond_center := Vector2(-24, -250)
var pond_radii := Vector2(17, 12)
var water_y := 0.0
## Each tree: {pos, trunk_r, trunk_h, canopy_c, canopy_r}
var trees: Array = []

var _nx := 0
var _nz := 0
var _h := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _tee_h := 0.0
var _club_h := 0.0
var _green_h := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.008
	_noise.seed = 7
	_rng.seed = 1234
	_tee_h = _hills(tee)
	_club_h = _hills(clubhouse)
	_green_h = _hills(pin)
	water_y = _hills(pond_center) - 0.4
	_build_heights()
	_build_terrain()
	_build_water()
	_build_trees()
	_build_props()


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
	var p := Vector2(x, z)
	if _ellipse(p, pond_center, pond_radii) < 1.0 and height_at(x, z) < water_y:
		return Surface.WATER
	for b in bunkers:
		if _ellipse(p, b[0], b[1]) < 1.0:
			return Surface.BUNKER
	var pin_d := p.distance_to(pin)
	if pin_d < green_radius:
		return Surface.GREEN
	if absf(x - tee.x) < 3.0 and absf(z - tee.y) < 3.0:
		return Surface.TEE
	if pin_d < green_radius + 5.0 or _dist_polyline(p, fairway) < fairway_half_width:
		return Surface.FAIRWAY
	return Surface.ROUGH


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


# ---------------------------------------------------------------- terrain

func _hills(p: Vector2) -> float:
	var amp := lerpf(0.55, 1.0, smoothstep(fairway_half_width,
		fairway_half_width + 25.0, _dist_polyline(p, fairway)))
	return _noise.get_noise_2d(p.x, p.y) * 7.0 * amp


func _raw_height(p: Vector2) -> float:
	var h := _hills(p) + _noise.get_noise_2d(p.x * 5.0 + 500.0, p.y * 5.0) * 0.35
	h = _flatten(h, p.distance_to(tee), 6.0, 16.0, _tee_h)
	h = _flatten(h, p.distance_to(clubhouse), 13.0, 26.0, _club_h)
	# Greens keep a gentle tilt so putts break.
	var g := p - pin
	var green_target := _green_h + g.x * 0.018 + g.y * 0.012 \
		+ _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.12
	h = _flatten(h, g.length(), green_radius, green_radius + 10.0, green_target)
	# Pond: level the banks, then dig the bowl.
	var pd := _ellipse(p, pond_center, pond_radii)
	h = lerpf(h, water_y + 0.4, 1.0 - smoothstep(1.1, 1.7, pd))
	h = lerpf(h, water_y - 1.6, 1.0 - smoothstep(0.45, 1.0, pd))
	for b in bunkers:
		h -= 0.7 * (1.0 - smoothstep(0.3, 1.0, _ellipse(p, b[0], b[1])))
	return h


func _flatten(h: float, dist: float, r_in: float, r_out: float, target: float) -> float:
	return lerpf(h, target, 1.0 - smoothstep(r_in, r_out, dist))


func _ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	return Vector2((p.x - c.x) / r.x, (p.y - c.y) / r.y).length()


func _dist_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in range(line.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(q))
	return best


func _build_heights() -> void:
	_nx = int((X_MAX - X_MIN) / CELL) + 1
	_nz = int((Z_MAX - Z_MIN) / CELL) + 1
	_h.resize(_nx * _nz)
	for j in _nz:
		for i in _nx:
			_h[j * _nx + i] = _raw_height(Vector2(X_MIN + i * CELL, Z_MIN + j * CELL))


func _surface_color(s: int, cx: float, cz: float) -> Color:
	var c := Color(0.12, 0.29, 0.10)
	match s:
		Surface.FAIRWAY:
			c = Color(0.35, 0.61, 0.23)
			if posmod(int(floor((cx + cz) / 9.0)), 2) == 0:
				c = c.lightened(0.07)
		Surface.GREEN:
			c = Color(0.46, 0.76, 0.33)
		Surface.BUNKER:
			c = Color(0.88, 0.80, 0.56)
		Surface.TEE:
			c = Color(0.42, 0.70, 0.30)
		Surface.WATER:
			c = Color(0.28, 0.27, 0.18)
	var j := _rng.randf_range(-0.03, 0.03)
	return Color(c.r + j, c.g + j, c.b + j)


func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in _nz - 1:
		for i in _nx - 1:
			var x0 := X_MIN + i * CELL
			var z0 := Z_MIN + j * CELL
			var a := Vector3(x0, _h[j * _nx + i], z0)
			var b := Vector3(x0 + CELL, _h[j * _nx + i + 1], z0)
			var c := Vector3(x0, _h[(j + 1) * _nx + i], z0 + CELL)
			var d := Vector3(x0 + CELL, _h[(j + 1) * _nx + i + 1], z0 + CELL)
			for tri in [[a, b, c], [b, d, c]]:
				var t0: Vector3 = tri[0]
				var t1: Vector3 = tri[1]
				var t2: Vector3 = tri[2]
				var n := (t2 - t0).cross(t1 - t0).normalized()
				var mid := (t0 + t1 + t2) / 3.0
				var col := _surface_color(surface_at(mid.x, mid.z), mid.x, mid.z)
				for v in [t0, t1, t2]:
					verts.append(v)
					normals.append(n)
					colors.append(col)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _build_water() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 14
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.45, 0.70, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	disc.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position = Vector3(pond_center.x, water_y, pond_center.y)
	mi.scale = Vector3(pond_radii.x * 1.05, 1.0, pond_radii.y * 1.05)
	add_child(mi)


# ---------------------------------------------------------------- scenery

func _build_trees() -> void:
	var tee_line := PackedVector2Array([clubhouse, tee, fairway[0]])
	for attempt in 650:
		var p := Vector2(_rng.randf_range(X_MIN + 3, X_MAX - 3), _rng.randf_range(Z_MIN + 3, Z_MAX - 3))
		if _dist_polyline(p, fairway) < fairway_half_width + 7.0:
			continue
		if _dist_polyline(p, tee_line) < 13.0:
			continue
		if p.distance_to(pin) < 27.0 or p.distance_to(clubhouse) < 20.0:
			continue
		if _ellipse(p, pond_center, pond_radii) < 1.5:
			continue
		var s := _rng.randf_range(0.8, 1.6)
		var ground := ground_point(p)
		trees.append({
			"pos": ground,
			"scale": s,
			"trunk_r": 0.35 * s,
			"trunk_h": 3.0 * s,
			"canopy_c": ground + Vector3(0, 5.0 * s, 0),
			"canopy_r": 2.0 * s,
		})

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.35
	trunk.height = 3.0
	trunk.radial_segments = 5
	trunk.rings = 1
	trunk.material = _flat(Color(0.36, 0.25, 0.15))
	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.0
	canopy.bottom_radius = 2.3
	canopy.height = 5.5
	canopy.radial_segments = 6
	canopy.rings = 1
	canopy.material = _flat(Color(0.12, 0.30, 0.14))

	var body := StaticBody3D.new()
	add_child(body)
	for pair in [[trunk, 1.5], [canopy, 5.2]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = trees.size()
		for i in trees.size():
			var t: Dictionary = trees[i]
			var s: float = t["scale"]
			var basis := Basis(Vector3.UP, i * 1.7).scaled(Vector3(s, s, s))
			var origin: Vector3 = t["pos"]
			mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0, pair[1] * s, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	for t in trees:
		var shape := CylinderShape3D.new()
		shape.radius = t["trunk_r"]
		shape.height = t["trunk_h"]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var origin: Vector3 = t["pos"]
		cs.position = origin + Vector3(0, shape.height * 0.5, 0)
		body.add_child(cs)


func _build_props() -> void:
	# Flag and cup.
	var pin_pos := ground_point(pin)
	var cup := CylinderMesh.new()
	cup.top_radius = CUP_RADIUS
	cup.bottom_radius = CUP_RADIUS
	cup.height = 0.02
	cup.radial_segments = 8
	cup.material = _flat(Color(0.03, 0.03, 0.03))
	_add_mesh(cup, pin_pos + Vector3(0, 0.02, 0))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 2.6
	pole.radial_segments = 4
	pole.material = _flat(Color(0.95, 0.95, 0.85))
	_add_mesh(pole, pin_pos + Vector3(0, 1.3, 0))
	var flag := BoxMesh.new()
	flag.size = Vector3(0.7, 0.4, 0.02)
	flag.material = _flat(Color(0.90, 0.12, 0.12))
	_add_mesh(flag, pin_pos + Vector3(0.36, 2.38, 0))

	# Tee markers.
	var marker := SphereMesh.new()
	marker.radius = 0.12
	marker.height = 0.24
	marker.radial_segments = 6
	marker.rings = 3
	marker.material = _flat(Color(0.85, 0.15, 0.15))
	for sx in [-2.4, 2.4]:
		_add_mesh(marker, ground_point(tee + Vector2(sx, 0.0)) + Vector3(0, 0.1, 0))

	# Clubhouse.
	var base := ground_point(clubhouse)
	base.y = _club_h
	var walls := BoxMesh.new()
	walls.size = Vector3(14, 4, 9)
	walls.material = _flat(Color(0.90, 0.86, 0.74))
	_add_mesh(walls, base + Vector3(0, 2, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(15.5, 2.8, 10.5)
	roof.material = _flat(Color(0.55, 0.20, 0.16))
	_add_mesh(roof, base + Vector3(0, 5.4, 0))
	var door := BoxMesh.new()
	door.size = Vector3(1.4, 2.4, 0.1)
	door.material = _flat(Color(0.30, 0.18, 0.10))
	_add_mesh(door, base + Vector3(0, 1.2, -4.52))
	var window := BoxMesh.new()
	window.size = Vector3(2.2, 1.3, 0.1)
	window.material = _flat(Color(0.45, 0.65, 0.80))
	for wx in [-4.2, 4.2]:
		_add_mesh(window, base + Vector3(wx, 2.2, -4.52))
	var house := StaticBody3D.new()
	var hs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = walls.size
	hs.shape = box
	house.add_child(hs)
	house.position = base + Vector3(0, 2, 0)
	add_child(house)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	return mi
