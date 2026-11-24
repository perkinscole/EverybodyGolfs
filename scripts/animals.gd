extends Node3D
## Blocky wildlife. Sheep, cows and chickens wander their patch, bolt when
## you get close, and get in the way of golf balls. Ducks circle the pond.

const Blocks = preload("res://scripts/blocks.gd")

var course: Node3D
var player: Node3D
var ball: Node3D
## Each: {node, kind, home, target, state, timer, speed, scare, radius,
## height, legs, phase, hop, hop_v, dir, cooldown, angle}
var animals: Array = []

var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
	_rng.seed = 777
	_spawn_herd("sheep", 7, Vector2(-38, -85), 14.0)
	_spawn_herd("cow", 5, Vector2(60, -105), 15.0)
	_spawn_herd("sheep", 4, Vector2(-30, -275), 12.0)
	_spawn_herd("chicken", 7, Vector2(31, 30), 9.0)
	_spawn_herd("chicken", 4, Vector2(70, -300), 8.0)
	for i in 3:
		_add("duck", course.pond_center, 0.0).merge({"angle": i * TAU / 3.0}, true)


func _spawn_herd(kind: String, count: int, around: Vector2, spread: float) -> void:
	var home := _open_ground(around, 30.0)
	for i in count:
		var a := _add(kind, home, spread)
		var p := _open_ground(home + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread)), 6.0)
		a["node"].position = course.ground_point(p)
		a["node"].rotation.y = _rng.randf() * TAU


## Nearest-ish spot that is rough, dry, clear of trees and ideally open meadow.
func _open_ground(around: Vector2, search: float) -> Vector2:
	for attempt in 60:
		var p := around + Vector2(_rng.randf_range(-search, search), _rng.randf_range(-search, search)) * (attempt / 60.0)
		if not course.in_bounds(p.x, p.y, 6.0) or course.surface_at(p.x, p.y) != course.Surface.ROUGH:
			continue
		if course.forest_at(p) > 0.0 and attempt < 45:
			continue
		var clear := true
		for t in course.trees:
			var tp: Vector3 = t["pos"]
			if Vector2(tp.x, tp.z).distance_to(p) < 3.0:
				clear = false
				break
		if clear:
			return p
	return around


