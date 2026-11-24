extends Node3D
## Everything that sits on the course: trees, plants, rocks, the bridge, the
## flag, signs, a parked cart and clouds. `course` must be set before _ready.

const Blocks = preload("res://scripts/blocks.gd")

var course: Node3D

var _rng := RandomNumberGenerator.new()
var _clouds: Node3D
var _body: StaticBody3D


func _ready() -> void:
	_rng.seed = 4321
	_body = StaticBody3D.new()
	add_child(_body)
	_build_trees()
	_build_plants()
	_build_rocks()
	_build_undergrowth()
	_build_fence()
	_build_bridge()
	_build_hole_props()
	_build_cart()
	_build_clouds()


func _process(delta: float) -> void:
	for cloud in _clouds.get_children():
		cloud.position.x += delta * 1.2
		if cloud.position.x > 420.0:
			cloud.position.x = -420.0


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(course.X_MIN + 3, course.X_MAX - 3),
		_rng.randf_range(course.Z_MIN + 3, course.Z_MAX - 3))


# ---------------------------------------------------------------- trees

const TREE_VOXEL := 0.5
# Per kind: trunk height, canopy centre height and radius, in metres.
const TREE_SHAPES := [
	{"trunk_h": 3.5, "canopy_y": 4.9, "canopy_r": 1.9},     # oak
	{"trunk_h": 4.5, "canopy_y": 5.9, "canopy_r": 1.5},     # birch
	{"trunk_h": 2.5, "canopy_y": 4.6, "canopy_r": 1.8},     # pine
]


## Voxels for one tree. Slots: 0 bark, 1 leaf, 2 second leaf tone.
func _tree_cells(kind: int) -> Dictionary:
	var cells := {}
	var sides := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	if kind == 2:
		for y in 6:
			cells[Vector3i(0, y, 0)] = 0
		for y in range(4, 15):
			var r := lerpf(3.9, 0.7, (y - 4) / 10.0) * (1.0 if y % 2 == 0 else 0.72)
			var reach := int(ceil(r))
			for dx in range(-reach, reach + 1):
				for dz in range(-reach, reach + 1):
					if dx * dx + dz * dz <= r * r - _rng.randf() * 1.2:
						cells[Vector3i(dx, y, dz)] = 1 if _rng.randf() < 0.75 else 2
		for y in range(6, 16):
			cells[Vector3i(0, y, 0)] = 1          # keep the top joined up
		return cells
	var trunk := 7 if kind == 0 else 9
	var radii := Vector3(3.8, 2.8, 3.8) if kind == 0 else Vector3(2.6, 3.3, 2.6)
	var mid_y := trunk + (2 if kind == 0 else 2)
	for y in trunk + 2:
		cells[Vector3i(0, y, 0)] = 0
	for side in sides:
		if _rng.randf() < 0.55:
			cells[side] = 0                       # root flare
		if kind == 0 and _rng.randf() < 0.5:
			cells[side + Vector3i(0, trunk - 1, 0)] = 0   # stub of a branch
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			for dz in range(-4, 5):
				var q := Vector3(dx / radii.x, dy / radii.y, dz / radii.z).length_squared()
				if q < 1.0 - _rng.randf() * 0.35:
					var cell := Vector3i(dx, mid_y + dy, dz)
					if not cells.has(cell):
						cells[cell] = 1 if _rng.randf() < 0.72 else 2
	return cells


