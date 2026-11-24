extends Node3D
## Game flow for a single hole: walk from the clubhouse, hit, hunt for the
## ball against the clock, hole out.

const Course = preload("res://scripts/course.gd")
const Ball = preload("res://scripts/ball.gd")
const Player = preload("res://scripts/player.gd")
const Clubs = preload("res://scripts/clubs.gd")

const SEARCH_LIMIT := 120.0
const FIND_RADIUS := 3.0
const ADDRESS_RADIUS := 2.5
const HELP_TEXT := """WASD walk    Shift run    Space jump    V third person
E address the ball / step away
At the ball: mouse aims, wheel or 1-8 picks a club
Hold left mouse to take the club back, release to swing
Keep the mouse still in the backswing or you will hook or slice it
Right mouse cancels    Tab scorecard    Esc frees the mouse"""

var course: Course
var ball: Ball
var player: Player
var strokes := 0
var hole_done := false
## Seconds spent looking for the ball, or -1 when not searching.
var search_time := -1.0

var _last_shot := Vector2.ZERO
var _prompt: Label
var _club: Label
var _timer: Label
var _message: Label
var _card: Label
var _help: Label
var _message_left := 0.0


func _ready() -> void:
	_build_environment()
	course = Course.new()
	add_child(course)
	ball = Ball.new()
	ball.course = course
	add_child(ball)
	player = Player.new()
	player.course = course
	player.ball = ball
	add_child(player)
	_build_hud()

	ball.stopped.connect(_on_ball_stopped)
	ball.holed.connect(_on_ball_holed)
	ball.hazard.connect(_on_ball_hazard)
	player.struck.connect(_on_struck)
	player.club_changed.connect(_refresh_club_label)
	_start_hole()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	say("First tee is straight ahead.  H for controls", 6.0)


func _start_hole() -> void:
	strokes = 0
	hole_done = false
	search_time = -1.0
	ball.place(course.tee)
	ball.set_beacon(false)
	_last_shot = course.tee
	player.step_away()
	player.set_club(0)
	player.global_position = course.ground_point(course.clubhouse + Vector2(0, -8)) + Vector3(0, 0.1, 0)
	player.yaw = 0.3
	player.pitch = 0.0


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_E:
			interact()
		KEY_H:
			_help.visible = not _help.visible
		KEY_R:
			if hole_done:
				_start_hole()
		KEY_B:
			# Development aid: light up the ball.
			ball.set_beacon(not ball.beacon_on())


func can_address() -> bool:
	return not hole_done and not ball.moving and player.mode == Player.Mode.FREE \
		and player.global_position.distance_to(ball.position) < ADDRESS_RADIUS


func interact() -> void:
	if player.mode == Player.Mode.ADDRESS:
		if not player.in_swing():
			player.step_away()
	elif can_address():
		search_time = -1.0
		ball.set_beacon(false)
		player.address(course.pin)
		if course.surface_at(ball.position.x, ball.position.z) == Course.Surface.GREEN:
			player.set_club(Clubs.PUTTER)
		_refresh_club_label()


# ---------------------------------------------------------------- shots

func _on_struck(power: float, drift: float) -> void:
	var club: Dictionary = Clubs.LIST[player.club_index]
	var lie := course.surface_at(ball.position.x, ball.position.z)
	var lie_mult := 1.0
	var scatter := 1.2
	var putting := player.club_index == Clubs.PUTTER
	if lie == Course.Surface.ROUGH:
		lie_mult = 0.35 if putting else randf_range(0.68, 0.9)
		scatter = 4.5
	elif lie == Course.Surface.BUNKER:
		if putting:
			lie_mult = 0.2
		elif player.club_index == Clubs.SAND_WEDGE:
			lie_mult = 0.85
		else:
			lie_mult = randf_range(0.3, 0.6)
		scatter = 5.0
	if putting:
		scatter = 0.4
	# Overswinging buys nothing but trouble.
	var over := maxf(player.backswing - 1.0, 0.0)
	scatter += over * 20.0
	var curve := clampf(drift + randfn(0.0, 0.05 + over), -1.5, 1.5)
	var yaw := player.aim_yaw + deg_to_rad(randfn(0.0, scatter)) - curve * deg_to_rad(2.0)
	if putting:
		curve = 0.0
		yaw = player.aim_yaw + deg_to_rad(randfn(0.0, scatter)) - drift * deg_to_rad(3.0)
	_last_shot = Vector2(ball.position.x, ball.position.z)
	strokes += 1
	search_time = -1.0
	ball.set_beacon(false)
	ball.launch(Clubs.shot_velocity(club, power, yaw, lie_mult), curve, club["spin"])


