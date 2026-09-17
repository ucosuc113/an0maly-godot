extends Node

# Crisis y finales, despues de la fase 3 (palancas desbloqueadas).
#
#   CONGELAMIENTO (freeze): energia al minimo (laterales y diagonales en 1) y
#     refrigeracion al maximo (ventiladores y escudo en 5) sostenidas unos
#     segundos -> la singularidad se congela y colapsa sin danos -> reinicio.
#
#   DERRETIMIENTO (meltdown): nucleo sobrecalentado (o escudo roto) sostenido
#     -> suena "Kinetic Energy" COMPLETA mientras todo se descontrola. El
#     jugador sigue al mando hasta el punto de no retorno (175 s):
#       - si vuelve a subir la refrigeracion (ventiladores y escudo >= 4), la
#         musica se va y en 30 s todo queda estable -> final "catastrofe
#         evitada" (sin reinicio; puede provocar otro derretimiento despues).
#       - si no, en 175 s la camara se toma el control: el escudo estalla, el
#         agujero negro crece hasta tragarse el mapa, implosiona y explota en
#         el ultimo golpe (199.5 s) -> reinicio.
#
#   APAGADO DE EMERGENCIA (shutdown): pendiente (falta el modelo).
#
# La pista de derretimiento va a ~90 BPM (compas de 2.667 s): los golpes de
# camara y de energia van a ese pulso.

enum State { IDLE, FREEZE, MELTDOWN, STABILIZING, CLIMAX, ENDING }

const BEAT := 60.0 / 90.0
const BAR := BEAT * 4.0
const NO_RETURN := 175.0
const CLIMAX_T := 178.5
const FINAL_HIT := 199.5
const CUT_LEAD := 0.23
## Desde aqui (mitad del camino al no retorno) empiezan las ondas expansivas.
const WAVES_FROM := NO_RETURN * 0.5
## Con menos de 20 s, el agujero empieza a tragarse cosas.
## [tiempo, tipo, dato]: laser -> orden de indices en `lasers` (0-2
## laterales, 3-6 diagonales); lights -> cuantas; wave -> fuerza.
const PRE_DEVOUR := [
	[156.0, "laser", [4, 3]],
	[160.5, "lights", 2],
	[162.0, "blade", 0],
	[164.5, "laser", [2, 1]],
	[167.5, "lights", 3],
	[170.0, "laser", [6, 5]],
]
const CLIMAX_HUNGER := [
	[178.5, "wave", 1.6],
	[180.0, "blade", 0],
	[181.4, "laser", [0, 1, 2]],
	[182.4, "lights", 3],
	[183.9, "wave", 1.3],
	[185.0, "laser", [3, 4, 5, 6]],
	[186.6, "blade", 0],
	[186.9, "blade", 0],
	[187.5, "lights", 4],
	[188.2, "laser", [0, 1, 2]],
	[189.3, "wave", 1.5],
	[189.6, "laser", [6, 5, 4, 3]],
	[190.8, "lights", 6],
	[191.9, "wave", 1.4],
	[192.2, "prop", "left_monitor"],
	[192.4, "laser", [0, 1, 2, 3, 4, 5, 6]],
	[193.2, "blade", 0],
	[193.6, "prop", "crystal"],
	[194.0, "lights", 30],
	[194.6, "wave", 1.8],
	[195.0, "all", 0],
	[196.0, "wave", 2.0],
	[197.2, "wave", 2.0],
	[198.2, "wave", 2.4],
]

## Cuanto se inclina el disco en el climax (para verlo de frente).
const DISC_TILT := Vector3(35.0, 0.0, 10.0)

@export var panel: Node
@export var sim: Node
@export var views: Node
@export var bars: Node
@export var music: Node
@export var driver: Node
@export var shield: Node3D
@export var lighting: Node
@export var endings: Node
@export var overlay: Node
@export var restore: Node
## ColorRect a pantalla completa (FlashLayer) para el destello final.
@export var flash: ColorRect
@export var sfx: Node
@export var settings: Node
@export var lasers: Array[Node] = []
## singularity_hunger.gd: ondas expansivas y cosas que se traga.
@export var hunger: Node
## Piezas que se traga al final.
@export var crystal: Node3D
@export var left_monitor: Node3D
@export_file("*.mp3", "*.ogg", "*.wav") var meltdown_track: String = ""
@export_range(-30.0, 0.0, 0.5) var meltdown_volume_db: float = -5.0
@export_group("Condiciones")
@export var freeze_hold: float = 6.0
@export var meltdown_hold: float = 8.0
@export var overheat_temp: float = 9000.0
@export var broken_shield: float = 45.0
@export var stabilize_time: float = 30.0

