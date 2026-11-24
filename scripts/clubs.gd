extends RefCounted
## Club data and the maths that turns a swing into a ball velocity.

const LIST := [
	{"name": "Driver", "speed": 80.0, "loft": 11.5, "spin": 1.0},
	{"name": "3 Wood", "speed": 71.0, "loft": 13.5, "spin": 1.0},
	{"name": "5 Iron", "speed": 59.0, "loft": 17.0, "spin": 1.0},
	{"name": "7 Iron", "speed": 52.0, "loft": 21.0, "spin": 1.0},
	{"name": "9 Iron", "speed": 45.0, "loft": 26.0, "spin": 1.0},
	{"name": "Pitching Wedge", "speed": 39.0, "loft": 31.0, "spin": 1.0},
	{"name": "Sand Wedge", "speed": 32.0, "loft": 38.0, "spin": 1.0},
	{"name": "Putter", "speed": 7.5, "loft": 0.0, "spin": 0.0},
]

const PUTTER := 7
const SAND_WEDGE := 6


## Direction on the ground for a yaw angle (0 = looking down -Z).
static func aim_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## power is 0..1 (how far back the club went), lie_mult scales for bad lies.
static func shot_velocity(club: Dictionary, power: float, yaw: float, lie_mult: float = 1.0) -> Vector3:
	var speed: float = club["speed"] * (0.08 + 0.92 * clampf(power, 0.0, 1.0)) * lie_mult
	var loft: float = deg_to_rad(club["loft"])
	return (aim_dir(yaw) * cos(loft) + Vector3.UP * sin(loft)) * speed