func _add(kind: String, home: Vector2, spread: float) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var a := {
		"node": node, "kind": kind, "home": home, "spread": spread, "target": home,
		"state": "idle", "timer": _rng.randf_range(0.5, 5.0), "legs": [],
		"phase": 0.0, "hop": 0.0, "hop_v": 0.0, "dir": Vector2(0, -1), "cooldown": 0.0, "angle": 0.0,
	}
	match kind:
		"sheep":
			a.merge({"speed": 1.1, "scare": 4.5, "radius": 0.85, "height": 1.2})
			_build_sheep(a)
		"cow":
			a.merge({"speed": 0.8, "scare": 3.0, "radius": 1.1, "height": 1.5})
			_build_cow(a)
		"chicken":
			a.merge({"speed": 1.4, "scare": 5.0, "radius": 0.4, "height": 0.6})
			_build_chicken(a)
		"duck":
			a.merge({"speed": 0.0, "scare": 0.0, "radius": 0.4, "height": 0.4})
			_build_duck(a)
	animals.append(a)
	return a


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	_time += delta
	var player_at := Vector2(player.global_position.x, player.global_position.z)
	for a in animals:
		var node: Node3D = a["node"]
		if a["kind"] == "duck":
			a["angle"] += delta * 0.22
			var ang: float = a["angle"]
			var r: Vector2 = course.pond_radii * 0.5
			node.position = Vector3(course.pond_center.x + cos(ang) * r.x,
				course.water_y - 0.08 + sin(_time * 2.0 + ang) * 0.03, course.pond_center.y + sin(ang) * r.y)
			node.rotation.y = atan2(sin(ang) * r.x, -cos(ang) * r.y)
			_ball_bump(a)
			continue

		var at := Vector2(node.position.x, node.position.z)
		a["cooldown"] = maxf(a["cooldown"] - delta, 0.0)
		a["timer"] -= delta
		if a["state"] != "flee" and at.distance_to(player_at) < a["scare"]:
			_flee(a, at - player_at)

		var moving := false
		var speed: float = a["speed"]
		match a["state"]:
			"idle":
				if a["timer"] <= 0.0:
					var home: Vector2 = a["home"]
					var spread: float = a["spread"]
					a["target"] = home + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
					a["state"] = "walk"
					a["timer"] = 12.0
			"walk":
				var to: Vector2 = a["target"] - at
				if to.length() < 0.5 or a["timer"] <= 0.0:
					_idle(a)
				else:
					a["dir"] = to.normalized()
					moving = true
			"flee":
				speed *= 3.2
				moving = true
				if a["timer"] <= 0.0:
					_idle(a)

		if moving:
			var dir: Vector2 = a["dir"]
			var next := at + dir * speed * delta
			if course.in_bounds(next.x, next.y, 4.0) and course.surface_at(next.x, next.y) != course.Surface.WATER \
					and course.water_distance(next) > 0.8:
				at = next
				a["phase"] += speed * delta * 5.0
			else:
				_idle(a)
				moving = false
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.y), minf(delta * 7.0, 1.0))

		a["hop_v"] -= 16.0 * delta
		a["hop"] = maxf(a["hop"] + a["hop_v"] * delta, 0.0)
		if a["hop"] == 0.0:
			a["hop_v"] = 0.0
		node.position = Vector3(at.x, course.height_at(at.x, at.y) + a["hop"], at.y)
		var swing := sin(a["phase"]) * 0.6 if moving else 0.0
		var legs: Array = a["legs"]
		for i in legs.size():
			legs[i].rotation.x = swing if i % 2 == 0 else -swing
		_ball_bump(a)


func _idle(a: Dictionary) -> void:
	a["state"] = "idle"
	a["timer"] = _rng.randf_range(2.0, 8.0)


func _flee(a: Dictionary, away: Vector2) -> void:
	if away.length() < 0.01:
		away = Vector2(1, 0)
	a["dir"] = away.normalized().rotated(_rng.randf_range(-0.5, 0.5))
	a["state"] = "flee"
	a["timer"] = _rng.randf_range(1.2, 2.2)


## A moving ball that hits an animal bounces off, and the animal is not pleased.
func _ball_bump(a: Dictionary) -> void:
	if not ball.moving or a["cooldown"] > 0.0:
		return
	var node: Node3D = a["node"]
	var height: float = a["height"]
	var centre := node.position + Vector3(0, height * 0.5, 0)
	var offset: Vector3 = ball.position - centre
	if offset.length() > a["radius"]:
		return
	var n := offset.normalized() if offset.length() > 0.01 else Vector3.UP
	n.y = maxf(n.y, 0.25)
	n = n.normalized()
	var v: Vector3 = ball.velocity
	if v.dot(n) < 0.0:
		v = v.bounce(n)
	ball.velocity = v * 0.4 + Vector3(0, 2.0, 0)
	ball.airborne = true
	a["cooldown"] = 1.0
	a["hop_v"] = 5.5
	if a["kind"] != "duck":
		_flee(a, Vector2(-offset.x, -offset.z))


# ---------------------------------------------------------------- models
# All models face -Z with feet at y = 0.

func _legs(a: Dictionary, size: Vector3, material: Material, x: float, z_front: float, z_back: float, top: float) -> void:
	for spot in [Vector2(-x, z_front), Vector2(x, z_front), Vector2(x, z_back), Vector2(-x, z_back)]:
		var hip := Blocks.pivot(a["node"], Vector3(spot.x, top, spot.y))
		Blocks.box(hip, size, material, Vector3(0, -size.y * 0.5, 0))
		a["legs"].append(hip)


