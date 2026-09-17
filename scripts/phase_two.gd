extends Node

# Fase 2 (boton 02): escudo gravitatorio, sincronizado con "Interfacing".
#
# La pista va a ~100 BPM: un compas cada 2.4 s y el bombo en el primer tiempo
# de cada compas desde 10.68 s. Todo se agenda por el tiempo de la pista
# (game_music.gd track_time), asi la cinematica no se desfasa.
#
#   1.08   intro: franjas, "PHASE 02 // GRAVITY SHIELD"; los lasers se cargan
#   5.88   aparece la semilla de energia en el centro
#   10.68  bombos: disparan los lasers laterales, uno por golpe
#   20.28  corte al centro: disparan los diagonales, la reticula se teje
#   29.88  reticula completa; ondas en cada golpe
#   39.48  corte a la sala: los monitores enlazan el escudo
#   44.28  corte al monitor central
#   49.08  suben los agudos: IGNICION del escudo
#   58.68  plano general: el campo se estabiliza
#   68.28  corte al centro; 75.48 convergencia
#   77.88  climax: escudo estable
#   82.68  salen las franjas, vuelta al panel; la musica queda de fondo

const PHASE := 2
const BAR := 2.4
const FIRST_BAR := 1.08
const KICKS_FROM := 10.68
## Tiempo que tarda un corte rapido (speed 2) en tapar la pantalla.
const CUT_LEAD := 0.23

@export var panel: Node
@export var views: Node
@export var bars: Node
@export var music: Node
@export var sim: Node
@export var shield: Node3D
@export_file("*.mp3", "*.ogg", "*.wav") var track_path: String = ""
@export_range(-30.0, 0.0, 0.5) var track_volume_db: float = -7.0
## Volumen de la pista cuando termina la cinematica (sigue sonando).
@export_range(-40.0, 0.0, 0.5) var background_volume_db: float = -22.0
@export var lateral_lasers: Array[Node] = []
@export var diagonal_lasers: Array[Node] = []
@export var cinematic_view: StringName = &"Window"
@export var monitors_view: StringName = &"Room"
@export var monitor_view: StringName = &"MonitorCentral"
@export var return_view: StringName = &"Panel"

var _dolly: Tween

func _ready() -> void:
	if panel:
		panel.register_phase(PHASE)
		panel.phase_started.connect(_on_phase_started)
	_register_shots.call_deferred()

## Planos de la cinematica, alrededor del escudo.
func _register_shots() -> void:
	if views == null or shield == null:
		return
	var c := shield.global_position
	views.register_view(&"CineCenter",
		Transform3D().looking_at(Vector3(-0.85, -0.4, -1.0)).translated(c + Vector3(0.85, 0.4, 1.0)))
	views.register_view(&"CineWide",
		Transform3D().looking_at(Vector3(1.4, -1.25, -1.05)).translated(c + Vector3(-1.4, 1.25, 1.05)))
	views.register_view(&"CineLow",
		Transform3D().looking_at(Vector3(-0.5, 0.75, -1.1)).translated(c + Vector3(0.5, -0.75, 1.1)))

func _on_phase_started(index: int) -> void:
	if index == PHASE:
		_run()

