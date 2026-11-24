extends Node3D
## Golf ball with hand-rolled physics: drag and lift in the air, bounce and
## roll on the ground, all driven by the course's height/surface queries.

const Course = preload("res://scripts/course.gd")

signal stopped
signal holed
signal hazard(kind: String)
## The ball hit the ground (surface index) at this speed.
signal bounced(surface: int, speed: float)
## The ball hit a tree: "knock" for trunk, "rustle" for leaves.
signal tree_hit(kind: String)

const RADIUS := 0.06
const G := 9.81
const DRAG := 0.0047
const LIFT := 0.0026
const SUBSTEPS := 4
# Indexed by Course.Surface: ROUGH, FAIRWAY, GREEN, BUNKER, TEE, WATER, PATH
const ROLL_DECEL := [7.0, 3.0, 0.85, 12.0, 3.0, 20.0, 2.6]
const BOUNCE := [0.20, 0.32, 0.28, 0.05, 0.32, 0.0, 0.5]
const SKID := [0.40, 0.55, 0.50, 0.15, 0.55, 0.0, 0.8]

var course: Course
var velocity := Vector3.ZERO
var moving := false
var airborne := false
var curve := 0.0
var spin := 1.0
var flight_time := 0.0
var move_time := 0.0
## Where the ball first touched down on the current shot (for tuning/tests).
var first_landing := Vector3.INF

var _last_tree := -1
var _on_deck := false
var _mesh: MeshInstance3D
var _beacon: MeshInstance3D


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.97, 0.95)
	mat.roughness = 0.6
	sphere.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	add_child(_mesh)

	var column := CylinderMesh.new()
	column.top_radius = 0.12
	column.bottom_radius = 0.12
	column.height = 30.0
	column.radial_segments = 5
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column.material = bmat
	_beacon = MeshInstance3D.new()
	_beacon.mesh = column
	_beacon.position = Vector3(0, 15.0, 0)
	_beacon.visible = false
	add_child(_beacon)


func set_beacon(on: bool) -> void:
	_beacon.visible = on


func beacon_on() -> bool:
	return _beacon.visible


## Put the ball at rest on the ground at an x/z spot.
func place(p: Vector2) -> void:
	position = Vector3(p.x, course.height_at(p.x, p.y) + RADIUS, p.y)
	velocity = Vector3.ZERO
	moving = false
	airborne = false
	visible = true


func launch(vel: Vector3, curve_amount: float, spin_amount: float) -> void:
	velocity = vel
	curve = curve_amount
	spin = spin_amount
	moving = true
	airborne = vel.y > 0.5
	flight_time = 0.0
	move_time = 0.0
	first_landing = Vector3.INF
	_last_tree = -1


func _physics_process(delta: float) -> void:
	simulate(delta)


## Advance the ball; public so tests can drive it without a running scene.
func simulate(delta: float) -> void:
	if not moving:
		return
	move_time += delta
	for i in SUBSTEPS:
		if not moving:
			return
		_step(delta / SUBSTEPS)
	if moving and move_time > 90.0:
		_rest()


func _rest() -> void:
	velocity = Vector3.ZERO
	moving = false
	airborne = false
	stopped.emit()


func _step(dt: float) -> void:
	var p := position
	if airborne:
		flight_time += dt
		var speed := velocity.length()
		var acc := Vector3(0, -G, 0)
		if speed > 0.01:
			var dir := velocity / speed
			acc -= dir * DRAG * speed * speed
			var side := dir.cross(Vector3.UP)
			if side.length() > 0.01:
				side = side.normalized()
				var decay := exp(-flight_time / 7.0)
				acc += side.cross(dir) * LIFT * spin * speed * speed * decay
				acc += side * LIFT * curve * speed * speed * decay * 0.5
		velocity += acc * dt
		p += velocity * dt
		_hit_trees(p)
		if not course.in_bounds(p.x, p.z, 1.0):
			_stop_in_hazard(p, "out of bounds")
			return
		var ground := _ground(p)
		if p.y <= ground:
			p.y = ground
			var s := _surface(p)
			if first_landing == Vector3.INF:
				first_landing = p
			if s == Course.Surface.WATER:
				_stop_in_hazard(p, "water")
				return
			var n := _normal(p)
			var vn := velocity.dot(n)
			if vn < 0.0:
				bounced.emit(s, -vn)
				var bounce_v: float = -vn * BOUNCE[s]
				velocity = (velocity - n * vn) * SKID[s] + n * bounce_v
				if bounce_v < 0.8:
					airborne = false
					velocity -= n * velocity.dot(n)
		position = p
		return

	# Rolling.
	p.y = _ground(p)
	var s := _surface(p)
	if s == Course.Surface.WATER:
		_stop_in_hazard(p, "water")
		return
	var n := _normal(p)
	var slope := Vector3(0, -G, 0)
	slope -= n * slope.dot(n)
	velocity -= n * velocity.dot(n)
	velocity += slope * dt
	var speed := velocity.length()
	var decel: float = ROLL_DECEL[s]
	if speed <= decel * dt + 0.02 and slope.length() < decel:
		position = p
		_rest()
		return
	if speed > 0.0:
		velocity -= velocity / speed * minf(decel * dt, speed)
	p += velocity * dt
	if not course.in_bounds(p.x, p.z, 1.0):
		_stop_in_hazard(p, "out of bounds")
		return
	p.y = _ground(p)
	position = p
	if Vector2(p.x - course.pin.x, p.z - course.pin.y).length() < Course.CUP_RADIUS and speed < 4.0:
		velocity = Vector3.ZERO
		moving = false
		visible = false
		holed.emit()


## Height the ball rests at here: the terrain, or the bridge deck if the
## ball is at or above it.
func _ground(p: Vector3) -> float:
	var terrain := course.height_at(p.x, p.z)
	var deck := course.deck_at(p.x, p.z)
	_on_deck = deck > terrain and p.y > deck - 0.4
	return (deck if _on_deck else terrain) + RADIUS


func _surface(p: Vector3) -> int:
	return Course.Surface.PATH if _on_deck else course.surface_at(p.x, p.z)


func _normal(p: Vector3) -> Vector3:
	return Vector3.UP if _on_deck else course.normal_at(p.x, p.z)


func _stop_in_hazard(p: Vector3, kind: String) -> void:
	position = p
	velocity = Vector3.ZERO
	moving = false
	airborne = false
	hazard.emit(kind)


func _hit_trees(p: Vector3) -> void:
	for i in course.trees.size():
		var t: Dictionary = course.trees[i]
		var base: Vector3 = t["pos"]
		var dx := p.x - base.x
		var dz := p.z - base.z
		var d2 := dx * dx + dz * dz
		var canopy_r: float = t["canopy_r"]
		if d2 > canopy_r * canopy_r:
			continue
		var trunk_r: float = t["trunk_r"] + RADIUS
		var trunk_h: float = t["trunk_h"]
		if p.y < base.y + trunk_h and d2 < trunk_r * trunk_r:
			var n := Vector3(dx, 0, dz).normalized()
			var vn := velocity.dot(n)
			if vn < 0.0:
				velocity -= n * vn * 1.5
				velocity *= 0.6
				tree_hit.emit("knock")
		elif i != _last_tree:
			var c: Vector3 = t["canopy_c"]
			if p.distance_to(c) < canopy_r:
				_last_tree = i
				tree_hit.emit("rustle")
				velocity *= 0.45
				velocity += Vector3(randf_range(-3, 3), randf_range(-2, 0), randf_range(-3, 3))
