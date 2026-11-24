extends SceneTree
## Headless check of the course and ball physics.
## Run: godot --headless -s tests/sim.gd

const Course = preload("res://scripts/course.gd")
const Ball = preload("res://scripts/ball.gd")
const Clubs = preload("res://scripts/clubs.gd")
const Sound = preload("res://scripts/sound.gd")

var course: Course
var ball: Ball
var events: Array = []


func _initialize() -> void:
	course = Course.new()
	root.add_child(course)
	ball = Ball.new()
	ball.course = course
	root.add_child(ball)
	ball.set_physics_process(false)
	ball.holed.connect(func(): events.append("holed"))
	ball.hazard.connect(func(kind): events.append(kind))
	await process_frame

	print("hole length: %.0f m, trees: %d" % [course.hole_length(), course.trees.size()])
	var failures := 0

	print("-- full swings from the tee, aimed down the fairway")
	for club in Clubs.LIST:
		ball.place(course.tee)
		ball.launch(Clubs.shot_velocity(club, 1.0, 0.0), 0.0, club["spin"])
		_run()
		var start := course.ground_point(course.tee)
		var carry := 0.0
		if ball.first_landing != Vector3.INF:
			carry = Vector2(ball.first_landing.x - start.x, ball.first_landing.z - start.z).length()
		var total := Vector2(ball.position.x - start.x, ball.position.z - start.z).length()
		print("%-15s carry %5.1f  total %5.1f  air %4.1fs" % [club["name"], carry, total, ball.flight_time])

	print("-- bot plays the hole")
	seed(42)
	ball.place(course.tee)
	events.clear()
	var strokes := 0
	var last := course.tee
	while strokes < 15 and not events.has("holed"):
		var here := Vector2(ball.position.x, ball.position.z)
		var to_pin := course.pin - here
		var dist := to_pin.length()
		var yaw := atan2(-to_pin.x, -to_pin.y)
		var surface := course.surface_at(here.x, here.y)
		var club: Dictionary = Clubs.LIST[Clubs.PUTTER]
		var power := 1.0
		if surface == Course.Surface.GREEN:
			# v^2 = 2 a d, a little firm so it reaches the hole.
			power = clampf((sqrt(2.0 * 0.85 * (dist + 0.4)) / 7.5 - 0.08) / 0.92, 0.02, 1.0)
		else:
			var reach := [215.0, 195.0, 170.0, 148.0, 125.0, 105.0, 78.0]
			var idx := 6
			for i in reach.size():
				if reach[i] <= dist + 8.0:
					idx = i
					break
			club = Clubs.LIST[idx]
			power = clampf(dist / reach[idx], 0.15, 1.0)
		last = here
		events.clear()
		ball.launch(Clubs.shot_velocity(club, power, yaw + deg_to_rad(randfn(0.0, 1.5))), 0.0, club["spin"])
		_run()
		strokes += 1
		var result := "rests %.1f m from pin" % Vector2(ball.position.x - course.pin.x, ball.position.z - course.pin.y).length()
		if events.has("holed"):
			result = "HOLED"
		elif not events.is_empty():
			result = "%s, replay" % events[0]
			strokes += 1
			ball.place(last)
		print("stroke %2d  %-15s power %.2f  from %-7s -> %s" % [
			strokes, club["name"], power, Course.Surface.keys()[surface], result])
	if not events.has("holed"):
		print("FAIL: bot did not hole out")
		failures += 1

	print("-- audio")
	var sound := Sound.new()
	root.add_child(sound)
	var waited := 0
	while not sound.streams.has("music") and waited < 2000:
		await process_frame
		waited += 1
	for key in sound.streams:
		var stream: AudioStreamWAV = sound.streams[key]
		var peak := 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		if stream.data.size() < 200 or peak < 1500 or peak >= 32767:
			print("FAIL: %s  bytes %d  peak %d" % [key, stream.data.size(), peak])
			failures += 1
	print("%d sounds, music loop %.1f s" % [sound.streams.size(), sound.streams["music"].get_length()])

	print("OK" if failures == 0 else "FAILED")
	quit(failures)


func _run() -> void:
	var steps := 0
	while ball.moving and steps < 60 * 120:
		ball.simulate(1.0 / 60.0)
		steps += 1