func _build_trees() -> void:
	var bark := Blocks.mat("bark", Color(0.36, 0.25, 0.15), 0.04, "bark")
	var birch_bark := Blocks.mat("birch_bark", Color(0.88, 0.87, 0.82), 0.03, "spots", Color(0.2, 0.2, 0.2))
	var palettes := [
		[bark, Blocks.mat("oak_leaf", Color(0.17, 0.42, 0.14), 0.05, "leaves", Color(0.10, 0.28, 0.09)),
			Blocks.mat("oak_leaf_b", Color(0.21, 0.47, 0.16), 0.05, "leaves", Color(0.12, 0.31, 0.10))],
		[birch_bark, Blocks.mat("birch_leaf", Color(0.38, 0.58, 0.20), 0.05, "leaves", Color(0.26, 0.44, 0.14)),
			Blocks.mat("birch_leaf_b", Color(0.46, 0.64, 0.22), 0.05, "leaves", Color(0.30, 0.48, 0.15))],
		[bark, Blocks.mat("pine_leaf", Color(0.09, 0.27, 0.17), 0.04, "leaves", Color(0.05, 0.18, 0.12)),
			Blocks.mat("pine_leaf_b", Color(0.11, 0.31, 0.19), 0.04, "leaves", Color(0.06, 0.20, 0.13))],
	]
	# A few different shapes of each kind, shared between many trees.
	var variants := 3
	var meshes: Array = []
	var placed: Array = []
	for kind in 3:
		for v in variants:
			meshes.append(Blocks.voxel_mesh(_tree_cells(kind), TREE_VOXEL, palettes[kind]))
			placed.append([])

	for attempt in 2300:
		var p := _random_point()
		var wooded: float = course.forest_at(p)
		if wooded < 0.05 and _rng.randf() > 0.06:
			continue
		if course.dist_polyline(p, course.fairway) < course.fairway_half_width + 7.0:
			continue
		if course.dist_polyline(p, course.cart_path) < 4.5:
			continue
		if course.dist_polyline(p, PackedVector2Array([course.tee, course.fairway[0]])) < 13.0:
			continue
		if p.distance_to(course.pin) < 27.0 or p.distance_to(course.clubhouse) < 21.0:
			continue
		if p.distance_to(course.tee) < 14.0 or course.water_distance(p) < 3.0:
			continue
		var roll := _rng.randf()
		var kind := 0
		if p.y < -230.0:
			kind = 2 if roll < 0.7 else 1
		elif roll > 0.85:
			kind = 2
		elif roll > 0.6:
			kind = 1
		var s := _rng.randf_range(1.0, 1.5)
		var ground: Vector3 = course.ground_point(p)
		var shape_info: Dictionary = TREE_SHAPES[kind]
		var trunk_h: float = shape_info["trunk_h"]
		var canopy_y: float = shape_info["canopy_y"]
		var canopy_r: float = shape_info["canopy_r"]
		placed[kind * variants + _rng.randi_range(0, variants - 1)].append([ground, s, _rng.randi_range(0, 3)])
		course.trees.append({
			"pos": ground,
			"trunk_r": 0.3 * s,
			"trunk_h": trunk_h * s,
			"canopy_c": ground + Vector3(0, canopy_y * s, 0),
			"canopy_r": canopy_r * s,
		})
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5 * s, trunk_h * s, 0.5 * s)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = ground + Vector3(0, trunk_h * s * 0.5, 0)
		_body.add_child(cs)

	for m in meshes.size():
		_scatter(meshes[m], placed[m], -0.25, true)


## One MultiMesh from a list of [ground point, scale, quarter turns].
func _scatter(mesh: Mesh, list: Array, sink: float, shadows: bool) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var s: float = list[i][1]
		var origin: Vector3 = list[i][0]
		var basis := Basis(Vector3.UP, list[i][2] * PI * 0.5).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0, sink * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Bushes at the edge of the woods, mushrooms under the trees, reeds and lily
