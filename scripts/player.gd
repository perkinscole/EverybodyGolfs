extends CharacterBody3D
## A blocky golfer. Walks around in first person; when addressing the ball the
## camera drops behind the target line and the mouse drives aim and swing.

const Course = preload("res://scripts/course.gd")
const Ball = preload("res://scripts/ball.gd")
const Clubs = preload("res://scripts/clubs.gd")

signal struck(power: float, drift: float)
signal club_changed

enum Mode { FREE, ADDRESS }

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const JUMP_SPEED := 4.5
const GRAVITY := 14.0
const LOOK_SENS := 0.0025
const AIM_SENS := 0.0009
const STANCE := 0.97          # how far the golfer stands from the ball
const BACKSWING_TIME := 1.2   # seconds to a full backswing
const OVERSWING := 1.3
const TOP_ANGLE := deg_to_rad(190.0)
const FINISH_ANGLE := deg_to_rad(-165.0)
const DOWNSWING_SPEED := deg_to_rad(1500.0)

var course: Course
var ball: Ball
var camera: Camera3D
var mode := Mode.FREE
var yaw := 0.0
var pitch := 0.0
var third_person := false
var aim_yaw := 0.0
var club_index := 0
## 0..OVERSWING while the mouse button is held.
var backswing := 0.0
## Sideways mouse wobble collected during the backswing; becomes hook/slice.
var drift := 0.0

var _holding := false
var _down := false
var _hit_sent := false
var _swing_angle := 0.0
var _power := 0.0
var _walk_phase := 0.0
## Where the ball was when we addressed it; the stance stays put after the hit.
var _anchor := Vector3.ZERO

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _shoulder: Node3D
var _swing: Node3D
var _club_head: MeshInstance3D


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = capsule
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4

	camera = Camera3D.new()
	camera.top_level = true
	camera.fov = 75.0
	camera.near = 0.08
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	_build_body()
	_refresh_club()


# ---------------------------------------------------------------- state

func in_swing() -> bool:
	return _holding or _down


func address(target: Vector2) -> void:
	var to := target - Vector2(ball.position.x, ball.position.z)
	aim_yaw = atan2(-to.x, -to.y)
	pitch = 0.0
	backswing = 0.0
	drift = 0.0
	_anchor = ball.position
	_holding = false
	_down = false
	_swing_angle = 0.0
	velocity = Vector3.ZERO
	mode = Mode.ADDRESS


func step_away() -> void:
	if mode != Mode.ADDRESS:
		return
	mode = Mode.FREE
	yaw = aim_yaw
	pitch = 0.0
	backswing = 0.0
	_holding = false
	_down = false
	_swing_angle = 0.0


func set_club(index: int) -> void:
	club_index = posmod(index, Clubs.LIST.size())
	_refresh_club()
	club_changed.emit()


func start_backswing() -> void:
	if mode == Mode.ADDRESS and not in_swing():
		_holding = true
		backswing = 0.0
		drift = 0.0


func release_swing() -> void:
	if not _holding:
		return
	_holding = false
	if backswing < 0.04:
		backswing = 0.0
		return
	_power = minf(backswing, 1.0)
	_down = true
	_hit_sent = false


