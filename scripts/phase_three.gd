extends Node

# Fase 3 (boton 03): la singularidad, sincronizada con "Singularity" (~140 BPM,
# compas de 1.714 s). La pista sube desde el silencio, tiene una seccion
# fuerte, un corte, golpes de bajo enormes y un drop electrico en 58.55 s:
# ahi nace el agujero negro.
#
#   0.0    corte a la sala; APAGON en cascada durante la subida (todo, menos
#          los lasers, que quedan tenues)
#   5.0    corte al ventanal: se apaga el exterior por filas
#   10.0   seccion fuerte: compresion gravitatoria (el escudo se achica, los
#          haces al maximo, la semilla crece)
#   31.0   corte: masa critica; la semilla implosiona y se oscurece
#   39.6   vuelve la musica: aparece un horizonte de sucesos diminuto
#   43.5 / 45.25 / 47.25   golpes de bajo: el horizonte crece
#   48.5   corte: acrecion; el disco empieza a girar y a formarse
#   58.55  DROP: nace la singularidad (disco encendido, destello, sacudida);
#          los monitores reciben sus datos; cortes rapidos cada 2 compases
#   79.1   "SINGULARITY STABLE"; 82.5 vuelta al panel (se destapan las
#          palancas). Las luces quedan apagadas.

const PHASE := 3
const BAR := 60.0 / 140.0 * 4.0
const DROP := 58.55
const CUT_LEAD := 0.23

@export var panel: Node
@export var views: Node
@export var bars: Node
@export var music: Node
@export var sim: Node
@export var shield: Node3D
@export var lighting: Node
@export var driver: Node
@export_file("*.mp3", "*.ogg", "*.wav") var track_path: String = ""
@export_range(-30.0, 0.0, 0.5) var track_volume_db: float = -6.0
@export_range(-40.0, 0.0, 0.5) var background_volume_db: float = -20.0
@export var lateral_lasers: Array[Node] = []
@export var diagonal_lasers: Array[Node] = []
@export var return_view: StringName = &"Panel"

var _dolly: Tween

func _ready() -> void:
	if panel:
		panel.register_phase(PHASE)
		panel.phase_started.connect(_on_phase_started)

func _on_phase_started(index: int) -> void:
	if index == PHASE:
		_run()