## pads on the water.
func _build_undergrowth() -> void:
	var leaf := Blocks.mat("bush_leaf", Color(0.20, 0.45, 0.16), 0.05, "leaves", Color(0.12, 0.30, 0.10), 2.0)
	var berry := Blocks.plain(Color(0.80, 0.16, 0.20))
	var bush_meshes: Array = []
	var bush_spots: Array = []
	for v in 3:
		var cells := {}
		for dx in range(-3, 4):
			for dy in range(0, 4):
				for dz in range(-3, 4):
					var q := Vector3(dx / 2.8, (dy - 1.0) / 2.4, dz / 2.8).length_squared()
					if q < 1.0 - _rng.randf() * 0.45:
						cells[Vector3i(dx, dy, dz)] = 1 if _rng.randf() < 0.025 else 0
		bush_meshes.append(Blocks.voxel_mesh(cells, 0.25, [leaf, berry]))
		bush_spots.append([])

	var stalk := Blocks.plain(Color(0.92, 0.90, 0.82))
	var caps := [Blocks.mat("cap_red", Color(0.80, 0.14, 0.14), 0.03, "spots", Color(0.95, 0.95, 0.92), 8.0),
		Blocks.plain(Color(0.62, 0.42, 0.24))]
	var shroom_meshes: Array = []
	var shroom_spots: Array = []
	for v in 2:
		var cells := {Vector3i(0, 0, 0): 0, Vector3i(0, 1, 0): 0}
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				cells[Vector3i(dx, 2, dz)] = 1
		cells[Vector3i(0, 3, 0)] = 1
		shroom_meshes.append(Blocks.voxel_mesh(cells, 0.09, [stalk, caps[v]]))
		shroom_spots.append([])

	for attempt in 5000:
		var p := _random_point()
		if course.surface_at(p.x, p.y) != course.Surface.ROUGH or p.distance_to(course.clubhouse) < 10.0:
			continue
		if course.dist_polyline(p, course.cart_path) < 2.5:
			continue
		var wooded: float = course.forest_at(p)
		var ground: Vector3 = course.ground_point(p)
		if absf(wooded - 0.05) < 0.07 and _rng.randf() < 0.45:
			bush_spots[_rng.randi_range(0, 2)].append([ground, _rng.randf_range(0.8, 1.5), _rng.randi_range(0, 3)])
		elif wooded > 0.15 and _rng.randf() < 0.3:
			shroom_spots[_rng.randi_range(0, 1)].append([ground, _rng.randf_range(0.8, 1.8), _rng.randi_range(0, 3)])
	for v in bush_meshes.size():
		_scatter(bush_meshes[v], bush_spots[v], 0.0, true)
	for v in shroom_meshes.size():
		_scatter(shroom_meshes[v], shroom_spots[v], 0.0, false)

	# Reeds along the banks.
	var reed := Blocks.cross_mesh(0.7, 1.6, Blocks.plant_material("reed", "grass", Color(0.36, 0.46, 0.18)))
	var reed_spots: Array = []
	for attempt in 900:
		var k := _rng.randi_range(0, course.river.size() - 2)
		var along: Vector2 = course.river[k].lerp(course.river[k + 1], _rng.randf())
		var p := along + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-7, 7))
		if attempt % 4 == 0:
			p = course.pond_center + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-12, 12))
		var wd: float = course.water_distance(p)
		if wd < -0.6 or wd > 1.4 or course.surface_at(p.x, p.y) == course.Surface.PATH:
			continue
		if course.deck_at(p.x, p.y) > -1000.0:
			continue
		reed_spots.append([course.ground_point(p), _rng.randf_range(0.7, 1.2), _rng.randi_range(0, 3)])
	_scatter(reed, reed_spots, 0.05, false)

	# Lily pads on the pond.
	var pad := Blocks.plain(Color(0.20, 0.50, 0.22))
	var bloom := Blocks.plain(Color(0.96, 0.70, 0.82))
	for i in 16:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(0.15, 0.8)
		var at := Vector3(course.pond_center.x + cos(ang) * course.pond_radii.x * r, course.water_y + 0.02,
			course.pond_center.y + sin(ang) * course.pond_radii.y * r)
		Blocks.box(self, Vector3(0.5, 0.03, 0.5), pad, at)
		Blocks.box(self, Vector3(0.25, 0.03, 0.25), pad, at + Vector3(0.3, 0, 0.12))
		if i % 3 == 0:
			Blocks.box(self, Vector3(0.14, 0.12, 0.14), bloom, at + Vector3(0, 0.07, 0))


## Post-and-rail fence beside the path from the clubhouse to the tee.
func _build_fence() -> void:
	var wood := Blocks.mat("dark_wood", Color(0.38, 0.26, 0.16), 0.04, "planks")
	var line := PackedVector2Array([course.cart_path[0] + Vector2(0, -2), course.cart_path[1], course.cart_path[2]])
	var posts: Array = []
	for k in line.size() - 1:
		var dir: Vector2 = (line[k + 1] - line[k]).normalized()
		var side := Vector2(-dir.y, dir.x) * 2.3
		var steps := int(line[k].distance_to(line[k + 1]) / 2.5)
		for i in steps + 1:
			posts.append(course.ground_point(line[k].lerp(line[k + 1], float(i) / steps) + side))
	for i in posts.size():
		var at: Vector3 = posts[i]
		Blocks.box(self, Vector3(0.18, 1.1, 0.18), wood, at + Vector3(0, 0.5, 0))
		if i == posts.size() - 1:
			continue
		var next: Vector3 = posts[i + 1]
		if at.distance_to(next) > 4.0:
			continue
		for rail_y in [0.45, 0.85]:
			var rail := Blocks.box(self, Vector3(0.08, 0.1, at.distance_to(next)), wood,
				(at + next) * 0.5 + Vector3(0, rail_y, 0))
			rail.look_at_from_position(rail.position, next + Vector3(0, rail_y, 0))


# ---------------------------------------------------------------- plants