func cancel_swing() -> void:
	_holding = false
	backswing = 0.0


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		if mode == Mode.FREE:
			yaw -= rel.x * LOOK_SENS
			pitch = clampf(pitch - rel.y * LOOK_SENS, -1.4, 1.4)
		elif _holding:
			drift += rel.x / 240.0
		elif not _down:
			aim_yaw -= rel.x * AIM_SENS
			pitch = clampf(pitch - rel.y * LOOK_SENS, -0.5, 0.5)
	elif event is InputEventMouseButton and mode == Mode.ADDRESS:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					start_backswing()
				else:
					release_swing()
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if _holding:
						cancel_swing()
					elif not _down:
						step_away()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed and not in_swing():
					set_club(club_index - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed and not in_swing():
					set_club(club_index + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V:
			third_person = not third_person
		elif mode == Mode.ADDRESS and not in_swing() \
				and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_8:
			set_club(event.physical_keycode - KEY_1)


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if mode == Mode.ADDRESS:
		_update_address(delta)
	else:
		_update_walk(delta)
	_animate(delta)
	_update_camera()


func _update_walk(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var dir := (Basis(Vector3.UP, yaw) * input).normalized()
	var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_physical_key_pressed(KEY_SPACE) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	rotation.y = yaw
	# Keep everyone on the property.
	var p := global_position
	p.x = clampf(p.x, Course.X_MIN + 2.0, Course.X_MAX - 2.0)
	p.z = clampf(p.z, Course.Z_MIN + 2.0, Course.Z_MAX - 2.0)
	var ground := course.height_at(p.x, p.z)
	if p.y < ground - 0.5:
		p.y = ground + 0.1
	global_position = p
	var moved := Vector2(velocity.x, velocity.z).length()
	_walk_phase = _walk_phase + moved * delta * 1.9 if moved > 0.2 else 0.0


func _update_address(delta: float) -> void:
	var aim := Clubs.aim_dir(aim_yaw)
	var facing := aim.cross(Vector3.UP)
	var stand := _anchor - facing * STANCE
	stand.y = course.height_at(stand.x, stand.z)
	if _anchor.y > course.deck_at(stand.x, stand.z) - 0.4:
		stand.y = maxf(stand.y, course.deck_at(stand.x, stand.z))
	global_position = stand
	rotation.y = atan2(-facing.x, -facing.z)
	velocity = Vector3.ZERO

	if _holding:
		backswing = minf(backswing + delta / BACKSWING_TIME, OVERSWING)
		_swing_angle = backswing * TOP_ANGLE
	elif _down:
		_swing_angle -= DOWNSWING_SPEED * delta
		if _swing_angle <= 0.0 and not _hit_sent:
			_hit_sent = true
			struck.emit(_power, drift)
		if _swing_angle <= FINISH_ANGLE:
			_swing_angle = FINISH_ANGLE
			_down = false
			backswing = 0.0
			# Hold the finish for a beat, then let the player go find it.
			get_tree().create_timer(0.7).timeout.connect(step_away)
	elif backswing == 0.0 and _swing_angle > 0.0:
		_swing_angle = maxf(0.0, _swing_angle - DOWNSWING_SPEED * 0.3 * delta)


func _animate(_delta: float) -> void:
	var addressing := mode == Mode.ADDRESS
	_body.visible = addressing or third_person
	_shoulder.visible = addressing
	_arm_l.visible = not addressing
	_arm_r.visible = not addressing
	var stride := sin(_walk_phase) * 0.7
	_leg_l.rotation.x = stride if not addressing else 0.0
	_leg_r.rotation.x = -stride if not addressing else 0.0
	_arm_l.rotation.x = -stride * 0.8
	_arm_r.rotation.x = stride * 0.8
	_swing.rotation.z = _swing_angle


func _update_camera() -> void:
	if mode == Mode.ADDRESS:
		var aim := Clubs.aim_dir(aim_yaw)
		var right := aim.cross(Vector3.UP)
		var pos := _anchor - aim * 3.4 + right * 0.45 + Vector3(0, 1.6, 0)
		pos.y = maxf(pos.y, course.height_at(pos.x, pos.z) + 0.7)
		pos.y = maxf(pos.y, course.deck_at(pos.x, pos.z) + 0.7)
		camera.global_position = pos
		camera.look_at(_anchor + aim * 12.0 + Vector3(0, 1.0 + pitch * 10.0, 0))
		return
	var head := global_position + Vector3(0, 1.62, 0)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	if third_person:
		var pos := head + basis.z * 3.6 + Vector3(0, 0.5, 0)
		pos.y = maxf(pos.y, course.height_at(pos.x, pos.z) + 0.4)
		camera.global_transform = Transform3D(basis, pos)
	else:
		camera.global_transform = Transform3D(basis, head)


# ---------------------------------------------------------------- model

func _build_body() -> void:
	var skin := Color(0.93, 0.74, 0.58)
	var shirt := Color(0.86, 0.22, 0.30)
	var trousers := Color(0.20, 0.24, 0.42)
	var white := Color(0.95, 0.95, 0.92)
	_body = Node3D.new()
	add_child(_body)

	_leg_l = _pivot(_body, Vector3(-0.13, 0.80, 0))
	_box(_leg_l, Vector3(0.19, 0.80, 0.21), trousers, Vector3(0, -0.40, 0))
	_box(_leg_l, Vector3(0.20, 0.10, 0.30), white, Vector3(0, -0.76, -0.05))
	_leg_r = _pivot(_body, Vector3(0.13, 0.80, 0))
	_box(_leg_r, Vector3(0.19, 0.80, 0.21), trousers, Vector3(0, -0.40, 0))
	_box(_leg_r, Vector3(0.20, 0.10, 0.30), white, Vector3(0, -0.76, -0.05))

	_box(_body, Vector3(0.50, 0.62, 0.28), shirt, Vector3(0, 1.11, 0))
	_box(_body, Vector3(0.30, 0.30, 0.30), skin, Vector3(0, 1.58, 0))
	_box(_body, Vector3(0.33, 0.10, 0.33), white, Vector3(0, 1.76, 0))
	_box(_body, Vector3(0.30, 0.03, 0.16), white, Vector3(0, 1.72, -0.22))

	_arm_l = _pivot(_body, Vector3(-0.32, 1.38, 0))
	_box(_arm_l, Vector3(0.13, 0.60, 0.13), skin, Vector3(0, -0.30, 0))
	_arm_r = _pivot(_body, Vector3(0.32, 1.38, 0))
	_box(_arm_r, Vector3(0.13, 0.60, 0.13), skin, Vector3(0, -0.30, 0))

	# Address arms + club: hang down and forward from the shoulders, and
	# rotate around the forward axis to swing.
	_shoulder = _pivot(_body, Vector3(0, 1.35, -0.05))
	_shoulder.rotation.x = deg_to_rad(35.0)
	_swing = _pivot(_shoulder, Vector3.ZERO)
	var a1 := _box(_swing, Vector3(0.12, 0.64, 0.12), skin, Vector3(-0.13, -0.29, 0))
	a1.rotation.z = deg_to_rad(-22.0)
	var a2 := _box(_swing, Vector3(0.12, 0.64, 0.12), skin, Vector3(0.13, -0.29, 0))
	a2.rotation.z = deg_to_rad(22.0)
	_box(_swing, Vector3(0.03, 1.0, 0.03), Color(0.7, 0.7, 0.72), Vector3(0, -1.08, 0))
	_club_head = _box(_swing, Vector3(0.12, 0.07, 0.07), Color(0.15, 0.15, 0.17), Vector3(-0.05, -1.58, 0))


func _refresh_club() -> void:
	var box: BoxMesh = _club_head.mesh
	if club_index <= 1:
		box.size = Vector3(0.20, 0.11, 0.16)       # woods
	elif club_index == Clubs.PUTTER:
		box.size = Vector3(0.05, 0.05, 0.20)
	else:
		box.size = Vector3(0.13, 0.07, 0.06)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi
