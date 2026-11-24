extends SceneTree
## Drives the real game scene through a hole and saves screenshots.
## Run under a display:
##   xvfb-run -a godot --path . -s tests/playthrough.gd -- <output dir>

const Clubs = preload("res://scripts/clubs.gd")
const Player = preload("res://scripts/player.gd")

var main: Node
var out_dir := "user://"
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	seed(7)
	var player: Player = main.player
	var ball = main.ball
	var course = main.course

	await _shot("01_clubhouse")
	_check(not main.can_address(), "cannot address from the clubhouse")

	# Walk to the tee.
	player.global_position = course.ground_point(course.tee + Vector2(-1.2, 1.5)) + Vector3(0, 0.1, 0)
	player.yaw = 0.0
	player.pitch = -0.15
	await _frames(20)
	await _shot("02_on_the_tee")
	_check(main.can_address(), "can address on the tee")

	main.interact()
	_check(player.mode == Player.Mode.ADDRESS, "addressing")
	await _frames(10)
	await _shot("03_address")
	player.start_backswing()
	await _frames(55)
	await _shot("04_backswing")
	await _frames(30)
	player.release_swing()
	await _frames(12)
	await _shot("05_ball_away")
	_check(main.strokes == 1 and ball.moving, "tee shot is in the air")
	await _until(func(): return not ball.moving, 1200)
	_check(player.mode == Player.Mode.FREE, "player released after the swing")
	_check(main.search_time >= 0.0, "search clock running")
	await _frames(30)
	await _shot("06_searching")

	# Third-person look at the golfer mid-fairway.
	player.third_person = true
	player.global_position = course.ground_point(Vector2(2, -90)) + Vector3(0, 0.1, 0)
	player.yaw = 0.25
	await _frames(15)
	await _shot("07_third_person")
	player.third_person = false

	# Play on until holed, walking (teleporting) to the ball each time.
	var guard := 0
	while not main.hole_done and guard < 14:
		guard += 1
		await _until(func(): return not ball.moving, 1500)
		if main.hole_done:
			break
		var here := Vector2(ball.position.x, ball.position.z)
		player.global_position = course.ground_point(here + Vector2(0.8, 1.2)) + Vector3(0, 0.1, 0)
		await _frames(5)
		_check(main.can_address(), "can address shot %d" % (main.strokes + 1))
		main.interact()
		var dist: float = here.distance_to(course.pin)
		var power := 1.0
		if course.surface_at(here.x, here.y) == course.Surface.GREEN:
			_check(player.club_index == Clubs.PUTTER, "putter auto-selected on the green")
			power = clampf((sqrt(2.0 * 0.85 * (dist + 0.4)) / 7.5 - 0.08) / 0.92, 0.03, 1.0)
		else:
			var reach := [215.0, 195.0, 170.0, 148.0, 125.0, 105.0, 78.0]
			var idx := 6
			for i in reach.size():
				if reach[i] <= dist + 8.0:
					idx = i
					break
			player.set_club(idx)
			power = clampf(dist / reach[idx], 0.15, 1.0)
		if guard == 1:
			await _frames(5)
			await _shot("08_approach_address")
		player.start_backswing()
		await _until(func(): return player.backswing >= power, 200)
		player.release_swing()
		await _frames(30)
		if course.surface_at(here.x, here.y) == course.Surface.GREEN and guard < 5:
			await _shot("09_putt_%d" % guard)
	_check(main.hole_done, "holed out (strokes: %d)" % main.strokes)
	await _frames(20)
	await _shot("10_holed")

	print("PLAYTHROUGH OK" if failures == 0 else "PLAYTHROUGH FAILED (%d)" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _until(cond: Callable, max_frames: int) -> void:
	var n := 0
	while not cond.call() and n < max_frames:
		await physics_frame
		n += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