func _run() -> void:
	var bh: Node3D = driver.black_hole
	music.play_track(music.load_stream(track_path), track_volume_db)
	await _frames(2)
	views.cinematic = true
	views.go_to(&"Room")

	# --- Apagon ---------------------------------------------------------------
	await _at(0.9)
	bars.show_bars("PHASE 03 // SINGULARITY")
	await _at(1.8)
	lighting.blackout()
	await _cut(&"Window", 5.0)
	bars.set_caption("POWER REROUTE // ALL SYSTEMS")
	_dolly = views.dolly(Vector3(0.0, 0.02, -0.2), 5.0)

	# --- Compresion gravitatoria -------------------------------------------------
	await _cut(&"CineCenter", 10.0)
	bars.set_caption("GRAVITATIONAL COMPRESSION")
	shield.compress_to(0.8, 21.0)
	shield.seed_to(0.26, 2.2, 21.0)
	shield.density_to(0.75, 6.0)
	for l in _all_lasers():
		l.set_beam(1.5, 2.0)
	_on_bars(10.0, 31.0, 2, func(i: int) -> void:
		shield.ripple(_random_dir())
		_pulse(0.6 + 0.1 * (i % 3)))
	await _cut(&"CineWide", 17.0)
	_dolly = views.dolly(Vector3(0.1, -0.04, -0.2), 7.0)
	await _cut(&"CineLow", 24.0)
	_dolly = views.dolly(Vector3(0.0, 0.05, -0.25), 7.0)

	# --- Masa critica: la semilla implosiona -------------------------------------
	await _cut(&"CineCenter", 31.0)
	bars.set_caption("CRITICAL MASS")
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.35), 8.0)
	for l in _all_lasers():
		l.set_beam(0.35, 3.0)
	var implode := create_tween().set_parallel()
	implode.tween_property(shield, "seed_energy", 0.0, 5.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	implode.tween_property(shield, "seed_size", 0.02, 5.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	shield.density_to(0.3, 5.0)
	if sim:
		sim.singularity_forming = true

	# --- Horizonte de sucesos ----------------------------------------------------
	await _at(39.6)
	driver.prepare()
	shield.seed_to(0.0, 0.0, 0.2)
	bh.sphere_radius = 0.012
	shield.flash(0.9)
	_pulse(1.2)
	views.shake(0.005, 0.3)
	bars.set_caption("EVENT HORIZON DETECTED", Color(1.0, 0.52, 0.14))
	for l in _all_lasers():
		l.set_beam(1.0, 0.5)
		l.beam_stop = 0.07
	for hit in [[43.5, 0.02], [45.25, 0.028], [47.25, 0.04]]:
		await _at(hit[0])
		_grow(bh, "sphere_radius", hit[1], 0.35)
		shield.ripple(_random_dir())
		shield.flash(0.6)
		_pulse(1.0)
		views.shake(0.008 if hit[0] > 47.0 else 0.005, 0.35)
		_play("beam_fire", -4.0, 0.6)

	# --- Acrecion ---------------------------------------------------------------
	await _cut(&"Window", 48.5)
	bars.set_caption("ACCRETION")
	bh.swirl_speed = 0.4
	var accrete := create_tween().set_parallel()
	accrete.tween_property(bh, "disc_radius", 0.28, 10.0).set_trans(Tween.TRANS_SINE)
	accrete.tween_property(bh, "disc_opacity", 0.18, 10.0)
	accrete.tween_property(bh, "disc_brightness", 0.8, 10.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	accrete.tween_property(bh, "swirl_speed", 2.2, 10.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for l in _all_lasers():
		l.set_beam(1.6, 9.0)
	await _cut(&"CineCenter", 53.0)
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.3), 5.5)
	await _at(DROP - 1.2)
	shield.compress_to(1.0, 1.2)

	# --- DROP: nace la singularidad ---------------------------------------------
	await _at(DROP)
	bh.sphere_radius = 0.06
	bh.disc_radius = 0.4
	bh.disc_opacity = 0.42
	bh.disc_brightness = 6.0
	_grow(bh, "disc_brightness", 2.2, 1.5)
	shield.flash(2.0)
	shield.compress_to(0.35, 3.0)
	_pulse(2.0)
	views.shake(0.016, 0.7)
	_play("shield_ignite", 3.0, 0.7)
	bars.set_caption("SINGULARITY BORN", Color(1.0, 0.52, 0.14))
	for l in _all_lasers():
		l.set_beam(0.8, 2.0)
		l.beam_stop = 0.36
	# El escudo cede el protagonismo al agujero negro.
	var calm := create_tween()
	calm.tween_interval(2.5)
	calm.tween_property(shield, "brightness", 0.45, 6.0).set_trans(Tween.TRANS_SINE)
	shield.density_to(0.3, 8.0)
	if sim:
		sim.singularity_forming = false
		sim.singularity_online = true
	get_tree().create_timer(1.6, false).timeout.connect(func() -> void: driver.alive = true)

	# Cortes rapidos cada 2 compases.
	# El ultimo (79.1 s) termina en el primer plano del agujero negro.
	var shots := [&"Window", &"CineWide", &"Room", &"MonitorCentral", &"CineLow", &"CineCenter"]
	for i in shots.size():
		await _cut(shots[i], DROP + BAR * 2 * (i + 1))
		if i < 4:
			_pulse(0.9)
			shield.ripple(_random_dir())

	await _at(79.1)
	bars.set_caption("SINGULARITY STABLE", bars.ok_color)
	await _at(82.5)
	await bars.hide_bars()
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	views.cinematic = false
	music.duck_track(background_volume_db, 4.0)
	await views.go_to(return_view)
	panel.complete_phase(PHASE)

# --- Ayudas -----------------------------------------------------------------------

func _all_lasers() -> Array:
	return lateral_lasers + diagonal_lasers

func _at(t: float) -> void:
	while music.is_track_playing() and music.track_time() < t:
		await get_tree().process_frame

func _cut(view: StringName, t: float) -> void:
	await _at(t - CUT_LEAD)
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	views.go_to(view, 2.0)
	await _at(t)

## Llama `action(i)` cada `every` compases entre `from` y `to` (en paralelo).
func _on_bars(from: float, to: float, every: int, action: Callable) -> void:
	var i := 0
	var t := from
	while t < to:
		await _at(t)
		action.call(i)
		i += 1
		t += BAR * every

func _pulse(amount: float) -> void:
	for l in _all_lasers():
		l.pulse(amount)

func _grow(obj: Object, prop: String, value: float, time: float) -> void:
	create_tween().tween_property(obj, prop, value, time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _random_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if views and views.sfx:
		views.sfx.play(sound, volume_db, pitch)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
