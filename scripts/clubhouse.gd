extends Node3D
## The clubhouse: a blocky timber building you start inside. The door faces
## -Z, toward the first tee. Origin is the centre of the floor.

const Blocks = preload("res://scripts/blocks.gd")

const W := 16.0      # along x
const D := 10.0      # along z
const H := 4.0
const T := 0.4       # wall thickness
const DOOR_W := 2.2
const DOOR_H := 2.8
const FLOOR_TOP := 0.08


func _ready() -> void:
	var planks := Blocks.mat("planks", Color(0.72, 0.56, 0.36), 0.04, "planks")
	var dark_wood := Blocks.mat("dark_wood", Color(0.38, 0.26, 0.16), 0.04, "planks")
	var stone := Blocks.mat("stone", Color(0.55, 0.55, 0.56), 0.05, "bricks")
	var roof := Blocks.mat("roof", Color(0.58, 0.20, 0.16), 0.04, "bricks")
	var glass := Blocks.plain(Color(0.55, 0.78, 0.92))
	var body := StaticBody3D.new()
	add_child(body)

	# Floor and foundation.
	Blocks.solid_box(self, body, Vector3(W, 0.6, D), dark_wood, Vector3(0, FLOOR_TOP - 0.3, 0))
	Blocks.box(self, Vector3(W + 0.6, 0.5, D + 0.6), stone, Vector3(0, -0.3, 0))

	# Walls. The front has a doorway.
	var front_z := -D * 0.5 + T * 0.5
	var seg := (W - DOOR_W) * 0.5
	Blocks.solid_box(self, body, Vector3(W, H, T), planks, Vector3(0, H * 0.5, D * 0.5 - T * 0.5))
	for side in [-1.0, 1.0]:
		Blocks.solid_box(self, body, Vector3(T, H, D), planks, Vector3(side * (W * 0.5 - T * 0.5), H * 0.5, 0))
		Blocks.solid_box(self, body, Vector3(seg, H, T), planks,
			Vector3(side * (DOOR_W * 0.5 + seg * 0.5), H * 0.5, front_z))
		# Windows, front and side.
		Blocks.box(self, Vector3(2.4, 1.4, T + 0.1), glass, Vector3(side * 4.6, 2.1, front_z))
		Blocks.box(self, Vector3(T + 0.1, 1.4, 2.6), glass, Vector3(side * (W * 0.5 - T * 0.5), 2.1, 0))
		# Corner posts.
		for zs in [-1.0, 1.0]:
			Blocks.box(self, Vector3(0.6, H, 0.6), dark_wood,
				Vector3(side * (W * 0.5 - 0.2), H * 0.5, zs * (D * 0.5 - 0.2)))
	Blocks.solid_box(self, body, Vector3(DOOR_W, H - DOOR_H, T), planks,
		Vector3(0, DOOR_H + (H - DOOR_H) * 0.5, front_z))
	Blocks.box(self, Vector3(DOOR_W + 0.5, 0.25, T + 0.2), dark_wood, Vector3(0, DOOR_H + 0.12, front_z))

	# Stepped roof and chimney.
	for i in 6:
		Blocks.box(self, Vector3(W + 1.6, 0.6, D + 2.0 - i * 2.2), roof, Vector3(0, H + 0.3 + i * 0.6, 0))
	Blocks.box(self, Vector3(1.2, 4.0, 1.2), stone, Vector3(5.0, H + 2.0, 1.6))

	# Porch.
	var porch_z := -D * 0.5 - 1.6
	Blocks.solid_box(self, body, Vector3(8.0, 0.3, 3.2), dark_wood, Vector3(0, FLOOR_TOP - 0.17, porch_z))
	Blocks.box(self, Vector3(8.8, 0.25, 3.8), roof, Vector3(0, 3.2, porch_z))
	for px in [-3.8, 3.8]:
		Blocks.solid_box(self, body, Vector3(0.3, 3.2, 0.3), dark_wood, Vector3(px, 1.6, porch_z - 1.4))

	var sign := Label3D.new()
	sign.text = "CLUBHOUSE"
	sign.font_size = 96
	sign.pixel_size = 0.006
	sign.modulate = Color(0.98, 0.95, 0.85)
	sign.outline_size = 24
	sign.outline_modulate = Color(0.15, 0.10, 0.06)
	sign.position = Vector3(0, 3.55, -D * 0.5 - 0.08)
	sign.rotation.y = PI
	add_child(sign)

	_build_interior(body, planks, dark_wood)


func _build_interior(body: StaticBody3D, planks: Material, dark_wood: Material) -> void:
	var back := D * 0.5 - T
	# Pro shop counter and shelves of stock.
	Blocks.solid_box(self, body, Vector3(4.6, 1.1, 0.9), dark_wood, Vector3(-4.4, FLOOR_TOP + 0.55, 1.6))
	Blocks.box(self, Vector3(4.8, 0.1, 1.1), planks, Vector3(-4.4, FLOOR_TOP + 1.15, 1.6))
	for shelf_y in [1.0, 1.8, 2.6]:
		Blocks.box(self, Vector3(5.0, 0.1, 0.5), dark_wood, Vector3(-4.4, shelf_y, back - 0.25))
	var stock := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2),
		Color(0.95, 0.95, 0.95), Color(0.3, 0.7, 0.4)]
	for i in 12:
		Blocks.box(self, Vector3(0.3, 0.3, 0.3), Blocks.plain(stock[i % stock.size()]),
			Vector3(-6.5 + (i % 6) * 0.8, 1.2 + int(i / 6.0) * 0.8, back - 0.25))
	# Rug, bench, a bag of clubs by the door.
	Blocks.box(self, Vector3(4.5, 0.04, 3.0), Blocks.mat("rug", Color(0.60, 0.16, 0.18), 0.04,
		"patches", Color(0.85, 0.72, 0.40)), Vector3(2.5, FLOOR_TOP + 0.02, 0.5))
	Blocks.solid_box(self, body, Vector3(3.0, 0.45, 0.7), planks, Vector3(4.5, FLOOR_TOP + 0.22, back - 0.5))
	Blocks.box(self, Vector3(0.45, 1.0, 0.45), Blocks.plain(Color(0.15, 0.30, 0.55)),
		Vector3(2.0, FLOOR_TOP + 0.5, -D * 0.5 + T + 0.5))
	for i in 3:
		Blocks.box(self, Vector3(0.05, 0.5, 0.05), Blocks.plain(Color(0.75, 0.75, 0.78)),
			Vector3(1.88 + i * 0.12, FLOOR_TOP + 1.2, -D * 0.5 + T + 0.5))

	var board := Label3D.new()
	board.text = "TODAY\nHole 1   Par 4\nMind the sheep"
	board.font_size = 64
	board.pixel_size = 0.006
	board.modulate = Color(0.95, 0.95, 0.90)
	board.position = Vector3(3.5, 2.6, back - 0.12)
	board.rotation.y = PI
	add_child(board)
	Blocks.box(self, Vector3(3.6, 1.6, 0.1), Blocks.plain(Color(0.12, 0.22, 0.16)), Vector3(3.5, 2.6, back - 0.05))

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.3, 0)
	lamp.omni_range = 13.0
	lamp.light_energy = 1.3
	lamp.light_color = Color(1.0, 0.86, 0.66)
	add_child(lamp)