func _run() -> void:
	music.play_track(music.load_stream(track_path), track_volume_db)
	await _wait_frames(2)
	views.cinematic = true
	views.go_to(cinematic_view)
	for l in lateral_lasers + diagonal_lasers:
		l.charge_up(1.25, 6.0)

	# --- Intro ---------------------------------------------------------------
	await _at(FIRST_BAR)
	bars.show_bars("PHASE 02 // GRAVITY SHIELD")
	_dolly = views.dolly(Vector3(0.0, 0.03, -0.25), 9.0)
	await _at(_bar(2))
	shield.visible = true
	shield.seed_to(0.04, 0.6, 1.5)
	await _at(_bar(3))
	bars.set_caption("FIELD EMITTERS // SYNC")

	# --- A: los laterales disparan con el bombo --------------------------------
	for i in lateral_lasers.size():
		await _at(KICKS_FROM + i * BAR)
		_fire(lateral_lasers[i], 1.4)
		shield.seed_to(0.06 + 0.025 * i, 0.8 + 0.1 * i, 0.3)
		views.shake(0.004, 0.18)
	await _at(KICKS_FROM + 3 * BAR)
	for l in lateral_lasers:
		l.pulse(1.2)
	shield.seed_to(0.14, 1.2, 0.35)
	shield.flash(0.6)
	views.shake(0.006, 0.25)
	bars.set_caption("LATERAL LOCK")

	# --- B: corte al centro; los diagonales tejen la reticula ------------------
	await _cut(&"CineCenter", _bar(8))
	bars.set_caption("DIAGONAL ARRAY // LATTICE")
	for i in diagonal_lasers.size():
		await _at(_bar(8 + i))
		_fire(diagonal_lasers[i], 1.2)
		shield.build_to(0.25 * (i + 1), 1.4)
		shield.ripple(_dir_from(diagonal_lasers[i]))
		shield.seed_to(0.15 + 0.01 * i, 1.3, 0.25)
		views.shake(0.003, 0.15)
	await _at(_bar(12))
	bars.set_caption("LATTICE 100%")
	shield.flash(0.8)
	_pulse_all(1.0)
	shield.density_to(0.12, 4.0)
	for k in [13, 14, 15]:
		await _at(_bar(k))
		shield.ripple(_random_dir())
		_pulse_all(0.6)
	await _at(_bar(16) - 1.2)
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.15), 6.0)

	# --- Telemetria ------------------------------------------------------------
	await _cut(monitors_view, _bar(16))
	bars.set_caption("TELEMETRY // SHIELD LINK")
	if sim:
		sim.shield_forming = true
		sim.shield_online = true
	shield.density_to(0.25, 6.0)
	await _cut(monitor_view, _bar(18))

	# --- C: ignicion ------------------------------------------------------------
	await _cut(cinematic_view, _bar(20))
	bars.set_caption("SHIELD IGNITION", Color(1.0, 0.52, 0.14))
	shield.flash(1.8)
	shield.density_to(0.75, 0.6)
	shield.seed_to(0.2, 1.6, 0.4)
	_pulse_all(1.6)
	for l in lateral_lasers + diagonal_lasers:
		l.set_beam(1.6, 0.3)
	views.shake(0.012, 0.5)
	_play("shield_ignite")
	for k in [21, 22, 23]:
		await _at(_bar(k))
		shield.ripple(_random_dir())
		shield.flash(0.5)
		_pulse_all(0.8)
		views.shake(0.004, 0.15)

	# --- D: el campo se estabiliza ----------------------------------------------
	await _cut(&"CineWide", _bar(24))
	bars.set_caption("STABILIZING FIELD")
	_dolly = views.dolly(Vector3(0.12, -0.05, -0.2), 11.0)
	for l in lateral_lasers + diagonal_lasers:
		l.set_beam(0.9, 2.0)
	shield.density_to(0.55, 4.0)
	for k in [26, 28]:
		await _at(_bar(k))
		shield.ripple(_random_dir())
		_pulse_all(0.5)
	await _cut(&"CineLow", _bar(28) + BAR * 0.5)
	await _at(_bar(30))
	shield.ripple(_random_dir())
	await _at(_bar(31))
	bars.set_caption("CONVERGENCE")
	# Tension: todo sube hacia el climax.
	for l in lateral_lasers + diagonal_lasers:
		l.set_beam(1.8, BAR)
		l.charge_up(1.6, BAR)
	shield.density_to(0.85, BAR)
	shield.seed_to(0.24, 2.0, BAR)

	# --- Climax -------------------------------------------------------------------
	await _cut(&"CineCenter", _bar(32))
	shield.flash(2.0)
	_pulse_all(2.0)
	views.shake(0.014, 0.6)
	_play("shield_ignite", 2.0, 0.8)
	shield.density_to(0.6, 3.0)
	shield.seed_to(0.16, 1.1, 2.0)
	for l in lateral_lasers + diagonal_lasers:
		l.set_beam(0.7, 2.5)
		l.charge_up(1.1, 3.0)
	if sim:
		sim.shield_forming = false
	bars.set_caption("SHIELD STABLE", bars.ok_color)

	await _at(_bar(34))
	await bars.hide_bars()
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	views.cinematic = false
	music.duck_track(background_volume_db, 4.0)
	await views.go_to(return_view)
	panel.complete_phase(PHASE)

# --- Ayudas -----------------------------------------------------------------------

func _bar(n: int) -> float:
	return FIRST_BAR + n * BAR

## Espera hasta el segundo `t` de la pista.
func _at(t: float) -> void:
	while music.is_track_playing() and music.track_time() < t:
		await get_tree().process_frame

## Corte rapido que destapa justo en `t`.
func _cut(view: StringName, t: float) -> void:
	await _at(t - CUT_LEAD)
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	views.go_to(view, 2.0)
	await _at(t)

func _fire(laser: Node, intensity: float) -> void:
	laser.fire(shield.global_position, intensity)

func _pulse_all(amount: float) -> void:
	for l in lateral_lasers + diagonal_lasers:
		l.pulse(amount)

func _dir_from(laser: Node) -> Vector3:
	return (laser.tip_position() - shield.global_position).normalized()

func _random_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if views and views.sfx:
		views.sfx.play(sound, volume_db, pitch)

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