func _on_ball_stopped() -> void:
	search_time = 0.0


func _on_ball_holed() -> void:
	hole_done = true
	search_time = -1.0
	say("%s\n%d %s on a par %d.   R to head back to the clubhouse" % [
		score_name(strokes, Course.PAR), strokes,
		"stroke" if strokes == 1 else "strokes", Course.PAR], 600.0)


func _on_ball_hazard(kind: String) -> void:
	strokes += 1
	ball.place(_last_shot)
	ball.set_beacon(true)
	search_time = -1.0
	say("%s.  One stroke penalty, play it again from the same spot" % kind.capitalize(), 5.0)


func _lose_ball() -> void:
	strokes += 1
	search_time = -1.0
	ball.place(course.nearest_fairway_point(Vector2(ball.position.x, ball.position.z)))
	ball.set_beacon(true)
	say("Lost ball.  One stroke penalty, take your drop at the marker", 5.0)


static func score_name(count: int, par: int) -> String:
	if count == 1:
		return "HOLE IN ONE"
	match count - par:
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double bogey"
		3: return "Triple bogey"
	return "%+d" % (count - par)


# ---------------------------------------------------------------- hud

func say(text: String, seconds: float) -> void:
	_message.text = text
	_message_left = seconds


func _process(delta: float) -> void:
	if search_time >= 0.0:
		if player.global_position.distance_to(ball.position) < FIND_RADIUS:
			search_time = -1.0
		else:
			search_time += delta
			if search_time >= SEARCH_LIMIT:
				_lose_ball()

	var addressing := player.mode == Player.Mode.ADDRESS
	_prompt.text = "E   address the ball" if can_address() else ""
	_club.visible = addressing
	_timer.visible = search_time >= 0.0
	if _timer.visible:
		var left := int(ceil(SEARCH_LIMIT - search_time))
		_timer.text = "%d:%02d" % [left / 60, left % 60]
		_timer.modulate = Color(1, 0.4, 0.3) if left <= 20 else Color.WHITE
	_card.visible = Input.is_physical_key_pressed(KEY_TAB)
	if _card.visible:
		_card.text = "Hole 1     Par %d     %d m\nStrokes  %d" % [
			Course.PAR, int(round(course.hole_length())), strokes]
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.text = ""


func _refresh_club_label() -> void:
	_club.text = Clubs.LIST[player.club_index]["name"]


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_prompt = _label(root, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, -40))
	_club = _label(root, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Vector2(12, -12))
	_timer = _label(root, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(-12, 10))
	_message = _label(root, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 50))
	_card = _label(root, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, Vector2.ZERO)
	_help = _label(root, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_LEFT, Vector2(0, 30))
	_help.text = HELP_TEXT
	_help.visible = false


func _label(parent: Control, preset: int, align: int, offset: Vector2) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = 12
	settings.outline_size = 4
	settings.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = settings
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if align == HORIZONTAL_ALIGNMENT_LEFT and preset != Control.PRESET_CENTER:
		l.grow_horizontal = Control.GROW_DIRECTION_END
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	if preset == Control.PRESET_CENTER_BOTTOM or preset == Control.PRESET_BOTTOM_LEFT:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif preset == Control.PRESET_CENTER_TOP or preset == Control.PRESET_TOP_RIGHT:
		l.grow_vertical = Control.GROW_DIRECTION_END
	l.position += offset
	return l


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.52, 0.86)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.93)
	sky_mat.ground_horizon_color = Color(0.74, 0.85, 0.93)
	sky_mat.ground_bottom_color = Color(0.30, 0.42, 0.30)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.85, 0.93)
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
