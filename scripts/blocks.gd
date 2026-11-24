extends RefCounted
## Shared helpers for the blocky look: pixel textures made in code,
## cached materials, and box/crossed-quad builders.

static var _mats := {}


const TEX := 32


## A 32x32 texture at 32 pixels per metre. Patterns: noise, planks, bricks,
## bark, spots, patches, grass, pebbles, water, sand, leaves.
static func texture(base: Color, jitter: float, seed_value: int,
		pattern: String = "noise", accent: Color = Color.BLACK) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := TEX
	# Tileable low-frequency tone so big areas are not flat.
	var lattice: Array = []
	for i in 16:
		lattice.append(rng.randf_range(-1.0, 1.0))
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var fx := x * 4.0 / n
			var fy := y * 4.0 / n
			var x0 := int(fx) % 4
			var y0 := int(fy) % 4
			var x1 := (x0 + 1) % 4
			var y1 := (y0 + 1) % 4
			var tx := smoothstep(0.0, 1.0, fx - int(fx))
			var ty := smoothstep(0.0, 1.0, fy - int(fy))
			var low := lerpf(lerpf(lattice[y0 * 4 + x0], lattice[y0 * 4 + x1], tx),
				lerpf(lattice[y1 * 4 + x0], lattice[y1 * 4 + x1], tx), ty)
			var v := rng.randf_range(-jitter, jitter) + low * jitter * 0.8
			var c := Color(base.r + v, base.g + v, base.b + v, base.a)
			var tint := Color(accent.r + v, accent.g + v, accent.b + v, base.a)
			# Structural patterns are laid out on a 16-wide grid.
			var px := int(x * 16.0 / n)
			var py := int(y * 16.0 / n)
			match pattern:
				"planks":
					var row := int(py / 4.0)
					if y % 8 == 7 or (px == (row * 7 + 3) % 16 and x % 2 == 0):
						c = c.darkened(0.30)
					elif rng.randf() < 0.06:
						c = c.darkened(0.12)
				"bricks":
					var row := int(y / 8.0)
					if y % 8 == 7 or (x + row * 8) % 16 == 15:
						c = c.darkened(0.35)
					elif y % 8 == 0:
						c = c.lightened(0.08)
				"bark":
					if (px + int(py / 6.0)) % 4 == 0:
						c = c.darkened(0.25)
					elif rng.randf() < 0.08:
						c = c.lightened(0.10)
				"spots":
					if rng.randf() < 0.10:
						c = tint
				"patches":
					if (int(px / 5.0) * 3 + int(py / 4.0) * 5 + seed_value) % 4 == 0:
						c = tint
				"grass":
					var r := rng.randf()
					if r < 0.16:
						c = tint
					elif r < 0.24:
						c = c.darkened(0.14)
				"leaves":
					var r := rng.randf()
					if r < 0.15:
						c = tint
					elif r < 0.24:
						c = c.lightened(0.14)
				"water":
					if (y + int(x / 5.0) * 3) % 8 == 0 and rng.randf() < 0.75:
						c = tint
				"sand":
					var ripple := sin((y + sin(x * 0.4) * 2.0) * 0.8) * 0.025
					c = Color(c.r + ripple, c.g + ripple, c.b + ripple, base.a)
			img.set_pixel(x, y, c)
	if pattern == "pebbles":
		for k in 34:
			var cx := rng.randi_range(0, n - 1)
			var cy := rng.randi_range(0, n - 1)
			var shade := rng.randf_range(-0.16, 0.16)
			var stone := Color(accent.r + shade, accent.g + shade, accent.b + shade, base.a)
			var size := rng.randi_range(2, 3)
			for dy in size:
				for dx in size:
					if size == 3 and dx != 1 and dy != 1:
						continue
					img.set_pixel((cx + dx) % n, (cy + dy) % n, stone)
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


## Mesh a set of voxels, hiding faces between neighbours.
## `cells` maps Vector3i -> material slot. Cell (x, y, z) spans x-0.5..x+0.5,
## y..y+1, z-0.5..z+0.5, times `voxel` metres. Materials should be triplanar.
static func voxel_mesh(cells: Dictionary, voxel: float, materials: Array) -> ArrayMesh:
	# For each face: outward normal, then two edge axes with u x v = normal.
	var faces := [
		[Vector3i(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3i(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3i(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3i(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3i(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3i(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	var verts: Array = []
	var normals: Array = []
	var indices: Array = []
	for m in materials.size():
		verts.append(PackedVector3Array())
		normals.append(PackedVector3Array())
		indices.append(PackedInt32Array())
	for cell: Vector3i in cells:
		var slot: int = cells[cell]
		var centre := Vector3(cell.x, cell.y + 0.5, cell.z)
		for face in faces:
			var dir: Vector3i = face[0]
			if cells.has(cell + dir):
				continue
			var n := Vector3(dir)
			var u: Vector3 = face[1]
			var v: Vector3 = face[2]
			var base: int = verts[slot].size()
			var mid := centre + n * 0.5
			for corner in [-u - v, u - v, u + v, -u + v]:
				verts[slot].append((mid + corner * 0.5) * voxel)
				normals[slot].append(n)
			indices[slot].append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var mesh := ArrayMesh.new()
	for m in materials.size():
		if verts[m].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts[m]
		arrays[Mesh.ARRAY_NORMAL] = normals[m]
		arrays[Mesh.ARRAY_INDEX] = indices[m]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[m])
	return mesh
