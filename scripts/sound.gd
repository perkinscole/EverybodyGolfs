extends Node
## All audio is synthesised here at startup: there are no sound files.
## play() is for sounds without a position, play_at() for sounds in the world.

const RATE := 22050
const MUSIC_RATE := 11025
const BPM := 72.0

var streams := {}
var music: AudioStreamPlayer
var course: Node3D

var _rng := RandomNumberGenerator.new()
var _flat: Array = []
var _spatial: Array = []
var _bird_wait := 4.0
var _music_thread: Thread
var _music_on := true


func _ready() -> void:
	_rng.seed = 2024
	_build_effects()
	# The music takes a few seconds to write, so do it off the main thread.
	_music_thread = Thread.new()
	_music_thread.start(_compose_music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 140.0
		add_child(p)
		_spatial.append(p)
	music = AudioStreamPlayer.new()
	music.volume_db = -15.0
	add_child(music)
	if course != null:
		_add_water_loop(Vector3(course.bridge_center.x, course.water_y, course.bridge_center.y))
		_add_water_loop(Vector3(course.pond_center.x, course.water_y, course.pond_center.y))


func _compose_music() -> void:
	var stream := _wav(_compose(), MUSIC_RATE, true)
	_music_ready.call_deferred(stream)


func _music_ready(stream: AudioStreamWAV) -> void:
	_music_thread.wait_to_finish()
	streams["music"] = stream
	music.stream = stream
	music.play()
	music.stream_paused = not _music_on


func _exit_tree() -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()


func _process(delta: float) -> void:
	# The odd bird, somewhere off in the trees.
	_bird_wait -= delta
	if _bird_wait <= 0.0:
		_bird_wait = _rng.randf_range(3.0, 11.0)
		play("bird", _rng.randf_range(-26.0, -17.0), _rng.randf_range(0.8, 1.35))


func toggle_music() -> bool:
	_music_on = not _music_on
	music.stream_paused = not _music_on
	return _music_on


func play(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _free_player(_flat)
	p.stream = streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_at(key: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer3D = _free_player(_spatial)
	p.stream = streams[key]
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _add_water_loop(at: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams["river"]
	p.position = at
	p.unit_size = 7.0
	p.max_distance = 60.0
	p.volume_db = -8.0
	add_child(p)
	p.play()


# ---------------------------------------------------------------- synthesis

func _wav(samples: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	# Leave headroom: scale anything that would clip.
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	for i in samples.size():
		bytes.encode_s16(i * 2, int(samples[i] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Add a decaying sine that glides from f0 to f1.
func _tone(b: PackedFloat32Array, start: float, length: float, f0: float, f1: float,
		amp: float, decay: float) -> void:
	var first := int(start * RATE)
	var count := mini(int(length * RATE), b.size() - first)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, float(i) / count) / RATE
		b[first + i] += sin(phase) * amp * exp(-t * decay) * minf(t * 400.0, 1.0)


## Add decaying noise through a one-pole low-pass (smooth 0 = raw, near 1 = dull).
func _noise(b: PackedFloat32Array, start: float, length: float, amp: float, decay: float,
		smooth: float, attack: float = 0.0) -> void:
	var first := int(start * RATE)
	var count := mini(int(length * RATE), b.size() - first)
	var held := 0.0
	for i in count:
		var t := float(i) / RATE
		held = lerpf(_rng.randf_range(-1.0, 1.0), held, smooth)
		var env := exp(-t * decay)
		if attack > 0.0:
			env *= minf(t / attack, 1.0)
		b[first + i] += held * amp * env


func _build_effects() -> void:
	var b := _buffer(0.3)                      # swish of the downswing
	_noise(b, 0.0, 0.3, 0.5, 9.0, 0.55, 0.12)
	streams["swish"] = _wav(b)

	b = _buffer(0.4)                           # driver: a hollow crack
	_noise(b, 0.0, 0.05, 0.9, 90.0, 0.1)
	_tone(b, 0.0, 0.3, 420.0, 260.0, 0.6, 26.0)
	_tone(b, 0.0, 0.2, 1900.0, 1500.0, 0.35, 45.0)
	streams["drive"] = _wav(b)

	b = _buffer(0.3)                           # iron: brighter click
	_noise(b, 0.0, 0.04, 0.8, 110.0, 0.05)
	_tone(b, 0.0, 0.2, 2600.0, 2300.0, 0.4, 40.0)
	_tone(b, 0.0, 0.2, 700.0, 500.0, 0.4, 38.0)
	streams["iron"] = _wav(b)

	b = _buffer(0.15)                          # putter tap
	_tone(b, 0.0, 0.12, 950.0, 880.0, 0.5, 70.0)
	_noise(b, 0.0, 0.02, 0.3, 200.0, 0.2)
	streams["putt"] = _wav(b)

	b = _buffer(0.25)                          # ball landing on turf
	_tone(b, 0.0, 0.2, 120.0, 65.0, 0.9, 28.0)
	_noise(b, 0.0, 0.08, 0.35, 60.0, 0.8)
	streams["thud"] = _wav(b)

	b = _buffer(0.2)                           # path, bridge, anything hard
	_tone(b, 0.0, 0.15, 520.0, 430.0, 0.6, 50.0)
	_noise(b, 0.0, 0.02, 0.5, 220.0, 0.1)
	streams["clack"] = _wav(b)

	b = _buffer(0.3)                           # bunker
	_noise(b, 0.0, 0.3, 0.7, 20.0, 0.45, 0.01)
	streams["sand"] = _wav(b)

	b = _buffer(0.9)                           # water
	_noise(b, 0.0, 0.9, 0.8, 5.5, 0.72, 0.03)
	_tone(b, 0.0, 0.25, 330.0, 110.0, 0.5, 14.0)
	_tone(b, 0.12, 0.2, 520.0, 260.0, 0.25, 22.0)
	streams["splash"] = _wav(b)

	b = _buffer(0.2)                           # tree trunk
	_tone(b, 0.0, 0.15, 640.0, 600.0, 0.6, 45.0)
	_tone(b, 0.0, 0.15, 980.0, 940.0, 0.35, 55.0)
	streams["knock"] = _wav(b)

	b = _buffer(0.4)                           # through the leaves
	_noise(b, 0.0, 0.4, 0.5, 9.0, 0.3, 0.03)
	streams["rustle"] = _wav(b)

	b = _buffer(0.45)                          # into the cup
	for k in 3:
		_tone(b, k * 0.07, 0.12, 1350.0 - k * 220.0, 1250.0 - k * 220.0, 0.5 - k * 0.1, 60.0)
	_tone(b, 0.18, 0.25, 310.0, 290.0, 0.4, 18.0)
	streams["cup"] = _wav(b)

	b = _buffer(1.2)                           # holed out
	var fanfare := [523.25, 659.25, 783.99, 1046.5]
	for k in fanfare.size():
		_tone(b, k * 0.11, 0.8, fanfare[k], fanfare[k], 0.28, 5.0)
	streams["fanfare"] = _wav(b)

	b = _buffer(0.7)                           # penalty
	_tone(b, 0.0, 0.3, 311.0, 311.0, 0.35, 7.0)
	_tone(b, 0.22, 0.45, 233.0, 220.0, 0.35, 6.0)
	streams["penalty"] = _wav(b)

	b = _buffer(0.08)                          # footsteps
	_noise(b, 0.0, 0.08, 0.5, 55.0, 0.75)
	streams["step_grass"] = _wav(b)
	b = _buffer(0.08)
	_noise(b, 0.0, 0.05, 0.5, 90.0, 0.3)
	_tone(b, 0.0, 0.06, 260.0, 200.0, 0.4, 60.0)
	streams["step_hard"] = _wav(b)

	b = _buffer(0.5)                           # bird
	for k in 3:
		_tone(b, k * 0.13, 0.09, 3100.0 + k * 250.0, 4300.0 - k * 150.0, 0.4, 14.0)
	streams["bird"] = _wav(b)

	streams["baa"] = _wav(_voice(0.7, 330.0, 300.0, 9.0, 0.6))
	streams["moo"] = _wav(_voice(1.1, 150.0, 112.0, 0.0, 0.85))
	b = _buffer(0.3)                           # chicken
	for k in 2:
		_tone(b, k * 0.13, 0.08, 780.0, 520.0, 0.5, 30.0)
	streams["cluck"] = _wav(b)
	var quack := _voice(0.16, 560.0, 480.0, 0.0, 0.35)
	quack.append_array(_voice(0.2, 520.0, 430.0, 0.0, 0.35))
	streams["quack"] = _wav(quack)

	# River: three seconds of soft noise, cross-faded so the loop has no seam.
	var count := RATE * 3
	var fade := RATE / 2
	var raw := PackedFloat32Array()
	raw.resize(count + fade)
	var held := 0.0
	var slow := 0.0
	for i in raw.size():
		held = lerpf(_rng.randf_range(-1.0, 1.0), held, 0.82)
		slow = lerpf(_rng.randf_range(-1.0, 1.0), slow, 0.97)
		raw[i] = (held * 0.6 + slow * 1.2) * (0.75 + 0.25 * sin(i * TAU * 3.0 / count))
	var river := PackedFloat32Array()
	river.resize(count)
	for i in count:
		river[i] = raw[i]
		if i < fade:
			river[i] = lerpf(raw[count + i], raw[i], float(i) / fade)
	streams["river"] = _wav(river, RATE, true)


## A buzzy animal voice: a sawtooth with a wobble, low-passed.
func _voice(seconds: float, f0: float, f1: float, tremolo: float, smooth: float) -> PackedFloat32Array:
	var b := _buffer(seconds)
	var phase := 0.0
	var held := 0.0
	for i in b.size():
		var u := float(i) / b.size()
		phase = fmod(phase + lerpf(f0, f1, u) / RATE, 1.0)
		var env := sin(u * PI) ** 0.6
		if tremolo > 0.0:
			env *= 0.65 + 0.35 * sin(u * seconds * tremolo * TAU)
		held = lerpf(phase * 2.0 - 1.0, held, smooth)
		b[i] = held * env * 0.7
	return b


# ---------------------------------------------------------------- music

## A slow, sparse electric-piano loop: eight bars, four chords, played twice
## with a different top line the second time.
func _compose() -> PackedFloat32Array:
	var beat := 60.0 / BPM
	var bars := 8
	var out := PackedFloat32Array()
	out.resize(int(bars * 4 * beat * MUSIC_RATE))
	# [bass, arpeggio notes...] as MIDI numbers.
	var chords := [
		[36, 64, 67, 71, 74],      # C maj9
		[33, 60, 64, 67, 71],      # A min9
		[29, 57, 60, 64, 69],      # F maj7
		[31, 59, 62, 64, 69],      # G 6/9
	]
	var tops := [[79, 76], [76, 72], [72, 77], [74, 71], [83, 79], [79, 76], [81, 77], [74, 79]]
	var steps := [0.0, 0.5, 1.0, 2.0, 2.5]
	for bar in bars:
		var chord: Array = chords[bar % 4]
		var t0 := bar * 4.0 * beat
		_piano(out, t0, chord[0], 0.20, 0.9)
		_piano(out, t0 + 2.0 * beat, chord[0] + 12, 0.08, 1.4)
		for k in 4:
			var order := k if bar % 2 == 0 else (k * 3) % 4
			_piano(out, t0 + steps[k + 1] * beat, chord[1 + order], 0.085, 1.5)
		_piano(out, t0 + 3.0 * beat, tops[bar][0], 0.075, 1.3)
		if bar % 2 == 1:
			_piano(out, t0 + 3.5 * beat, tops[bar][1], 0.06, 1.3)
	return out


## One note, added into the loop; the tail wraps round to the start.
func _piano(out: PackedFloat32Array, start: float, midi: int, amp: float, decay: float) -> void:
	var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var first := int(start * MUSIC_RATE)
	var count := int(3.2 * MUSIC_RATE)
	var w := TAU * freq / MUSIC_RATE
	var size := out.size()
	for i in count:
		var t := float(i) / MUSIC_RATE
		var env := exp(-t * decay) * minf(t * 220.0, 1.0)
		var s := sin(w * i) + 0.32 * sin(2.0 * w * i) * exp(-t * 3.0) + 0.10 * sin(3.0 * w * i) * exp(-t * 6.0)
		out[(first + i) % size] += s * amp * env