func _build_sheep(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	var wool := Blocks.mat("wool", Color(0.93, 0.92, 0.88), 0.05, "spots", Color(0.82, 0.81, 0.76), 3.0)
	var face := Blocks.plain(Color(0.28, 0.24, 0.22))
	Blocks.box(node, Vector3(0.9, 0.75, 1.3), wool, Vector3(0, 0.88, 0))
	Blocks.box(node, Vector3(0.42, 0.42, 0.45), face, Vector3(0, 1.05, -0.8))
	Blocks.box(node, Vector3(0.50, 0.25, 0.30), wool, Vector3(0, 1.28, -0.72))
	_legs(a, Vector3(0.18, 0.55, 0.18), face, 0.28, -0.42, 0.42, 0.55)


func _build_cow(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	var hide := Blocks.mat("cowhide", Color(0.95, 0.94, 0.90), 0.03, "patches", Color(0.25, 0.17, 0.12), 0.8)
	var pink := Blocks.plain(Color(0.92, 0.70, 0.68))
	var horn := Blocks.plain(Color(0.88, 0.85, 0.75))
	var dark := Blocks.plain(Color(0.22, 0.16, 0.12))
	Blocks.box(node, Vector3(1.0, 0.9, 1.8), hide, Vector3(0, 1.15, 0))
	Blocks.box(node, Vector3(0.6, 0.6, 0.6), hide, Vector3(0, 1.4, -1.1))
	Blocks.box(node, Vector3(0.45, 0.28, 0.2), pink, Vector3(0, 1.25, -1.45))
	for hx in [-0.35, 0.35]:
		Blocks.box(node, Vector3(0.1, 0.22, 0.1), horn, Vector3(hx, 1.78, -1.05))
	Blocks.box(node, Vector3(0.4, 0.2, 0.5), pink, Vector3(0, 0.62, 0.45))
	_legs(a, Vector3(0.24, 0.72, 0.24), dark, 0.32, -0.62, 0.62, 0.72)


func _build_chicken(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	var white := Blocks.plain(Color(0.96, 0.95, 0.92))
	var yellow := Blocks.plain(Color(0.95, 0.72, 0.15))
	var red := Blocks.plain(Color(0.85, 0.15, 0.15))
	Blocks.box(node, Vector3(0.34, 0.34, 0.48), white, Vector3(0, 0.42, 0))
	Blocks.box(node, Vector3(0.22, 0.28, 0.22), white, Vector3(0, 0.68, -0.24))
	Blocks.box(node, Vector3(0.12, 0.08, 0.14), yellow, Vector3(0, 0.66, -0.40))
	Blocks.box(node, Vector3(0.06, 0.10, 0.16), red, Vector3(0, 0.86, -0.24))
	Blocks.box(node, Vector3(0.20, 0.20, 0.10), white, Vector3(0, 0.55, 0.26))
	for lx in [-0.09, 0.09]:
		var hip := Blocks.pivot(node, Vector3(lx, 0.26, 0))
		Blocks.box(hip, Vector3(0.05, 0.26, 0.05), yellow, Vector3(0, -0.13, 0))
		a["legs"].append(hip)


func _build_duck(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	var brown := Blocks.plain(Color(0.50, 0.38, 0.25))
	var green := Blocks.plain(Color(0.12, 0.42, 0.25))
	var yellow := Blocks.plain(Color(0.95, 0.72, 0.15))
	Blocks.box(node, Vector3(0.34, 0.24, 0.52), brown, Vector3(0, 0.14, 0))
	Blocks.box(node, Vector3(0.2, 0.24, 0.2), green, Vector3(0, 0.38, -0.2))
	Blocks.box(node, Vector3(0.14, 0.06, 0.16), yellow, Vector3(0, 0.34, -0.36))