var state: State = State.IDLE
var _freeze_t: float = 0.0
var _heat_t: float = 0.0
var _cooldown: float = 0.0
var _beat_i: int = -1
var _siren: AudioStreamPlayer
var _dolly: Tween
var _wave_bar: int = -1
var _hunger_i: int = 0

func _ready() -> void:
	_siren = AudioStreamPlayer.new()
	_siren.bus = &"SFX"
	add_child(_siren)

func _process(delta: float) -> void:
	if panel == null or not panel.unlocked:
		return
	overlay.visible = not (views.current in views.cycle_views)
	match state:
		State.IDLE:
			_watch(delta)
		State.MELTDOWN:
			_meltdown_tick()

# --- Vigilancia ---------------------------------------------------------------------

func _watch(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if views.cinematic or views.is_busy():
		return
	var lat: int = panel.get_level(&"lateral")
	var dia: int = panel.get_level(&"diagonal")
	var fans: int = panel.get_level(&"fans")
	var cool: int = panel.get_level(&"shield")

	# Congelamiento.
	if lat == 1 and dia == 1 and fans == 5 and cool == 5:
		_freeze_t += delta
		overlay.show_notice("CRYO LOCK", Color(0.55, 0.9, 1.0))
		overlay.set_detail("CORE COOLING %d%%" % int(_freeze_t / freeze_hold * 100.0))
		overlay.set_progress(_freeze_t / freeze_hold)
		if _freeze_t >= freeze_hold:
			_freeze()
		return
	if _freeze_t > 0.0:
		_freeze_t = 0.0
		overlay.clear()

	# Sobrecalentamiento -> derretimiento.
	var hot: bool = sim.temp > overheat_temp or (sim.shield_online and sim.shield_integrity < broken_shield)
	if hot and _cooldown <= 0.0:
		_heat_t += delta
		overlay.show_alert("CORE OVERHEAT", 0.35)
		overlay.set_detail("CONTAINMENT FAILURE IN %d" % int(ceil(meltdown_hold - _heat_t)))
		overlay.set_progress(_heat_t / meltdown_hold)
		if _heat_t >= meltdown_hold:
			_start_meltdown()
	elif _heat_t > 0.0:
		_heat_t = maxf(_heat_t - delta * 2.0, 0.0)
		if _heat_t <= 0.0:
			overlay.clear()

# --- Derretimiento -----------------------------------------------------------------

func _start_meltdown() -> void:
	state = State.MELTDOWN
	_beat_i = -1
	music.play_track(music.load_stream(meltdown_track), meltdown_volume_db)
	overlay.show_alert("MELTDOWN", BEAT)
	overlay.set_progress(-1.0)
	lighting.alarm(true, BEAT)
	_start_siren()
	sim.meltdown = 0.25
	_wave_bar = -1
	_hunger_i = 0
	if hunger and hunger.outside:
		hunger.outside.emergency(true)
	# El disco crece mas alla de la recamara: corte por profundidad manual.
	driver.black_hole.draw_over_everything = true
	shield.flash(1.2)
	shield.tint_to(Color(1.0, 0.35, 0.3), Color(1.0, 0.75, 0.6), 20.0)
	views.shake(0.012, 0.5)
	_play("shield_ignite", 0.0, 0.6)

func _meltdown_tick() -> void:
	var t: float = music.track_time()
	if t < 0.0:
		return
	var m := clampf(t / NO_RETURN, 0.0, 1.0)
	sim.meltdown = 0.25 + 0.75 * m
	sim.meltdown_eta = maxf(NO_RETURN - t, 0.0)
	var eta := int(ceil(sim.meltdown_eta))
	overlay.set_detail("POINT OF NO RETURN T-%02d:%02d" % [eta / 60, eta % 60])
	for l in lasers:
		l.overload(clampf((t - 6.0) / 120.0, 0.0, 1.0))

	# Golpes al pulso: cada compas, cada vez mas fuertes.
	var beat := int(t / BEAT)
	if beat != _beat_i:
		_beat_i = beat
		if beat % 4 == 0:
			var k := 0.3 + 0.7 * m
			views.shake(0.003 + 0.006 * k, 0.2)
			shield.ripple(_random_dir())
			shield.flash(0.3 * k)
			for l in lasers:
				l.pulse(0.5 * k)
		elif m > 0.5 and beat % 2 == 0:
			shield.ripple(_random_dir())

	if hunger:
		# Ondas expansivas: cada dos compases, y cada compas al final.
		if t >= WAVES_FROM:
			var bar := int(t / BAR)
			var every := 2 if t < 140.0 else 1
			if bar != _wave_bar and bar % every == 0:
				_wave_bar = bar
				hunger.shockwave(0.35 + 0.65 * clampf((t - WAVES_FROM) / (NO_RETURN - WAVES_FROM), 0.0, 1.0))
		while _hunger_i < PRE_DEVOUR.size() and t >= PRE_DEVOUR[_hunger_i][0]:
			_hunger_event(PRE_DEVOUR[_hunger_i])
			_hunger_i += 1

	# El jugador lo enfria a tiempo.
	var fans: int = panel.get_level(&"fans")
	var cool: int = panel.get_level(&"shield")
	if fans >= 4 and cool >= 4 and t < NO_RETURN - 1.0:
		_stabilize()
		return
	if t >= NO_RETURN - CUT_LEAD:
		_climax()

func _start_siren() -> void:
	_siren.stream = await sfx.get_stream("siren")
	_siren.volume_db = -40.0
	_siren.play()
	create_tween().tween_property(_siren, "volume_db", -14.0, 2.0)

func _stop_siren(time: float) -> void:
	var t := create_tween()
	t.tween_property(_siren, "volume_db", -60.0, time)
	t.tween_callback(_siren.stop)

# --- Estabilizacion ---------------------------------------------------------------

func _stabilize() -> void:
	state = State.STABILIZING
	music.stop_track(3.0)
	_stop_siren(2.0)
	sim.meltdown_eta = -1.0
	overlay.show_notice("STABILIZING", Color(0.45, 0.95, 1.0))
	overlay.set_progress(0.0)
	lighting.alarm(false)
	shield.tint_to(Color(0.35, 0.8, 1.0), Color(0.7, 0.95, 1.0), 6.0)
	for l in lasers:
		l.overload(0.0)
	if hunger:
		hunger.restore_all()
		if hunger.outside:
			hunger.outside.emergency(false)
	_play("shield_ignite", -4.0, 1.3)
	var t := create_tween().set_parallel()
	t.tween_property(sim, "meltdown", 0.0, 8.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(sim, "stabilizing", 1.0, 4.0)
	var elapsed := 0.0
	while elapsed < stabilize_time:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		overlay.set_detail("FIELD STABLE IN %d" % int(ceil(stabilize_time - elapsed)))
		overlay.set_progress(elapsed / stabilize_time)
	create_tween().tween_property(sim, "stabilizing", 0.0, 3.0)
	driver.black_hole.draw_over_everything = false
	overlay.show_notice("CATASTROPHE AVERTED", Color(0.45, 1.0, 0.55))
	overlay.set_detail("")
	overlay.set_progress(-1.0)
	endings.unlock(&"averted")
	_heat_t = 0.0
	_cooldown = 12.0
	state = State.IDLE
	await get_tree().create_timer(4.0, false).timeout
	if state == State.IDLE and _heat_t <= 0.0 and _freeze_t <= 0.0:
		overlay.clear()

# --- Climax y explosion -------------------------------------------------------------

func _climax() -> void:
	state = State.CLIMAX
	var bh: Node3D = driver.black_hole
	views.cinematic = true
	overlay.clear()
	sim.meltdown_eta = 0.0
	await _cut(&"Window", NO_RETURN)
	# Contador en cero: los monitores pierden los datos, uno tras otro.
	if hunger:
		for i in hunger.monitors.size():
			var m: Node = hunger.monitors[i]
			if m.get("screen"):
				get_tree().create_timer(0.12 * i, false).timeout.connect(m.screen.fail)
	bars.show_bars("CONTAINMENT FAILURE")
	bars.set_caption("POINT OF NO RETURN", Color(1.0, 0.25, 0.2))
	# El agujero negro "inhala": se encoge y todo se apaga un instante.
	driver.alive = false
	var inhale := create_tween().set_parallel()
	inhale.tween_property(bh, "sphere_radius", bh.sphere_radius * 0.7, 3.0).set_trans(Tween.TRANS_SINE)
	inhale.tween_property(bh, "disc_brightness", 0.6, 3.0)
	for l in lasers:
		l.set_beam(0.2, 2.0)
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.25), 3.5)

	# Climax: el escudo estalla y el agujero negro se expande.
	await _cut(&"CineCenter", CLIMAX_T)
	bars.set_caption("SHIELD COLLAPSE", Color(1.0, 0.25, 0.2))
	shield.shatter()
	_climax_hunger()
	_play("glass_shatter", 2.0)
	_play("shield_ignite", 3.0, 0.5)
	views.shake(0.02, 0.8)
	for l in lasers:
		l.overload(1.0)
		l.set_beam(2.5, 0.3)
		l.beam_stop = 0.0
	var grow := create_tween().set_parallel()
	# El disco manda: crece mucho mas que la esfera, se engrosa, se vuelve
	# opaco y compacto (menos turbulencia = brazos solidos, no jirones) y se
	# inclina hacia la camara para que se vea de frente, girando furioso.
	var grow_t := FINAL_HIT - CLIMAX_T - 5.0
	grow.tween_property(bh, "sphere_radius", 0.22, grow_t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	grow.tween_property(bh, "disc_radius", 2.2, grow_t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	grow.tween_property(bh, "disc_inner_ratio", 1.7, 3.0)
	grow.tween_property(bh, "disc_falloff", 0.5, 3.0)
	grow.tween_property(bh, "disc_thickness_ratio", 0.075, 4.0)
	grow.tween_property(bh, "disc_brightness", 1.5, 4.0)
	grow.tween_property(bh, "disc_opacity", 1.0, 4.0)
	grow.tween_property(bh, "bend_strength", 1.6, FINAL_HIT - CLIMAX_T)
	grow.tween_property(bh, "turbulence", 0.6, 2.0)
	grow.tween_property(bh, "filament_width", 0.75, 2.0)
	grow.tween_property(bh, "filament_contrast", 2.0, 2.0)
	grow.tween_property(bh, "filament_flatten", 0.6, 2.0)
	grow.tween_property(bh, "noise_detail", 6.0, 2.0)
	grow.tween_property(bh, "ring_contrast", 0.4, 2.0)
	grow.tween_property(bh, "doppler_strength", 0.8, 2.0)
	grow.tween_property(bh, "swirl_speed", 7.0, 8.0)
	grow.tween_property(bh, "disc_tilt_degrees", bh.disc_tilt_degrees + DISC_TILT * 0.3, 6.0).set_trans(Tween.TRANS_SINE)
	bh.disc_color_cold = Color(1.0, 0.1, 0.35)
	bh.disc_color_hot = Color(1.0, 0.8, 0.55)
	_shake_on_beats(CLIMAX_T, FINAL_HIT)

	var shots := [&"CineWide", &"Room", &"CineLow", &"Window", &"Room", &"Room"]
	var captions := ["GRAVITATIONAL RUNAWAY", "", "EVENT HORIZON EXPANDING", "", "", "IT'S HERE"]
	for i in shots.size():
		await _cut(shots[i], CLIMAX_T + BAR * (i + 1))
		if captions[i] != "":
			bars.set_caption(captions[i], Color(1.0, 0.25, 0.2))
	# El horizonte llega a la sala.
	var swallow := create_tween().set_parallel()
	grow.kill()
	var left := maxf(FINAL_HIT - 0.35 - _now(), 0.5)
	# Primero el disco arrasa la sala (llamas por todas partes) y, al final,
	# la esfera se la come.
	swallow.tween_property(bh, "sphere_radius", 3.2, left).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	swallow.tween_property(bh, "disc_radius", 30.0, left).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	swallow.tween_property(bh, "disc_inner_ratio", 1.35, left)
	swallow.tween_property(bh, "disc_falloff", 0.3, left)
	swallow.tween_property(bh, "disc_brightness", 2.0, left)
	swallow.tween_property(bh, "swirl_speed", 12.0, left)

	# Ultimo golpe: implosion y explosion.
	await _at(FINAL_HIT - 0.35)
	swallow.kill()
	var implode := create_tween().set_parallel()
	implode.tween_property(bh, "sphere_radius", 0.0005, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	implode.tween_property(bh, "disc_radius", 0.02, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_play("implosion")
	await _at(FINAL_HIT)
	_explosion()
	_stop_siren(0.5)
	lighting.alarm(false)
	await get_tree().create_timer(2.5, false).timeout
	await bars.hide_bars()
	endings.unlock(&"meltdown")
	await get_tree().create_timer(1.0, false).timeout
	state = State.ENDING
	restore.play("EVENT HORIZON BREACH")

## Lo que el agujero negro destroza mientras crece.
func _climax_hunger() -> void:
	if hunger == null:
		return
	for ev in CLIMAX_HUNGER:
		await _at(ev[0])
		if state != State.CLIMAX:
			return
		_hunger_event(ev)

func _hunger_event(ev: Array) -> void:
	match ev[1]:
		"wave":
			hunger.shockwave(ev[2])
		"laser":
			hunger.devour_laser(hunger.next_laser(ev[2]))
		"blade":
			hunger.devour_blade(hunger.next_blade())
		"prop":
			if ev[2] == "crystal":
				hunger.devour_prop(crystal, 2.4, "glass_shatter")
			else:
				hunger.devour_prop(left_monitor, 2.6, "spark")
		"lights":
			var i := 0
			for l in hunger.next_lights(ev[2]):
				get_tree().create_timer(0.18 * i, false).timeout.connect(hunger.devour_light.bind(l, 1.3))
				i += 1
		"all":
			# Lo que quede, todo de golpe.
			var i := 0
			for l in lasers:
				if not hunger.is_devoured(l):
					get_tree().create_timer(0.15 * i, false).timeout.connect(hunger.devour_laser.bind(l, 1.6))
					i += 1
			var blade: Node3D = hunger.next_blade()
			while blade:
				hunger.devour_blade(blade, 1.5)
				blade = hunger.next_blade()

func _explosion() -> void:
	var calm: bool = settings != null and bool(settings.get_value("reduce_flashing"))
	_play("explosion", 4.0)
	views.shake(0.03, 1.5)
	driver.black_hole.visible = false
	flash.visible = true
	flash.color = Color(1.0, 0.95, 0.85, 1.0 if not calm else 0.6)
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(flash, "color", Color(1.0, 0.45, 0.2, 1.0), 0.8)
	t.tween_property(flash, "color", Color(0.0, 0.0, 0.0, 1.0), 1.4)

func _shake_on_beats(from: float, to: float) -> void:
	var b := int(ceil(from / BEAT))
	while b * BEAT < to:
		await _at(b * BEAT)
		var k := clampf((b * BEAT - from) / (to - from), 0.0, 1.0)
		views.shake(0.006 + 0.02 * k, 0.25)
		for l in lasers:
			l.pulse(0.6 + k)
		b += 1

# --- Congelamiento -----------------------------------------------------------------

func _freeze() -> void:
	state = State.FREEZE
	var bh: Node3D = driver.black_hole
	overlay.clear()
	views.cinematic = true
	music.stop_background(2.5)
	_play("cryo_freeze")
	await views.go_to(&"CineCenter")
	bars.show_bars("CRYOGENIC LOCK")
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.2), 16.0)
	create_tween().tween_property(sim, "frozen", 1.0, 7.0).set_trans(Tween.TRANS_SINE)
	shield.tint_to(Color(0.8, 0.95, 1.0), Color(1.0, 1.0, 1.0), 5.0)
	shield.density_to(0.9, 6.0)
	for i in lasers.size():
		lasers[i].set_beam(0.0, 1.5 + i * 0.4)
		lasers[i].set_light_scale(0.05, 4.0)
	await get_tree().create_timer(3.5, false).timeout
	bars.set_caption("CORE TEMPERATURE 0.3 K", Color(0.55, 0.9, 1.0))
	await get_tree().create_timer(4.5, false).timeout
	# Colapso suave.
	driver.alive = false
	bars.set_caption("SINGULARITY COLLAPSING", Color(0.55, 0.9, 1.0))
	_play("implosion", -4.0, 0.7)
	var collapse := create_tween().set_parallel()
	collapse.tween_property(bh, "disc_radius", 0.02, 4.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(bh, "sphere_radius", 0.0005, 4.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.tween_property(bh, "disc_brightness", 0.3, 4.0)
	collapse.tween_property(shield, "compression", 1.0, 4.5)
	await collapse.finished
	bh.visible = false
	shield.flash(1.2)
	var fade := create_tween()
	fade.tween_property(shield, "brightness", 0.0, 2.0)
	bars.set_caption("SINGULARITY NEUTRALIZED", Color(0.45, 1.0, 0.55))
	await get_tree().create_timer(2.5, false).timeout
	endings.unlock(&"freeze")
	await get_tree().create_timer(2.0, false).timeout
	await bars.hide_bars()
	state = State.ENDING
	restore.play("CRYOGENIC COLLAPSE")

# --- Ayudas --------------------------------------------------------------------------

func _now() -> float:
	return music.track_time()

func _at(t: float) -> void:
	while music.is_track_playing() and music.track_time() < t:
		await get_tree().process_frame

func _cut(view: StringName, t: float) -> void:
	await _at(t - CUT_LEAD)
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	views.go_to(view, 2.0)
	await _at(t)

func _random_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