func _build_plants() -> void:
	var grass_a := Blocks.cross_mesh(0.8, 0.6, Blocks.plant_material("tuft_a", "grass", Color(0.22, 0.48, 0.16)))
	var grass_b := Blocks.cross_mesh(0.9, 0.8, Blocks.plant_material("tuft_b", "grass", Color(0.17, 0.40, 0.13)))
	var flowers := [
		Blocks.cross_mesh(0.5, 0.6, Blocks.plant_material("flower_r", "flower", Color(0.90, 0.20, 0.22))),
		Blocks.cross_mesh(0.5, 0.6, Blocks.plant_material("flower_y", "flower", Color(0.97, 0.82, 0.20))),
		Blocks.cross_mesh(0.5, 0.6, Blocks.plant_material("flower_b", "flower", Color(0.45, 0.55, 0.95))),
		Blocks.cross_mesh(0.5, 0.6, Blocks.plant_material("flower_w", "flower", Color(0.96, 0.96, 0.98))),
	]
	var spots: Array = [[], [], [], [], [], []]
	for attempt in 16000:
		var p := _random_point()
		if course.surface_at(p.x, p.y) != course.Surface.ROUGH:
			continue
		if p.distance_to(course.clubhouse) < 9.5:
			continue
		var slot := _rng.randi_range(0, 1)
		# Flowers gather in the open meadows.
		if course.forest_at(p) < -0.05 and _rng.randf() < 0.22:
			slot = 2 + _rng.randi_range(0, 3)
		spots[slot].append(course.ground_point(p))
	var meshes := [grass_a, grass_b] + flowers
	for slot in meshes.size():
		var list: Array = spots[slot]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[slot]
		mm.instance_count = list.size()
		for i in list.size():
			var s := _rng.randf_range(0.8, 1.3)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
			var origin: Vector3 = list[i]
			mm.set_instance_transform(i, Transform3D(basis, origin - Vector3(0, 0.04, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_rocks() -> void:
	var stone := Blocks.mat("rock", Color(0.50, 0.50, 0.52), 0.06, "pebbles", Color(0.42, 0.42, 0.44), 1.5)
	var spots: Array = []
	for attempt in 260:
		var p := _random_point()
		var near_water: bool = course.water_distance(p) < 5.0 and course.water_distance(p) > 0.8
		if course.surface_at(p.x, p.y) != course.Surface.ROUGH:
			continue
		if not near_water and _rng.randf() > 0.25:
			continue
		spots.append(course.ground_point(p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Blocks.box_mesh(Vector3(0.6, 0.45, 0.5), stone)
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := Vector3(_rng.randf_range(0.6, 1.8), _rng.randf_range(0.6, 1.5), _rng.randf_range(0.6, 1.8))
		var origin: Vector3 = spots[i]
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5).scaled(s), origin + Vector3(0, 0.1, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ---------------------------------------------------------------- bridge

func _build_bridge() -> void:
	var planks := Blocks.mat("planks", Color(0.72, 0.56, 0.36), 0.04, "planks")
	var dark_wood := Blocks.mat("dark_wood", Color(0.38, 0.26, 0.16), 0.04, "planks")
	var c: Vector2 = course.bridge_center
	var half: Vector2 = course.bridge_half
	var top: float = course.bridge_top
	var mid := Vector3(c.x, top, c.y)
	Blocks.solid_box(self, _body, Vector3(half.x * 2.0, 0.3, half.y * 2.0), planks, mid - Vector3(0, 0.15, 0))
	# Short ramps so you can walk on without a hop.
	for end in [-1.0, 1.0]:
		var ramp_pos := mid + Vector3(0, -0.2, end * (half.y + 0.9))
		var ramp := Blocks.solid_box(self, _body, Vector3(half.x * 2.0, 0.3, 2.2), planks, ramp_pos)
		ramp.rotation.x = end * 0.16
		_body.get_child(_body.get_child_count() - 1).rotation.x = end * 0.16
	for side in [-1.0, 1.0]:
		var x: float = side * (half.x - 0.1)
		Blocks.solid_box(self, _body, Vector3(0.16, 0.16, half.y * 2.0), dark_wood, mid + Vector3(x, 1.05, 0))
		Blocks.box(self, Vector3(0.10, 0.10, half.y * 2.0), dark_wood, mid + Vector3(x, 0.55, 0))
		for k in 5:
			var z := lerpf(-half.y + 0.15, half.y - 0.15, k / 4.0)
			Blocks.box(self, Vector3(0.22, 1.2, 0.22), dark_wood, mid + Vector3(x, 0.6, z))
		# Piles down into the river bed.
		for z in [-2.5, 2.5]:
			Blocks.box(self, Vector3(0.3, 2.4, 0.3), dark_wood, mid + Vector3(x, -1.3, z))


# ---------------------------------------------------------------- props

func _build_hole_props() -> void:
	var white := Blocks.plain(Color(0.95, 0.95, 0.88))
	var red := Blocks.plain(Color(0.88, 0.14, 0.14))
	var dark_wood := Blocks.mat("dark_wood", Color(0.38, 0.26, 0.16), 0.04, "planks")
	var planks := Blocks.mat("planks", Color(0.72, 0.56, 0.36), 0.04, "planks")

	# Cup and flag.
	var pin_pos: Vector3 = course.ground_point(course.pin)
	Blocks.box(self, Vector3(0.26, 0.02, 0.26), Blocks.plain(Color(0.03, 0.03, 0.03)), pin_pos + Vector3(0, 0.02, 0))
	Blocks.box(self, Vector3(0.06, 2.8, 0.06), white, pin_pos + Vector3(0, 1.4, 0))
	Blocks.box(self, Vector3(0.8, 0.5, 0.04), red, pin_pos + Vector3(0.43, 2.5, 0))

	# Tee blocks.
	for sx in [-2.4, 2.4]:
		Blocks.box(self, Vector3(0.3, 0.3, 0.3), red, course.ground_point(course.tee + Vector2(sx, 0.0)) + Vector3(0, 0.15, 0))

	# Hole sign by the tee, facing the path.
	var sign_at: Vector3 = course.ground_point(course.tee + Vector2(5.0, 2.5))
	Blocks.box(self, Vector3(0.16, 1.6, 0.16), dark_wood, sign_at + Vector3(0, 0.8, 0))
	Blocks.box(self, Vector3(1.5, 1.0, 0.1), planks, sign_at + Vector3(0, 1.7, 0))
	var label := Label3D.new()
	label.text = "HOLE 1\nPAR %d\n%d m" % [course.PAR, int(round(course.hole_length()))]
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.15, 0.10, 0.06)
	label.position = sign_at + Vector3(0, 1.7, 0.06)
	add_child(label)

	# Bench behind the tee.
	var bench_at: Vector3 = course.ground_point(course.tee + Vector2(-4.5, 4.0))
	Blocks.solid_box(self, _body, Vector3(2.0, 0.12, 0.6), planks, bench_at + Vector3(0, 0.5, 0))
	Blocks.box(self, Vector3(2.0, 0.5, 0.1), planks, bench_at + Vector3(0, 0.9, 0.3))
	for bx in [-0.85, 0.85]:
		Blocks.box(self, Vector3(0.12, 0.5, 0.5), dark_wood, bench_at + Vector3(bx, 0.25, 0))


func _build_cart() -> void:
	var at: Vector3 = course.ground_point(Vector2(20.5, 35.0))
	var cart := Node3D.new()
	cart.position = at
	cart.rotation.y = 0.35
	add_child(cart)
	var white := Blocks.plain(Color(0.94, 0.94, 0.90))
	var dark := Blocks.plain(Color(0.12, 0.12, 0.14))
	var green := Blocks.plain(Color(0.16, 0.42, 0.26))
	Blocks.box(cart, Vector3(1.4, 0.5, 2.5), white, Vector3(0, 0.6, 0))
	Blocks.box(cart, Vector3(1.4, 0.35, 0.9), white, Vector3(0, 1.0, -0.8))
	Blocks.box(cart, Vector3(1.2, 0.25, 0.6), dark, Vector3(0, 0.95, 0.2))
	Blocks.box(cart, Vector3(1.2, 0.6, 0.15), dark, Vector3(0, 1.25, 0.55))
	Blocks.box(cart, Vector3(1.5, 0.1, 2.0), green, Vector3(0, 2.15, 0.1))
	for px in [-0.65, 0.65]:
		for pz in [-0.75, 0.95]:
			Blocks.box(cart, Vector3(0.08, 1.2, 0.08), dark, Vector3(px, 1.55, pz))
		for wz in [-0.85, 0.85]:
			Blocks.box(cart, Vector3(0.25, 0.5, 0.5), dark, Vector3(px * 1.1, 0.25, wz))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 2.2, 2.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at + Vector3(0, 1.1, 0)
	cs.rotation.y = 0.35
	_body.add_child(cs)


func _build_clouds() -> void:
	_clouds = Node3D.new()
	add_child(_clouds)
	var white := Blocks.plain(Color(1, 1, 1, 0.85), true)
	for i in 26:
		var cloud := Node3D.new()
		cloud.position = Vector3(_rng.randf_range(-420, 420), _rng.randf_range(85, 120), _rng.randf_range(-650, 250))
		_clouds.add_child(cloud)
		for k in _rng.randi_range(2, 4):
			var mi := Blocks.box(cloud, Vector3(_rng.randf_range(14, 34), 4.0, _rng.randf_range(10, 22)), white,
				Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-9, 9)))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
