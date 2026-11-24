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

func _build_trees() -> void:
	var bark := Blocks.mat("bark", Color(0.36, 0.25, 0.15), 0.04, "bark")
	var birch_bark := Blocks.mat("birch_bark", Color(0.88, 0.87, 0.82), 0.03, "spots", Color(0.2, 0.2, 0.2))
	var oak_leaf := Blocks.mat("oak_leaf", Color(0.17, 0.42, 0.14), 0.05, "spots", Color(0.11, 0.30, 0.10))
	var birch_leaf := Blocks.mat("birch_leaf", Color(0.38, 0.58, 0.20), 0.05, "spots", Color(0.28, 0.46, 0.15))
	var pine_leaf := Blocks.mat("pine_leaf", Color(0.09, 0.27, 0.17), 0.04, "spots", Color(0.06, 0.20, 0.13))
	# Each kind: list of [box size, material, centre height], then canopy info.
	var kinds := [
		{"parts": [[Vector3(0.6, 3.8, 0.6), bark, 1.5], [Vector3(3.4, 2.4, 3.4), oak_leaf, 4.3],
			[Vector3(2.0, 1.0, 2.0), oak_leaf, 6.0]], "canopy_y": 4.6, "canopy_r": 2.2},
		{"parts": [[Vector3(0.45, 4.8, 0.45), birch_bark, 2.0], [Vector3(2.6, 2.6, 2.6), birch_leaf, 5.2],
			[Vector3(1.4, 0.8, 1.4), birch_leaf, 6.9]], "canopy_y": 5.3, "canopy_r": 1.7},
		{"parts": [[Vector3(0.5, 3.2, 0.5), bark, 1.2], [Vector3(3.6, 0.9, 3.6), pine_leaf, 2.9],
			[Vector3(2.8, 0.9, 2.8), pine_leaf, 3.8], [Vector3(2.0, 0.9, 2.0), pine_leaf, 4.7],
			[Vector3(1.1, 1.2, 1.1), pine_leaf, 5.75]], "canopy_y": 4.2, "canopy_r": 2.0},
	]
	var by_kind: Array = [[], [], []]

	for attempt in 2600:
		var p := _random_point()
		var wooded: float = course.forest_at(p)
		if wooded < 0.05 and _rng.randf() > 0.06:
			continue
		if course.dist_polyline(p, course.fairway) < course.fairway_half_width + 7.0:
			continue
		if course.dist_polyline(p, course.cart_path) < 4.0:
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
		var s := _rng.randf_range(0.85, 1.45)
		var ground: Vector3 = course.ground_point(p)
		var info: Dictionary = kinds[kind]
		var canopy_y: float = info["canopy_y"]
		var canopy_r: float = info["canopy_r"]
		by_kind[kind].append([ground, s, _rng.randi_range(0, 3)])
		course.trees.append({
			"pos": ground,
			"trunk_r": 0.35 * s,
			"trunk_h": 3.0 * s,
			"canopy_c": ground + Vector3(0, canopy_y * s, 0),
			"canopy_r": canopy_r * s,
		})
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6 * s, 3.5 * s, 0.6 * s)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = ground + Vector3(0, 1.5 * s, 0)
		_body.add_child(cs)

	for kind in kinds.size():
		var list: Array = by_kind[kind]
		for part in kinds[kind]["parts"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Blocks.box_mesh(part[0], part[1])
			mm.instance_count = list.size()
			for i in list.size():
				var s: float = list[i][1]
				var origin: Vector3 = list[i][0]
				var basis := Basis(Vector3.UP, list[i][2] * PI * 0.5).scaled(Vector3(s, s, s))
				mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0, part[2] * s, 0)))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)


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
	var stone := Blocks.mat("rock", Color(0.50, 0.50, 0.52), 0.06, "spots", Color(0.38, 0.38, 0.40), 2.0)
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
