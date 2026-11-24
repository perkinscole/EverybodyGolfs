extends RefCounted
## Shared helpers for the blocky look: 16x16 pixel textures made in code,
## cached materials, and box/crossed-quad builders.

static var _mats := {}


## A 16x16 texture. Patterns: noise, planks, bricks, bark, spots, patches.
static func texture(base: Color, jitter: float, seed_value: int,
		pattern: String = "noise", accent: Color = Color.BLACK) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(16, 16, true, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var v := rng.randf_range(-jitter, jitter)
			var c := Color(base.r + v, base.g + v, base.b + v, base.a)
			match pattern:
				"planks":
					var row := int(y / 4.0)
					if y % 4 == 3 or x == (row * 7 + 3) % 16:
						c = c.darkened(0.28)
				"bricks":
					var row := int(y / 4.0)
					if y % 4 == 3 or (x + row * 4) % 8 == 7:
						c = c.darkened(0.35)
				"bark":
					if (x + int(y / 6.0)) % 4 == 0:
						c = c.darkened(0.25)
				"spots":
					if rng.randf() < 0.10:
						c = Color(accent.r + v, accent.g + v, accent.b + v, base.a)
				"patches":
					if (int(x / 5.0) * 3 + int(y / 4.0) * 5 + seed_value) % 4 == 0:
						c = Color(accent.r + v, accent.g + v, accent.b + v, base.a)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Cached pixel-texture material. Triplanar ones tile per metre on any box.
static func mat(key: String, base: Color, jitter: float = 0.05, pattern: String = "noise",
		accent: Color = Color.BLACK, tiles_per_metre: float = 1.0,
		triplanar: bool = true) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(base, jitter, key.hash(), pattern, accent)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 1.0
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tiles_per_metre
	if base.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func plain(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := "plain:%s:%s" % [color.to_html(), unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func box_mesh(size: Vector3, material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh


static func box(parent: Node3D, size: Vector3, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size, material)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Box you can see and bump into. `body` must be a child of the same parent
## space as `parent` (both at the origin of the thing being built).
static func solid_box(parent: Node3D, body: StaticBody3D, size: Vector3,
		material: Material, pos: Vector3) -> MeshInstance3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return box(parent, size, material, pos)


static func pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Alpha-cutout plant textures: "grass" blades or a "flower".
static func plant_material(key: String, kind: String, color: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "grass":
		for x in 16:
			if rng.randf() < 0.25:
				continue
			var h := rng.randi_range(4, 14)
			var shade := rng.randf_range(-0.08, 0.08)
			for y in range(16 - h, 16):
				img.set_pixel(x, y, Color(color.r + shade, color.g + shade, color.b + shade))
	else:
		var stem := Color(0.20, 0.50, 0.18)
		for y in range(6, 16):
			img.set_pixel(8, y, stem)
		for p in [Vector2i(7, 11), Vector2i(6, 10), Vector2i(9, 12), Vector2i(10, 11)]:
			img.set_pixel(p.x, p.y, stem)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					img.set_pixel(8 + dx, 4 + dy, color)
		img.set_pixel(8, 4, Color(1.0, 0.9, 0.3))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	_mats[key] = m
	return m


## Two upright quads crossed at right angles, base at y = 0.
static func cross_mesh(width: float, height: float, material: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var w := width * 0.5
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var base := verts.size()
		verts.append_array([-axis * w, axis * w,
			axis * w + Vector3(0, height, 0), -axis * w + Vector3(0, height, 0)])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		for i in 4:
			normals.append(Vector3.UP)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
