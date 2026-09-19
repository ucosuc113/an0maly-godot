extends Node

# Crisis y finales, despues de la fase 3 (palancas desbloqueadas).
#
#   CONGELAMIENTO (freeze): lo decide la TEMPERATURA del nucleo, no en que
#     numero quedo cada palanca. El refrigerante del escudo es criogenico
#     (reactor_sim.gd): con caudal alto y los lasers bajos el nucleo cae por
#     debajo del ambiente. Cuando pasa `cryo_temp` y se sostiene `freeze_hold`
#     segundos, la singularidad se congela y colapsa sin danos -> reinicio.
#     Hay margen: no es una unica combinacion de palancas, es toda la region
#     de configuraciones que dejan el nucleo bastante frio, y se ve venir en
#     el monitor.
#
#   DERRETIMIENTO (meltdown): el nucleo se pasa de vueltas y la contencion
#     aguanta unos segundos (meltdown_hold) antes de ceder. No es un salto: la
#     sala avisa en tres escalones (THERMAL WARNING sin cuenta -> CORE
#     OVERHEAT con barra -> CONTAINMENT FAILURE con cuenta y bips), y si el
#     jugador enfria, la cuenta retrocede.
#
#     Una vez arrancado suena "Kinetic Energy" COMPLETA. Los 175 s hasta el
#     punto de no retorno van en tres actos, y el aborto pide mas en cada uno:
#       ACTO I   0-58 s   MELTDOWN. Los emisores se sobrecargan y el agujero
#                         empieza a tirar de sus piezas (desde los 34 s).
#                         Para frenarlo alcanza con refrigerar (4+).
#       ACTO II  58-128 s CONTAINMENT BREACH. Ondas expansivas, piezas que
#                         salen mas seguido, aspas que se sueltan. Ademas de
#                         refrigerar hacen falta `abort_emitters` emisores
#                         todavia disparando.
#       ACTO III 128-175  HORIZON EXPANDING. Sin rescate posible a partir de
#                         LOCKOUT (155 s); antes, ademas, hay que bajar la
#                         energia de los lasers.
#     Si lo frena a tiempo: la musica se va, en 30 s todo queda estable ->
#     final "catastrofe evitada" (sin reinicio; puede volver a pasar).
#     Si no: en 175 s la camara se toma el control, el escudo estalla, el
#     agujero negro crece hasta tragarse el mapa, implosiona y explota en el
#     ultimo golpe (199.5 s) -> reinicio.
#
#     El monitor derecho pasa a ser el tablero de reles del
#     refrigerante (coolant_routing.gd): los canales se queman y hay que
#     rehacer el camino, o el escudo se queda sin caudal.
#
#     El agujero negro no se traga los lasers enteros: les arranca las piezas
#     de a una (singularity_hunger.gd). Mientras tira de una, el jugador tiene
#     una ventana para reengancharla clicando el cerco que aparece sobre ella
#     (clamp_prompts.gd). El primer desgarro apaga el haz de ese laser, asi
#     que cada pieza perdida acerca el punto de no retorno.
#
#   PURGA CRIOGENICA (emergency_room.gd): el boton azul de la sala de
#     emergencia vacia TODAS las reservas de refrigerante sobre el agujero
#     negro, y deja los ventiladores muertos para siempre. No avisa nada: pasa en
#     silencio, a proposito.
#       - con el nucleo por debajo de `purge_safe_temp` alcanza y el nucleo
#         cae al fondo -> final de congelamiento (sin cartelitos: el aviso se
#         calla mientras dura la purga).
#       - por encima NO alcanza: le pega un frenazo termico y lo parte ->
#         derretimiento VIOLENTO -> final FLASH FREEZE FAILURE.
#     En derretimiento la temperatura sigue a la pista (reactor_sim.gd), asi
#     que el umbral cae siempre en el mismo momento (~95 s, acto II). Una
#     purga buena en pleno derretimiento lo ahoga: se calla todo de golpe y
#     el congelamiento llega solo (_quench_meltdown).
#
#   APAGADO DE EMERGENCIA (shutdown): los dos switches de la sala de
#     emergencia, en orden. Se corta la instalacion entera —luces, exterior,
#     emisores, musica— y queda el agujero negro como unica luz. Entonces los
#     tres emisores LATERALES vuelven a encenderse en naranja y lo desarman:
#     el disco se deshilacha en jirones, la lente deja de curvar la luz y el
#     horizonte revienta en una nube de fragmentos que se queda flotando.
#     Nunca se lo ve encogerse ni apagarse: desaparece tapado por sus restos.
#
#   CORE DETONATION: el mismo apagado de emergencia, pero tirado TARDE (pasado
#     `shutdown_max_temp`, ~142 s del derretimiento). Empieza igual que el
#     bueno, pero el nucleo se come el disparo, los laterales revientan por
#     realimentacion y el intento de destruirlo lo ENCIENDE: estalla hacia
#     afuera en vez de tragarse la sala (_detonation). La pista salta a
#     DET_START, asi que todo cae al compas sin importar cuando se tiro.
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
## CORE DETONATION: la pista salta aca. Los 8 s hasta NO_RETURN son el intento
## de apagado que sale mal.
const DET_START := NO_RETURN - 8.0
## Limites de los actos (segundos de la pista).
const ACT_II := 58.0
const ACT_III := 128.0
## Pasado esto ya no hay vuelta atras, se haga lo que se haga.
const LOCKOUT := 155.0
## Desde aqui el agujero empieza a arrancar piezas.
const TEAR_FROM := 34.0
## Desde aqui empiezan las ondas expansivas.
const WAVES_FROM := 52.0
## Desde aqui empiezan a quemarse los reles del refrigerante.
const ROUTE_FROM := 20.0
## Cartel de cada acto (el indice es el acto).
const ACT_NAME := ["", "MELTDOWN", "CONTAINMENT BREACH", "HORIZON EXPANDING"]
## Cosas sueltas al final, ademas de las piezas que van saliendo solas.
## [tiempo, tipo, dato]: lights -> cuantas; wave -> fuerza.
const PRE_DEVOUR := [
	[160.5, "lights", 2],
	[167.5, "lights", 3],
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
## coolant_routing.gd: el tablero de reles del monitor derecho.
@export var routing: Node
## Piezas que se traga al final.
@export var crystal: Node3D
@export var left_monitor: Node3D
@export_file("*.mp3", "*.ogg", "*.wav") var meltdown_track: String = ""
## La pista manda: la sirena va por debajo, no al reves.
@export_range(-30.0, 0.0, 0.5) var meltdown_volume_db: float = -1.0
@export_group("Condiciones")
@export var freeze_hold: float = 6.0
## Primer aviso (ambar, sin cuenta atras).
@export var warn_temp: float = 5500.0
@export var overheat_temp: float = 9000.0
## Por debajo de esto el nucleo empieza a congelarse.
@export var cryo_temp: float = 120.0
## Primer aviso frio (azul, sin cuenta).
@export var chill_temp: float = 900.0
## Cuanto aguanta la contencion con el nucleo pasado de vueltas.
@export var meltdown_hold: float = 26.0
## Ultimos segundos de esa espera: cuenta atras y bips que se aceleran.
@export var final_count: float = 10.0
@export var broken_shield: float = 45.0
@export var stabilize_time: float = 30.0
@export_group("Aborto del derretimiento")
## El aborto tampoco mira las palancas: mira lo que el reactor esta haciendo
## de verdad (lo mismo que muestran los monitores), con su inercia.
@export var abort_coolant: float = 70.0
@export var abort_fan_rpm: float = 1900.0
## Potencia total de lasers (lateral + diagonal) a la que hay que bajar en el
## ultimo acto.
@export var abort_laser_power: float = 700.0
## Emisores que tienen que seguir disparando para poder frenar el
## derretimiento a partir del acto II.
@export var abort_emitters: int = 3
@export_group("Purga criogenica")
## Desde aqui se puede apretar el boton azul.
@export var purge_unlock_temp: float = 4000.0
## Hasta aqui el refrigerante alcanza. Por encima, el golpe no basta.
## En derretimiento la temperatura sigue a la pista (reactor_sim.gd, 16.5K al
## arrancar + ~129 K/s): 28K cae a ~95 s, a mitad del acto II.
@export var purge_safe_temp: float = 28000.0
## Cuanto tarda el liquido en llegar al fondo.
@export var purge_time: float = 30.0
@export_group("Apagado de emergencia")
## Por encima de esta temperatura el nucleo junto demasiada energia: el corte
## de los laterales ya no lo desarma, se la entrega y lo enciende. Ahi el
## apagado de emergencia termina en CORE DETONATION en vez de EMERGENCY
## SHUTDOWN, que es lo que le da sentido literal al "PULL THE PLUG IN TIME".
##
## Va por temperatura, no por reloj: asi el jugador lo ve venir en la barra
## del monitor de arriba de la sala de emergencia, igual que el resto de los
## finales.
##
## 34K cae a ~142 s del derretimiento (acto III): casi todo el derretimiento
## se puede apagar, y queda un tramo corto y visible "mas alla" en la barra
## (la escala del monitor llega a 40K) que es donde vive CORE DETONATION.
@export var shutdown_max_temp: float = 34000.0
## Cuantos de los primeros `lasers` son laterales (los que cortan).
@export var lateral_count: int = 3
## Naranja de corte: los laterales dejan de contener y pasan a desintegrar.
@export var shutdown_deep: Color = Color(0.35, 0.08, 0.0)
@export var shutdown_mid: Color = Color(1.0, 0.42, 0.05)
@export var shutdown_hot: Color = Color(1.0, 0.92, 0.65)
@export var shutdown_light: Color = Color(1.0, 0.55, 0.15)
@export_group("Alarma")
## Volumen de la sirena. Suena a rafagas, no sin parar: una alarma continua
## en estos 650 Hz se come la melodia y el oido deja de registrarla.
@export_range(-45.0, 0.0, 0.5) var siren_db: float = -23.0

var state: State = State.IDLE
var _freeze_t: float = 0.0
var _heat_t: float = 0.0
var _cooldown: float = 0.0
var _beat_i: int = -1
var _siren: AudioStreamPlayer
var _dolly: Tween
var _wave_bar: int = -1
var _hunger_i: int = 0
## Acto en curso (1..3).
var _act_i: int = 0
## Cuenta atras hasta el proximo desgarro y cuantos van.
var _tear_t: float = 0.0
var _tear_n: int = 0
## Cuenta atras hasta el proximo rele quemado.
var _burn_t: float = 0.0
## Final que va a dar este derretimiento (cambia si se arma la ignicion).
var _ending: StringName = &"meltdown"
## Derretimiento violento: el que viene despues de una purga que no alcanzo.
var _violent: bool = false
## Ritmo de los bips de la cuenta atras y de los crujidos del aviso ambar.
var _tick_t: float = 0.0
var _creak_t: float = 0.0
## Hay algo puesto en el overlay por la vigilancia.
var _showing: bool = false

## No hay crisis en curso (lo consulta dev_shortcuts.gd).
func is_idle() -> bool:
	return state == State.IDLE

## Hay un desastre encima que justifica abrir la sala de emergencia.
func emergency_available() -> bool:
	return state == State.MELTDOWN or _heat_t > 0.0 or sim.temp > warn_temp

## El boton azul se puede apretar.
func purge_ready() -> bool:
	return not sim.purged and sim.temp > purge_unlock_temp

## Vacia las reservas sobre el nucleo. En silencio: no pone un solo cartel.
func purge() -> void:
	if sim.purged:
		return
	# La suerte se decide AHORA, con la temperatura del momento.
	var enough: bool = sim.temp <= purge_safe_temp
	sim.purge(purge_time, enough)
	views.shake(0.014, 1.2)
	if shield:
		shield.tint_to(Color(0.7, 0.92, 1.0), Color(1.0, 1.0, 1.0), purge_time * 0.5)
	if enough:
		# Alcanza: el nucleo se va al fondo y el congelamiento salta solo en
		# _watch(), que mientras tanto se queda callado.
		if state == State.MELTDOWN:
			_quench_meltdown()
		return
	# No alcanza: el frenazo termico parte la contencion.
	await get_tree().create_timer(purge_time * 0.55, false).timeout
	if state == State.MELTDOWN:
		_turn_violent()
	elif state == State.IDLE:
		_start_meltdown(true)

## La purga alcanzo con el derretimiento en curso: las reservas lo ahogan.
## No hay carteles (la purga pasa en silencio); lo que se nota es que TODO se
## calla de golpe. Vuelve a la vigilancia, y ahi el congelamiento salta solo
## cuando el nucleo llega al fondo.
func _quench_meltdown() -> void:
	state = State.IDLE
	_act_i = 0
	_heat_t = 0.0
	_cooldown = 0.0
	_freeze_t = 0.0
	music.stop_track(1.2)
	_stop_siren(0.8)
	lighting.alarm(false)
	sim.meltdown_eta = -1.0
	overlay.set_compact(false)
	overlay.clear()
	_showing = false
	if routing:
		routing.stop()
	if hunger:
		if hunger.prompts:
			hunger.prompts.clear()
		if hunger.outside:
			hunger.outside.emergency(false)
	for l in lasers:
		l.overload(0.0)
	create_tween().tween_property(sim, "meltdown", 0.0, 6.0).set_trans(Tween.TRANS_SINE)

## Lo que ya estaba derritiendose se pone peor.
func _turn_violent() -> void:
	if _violent:
		return
	_violent = true
	_ending = &"failed_freeze"
	overlay.flash_banner("QUENCH FAILURE", 3.0)
	views.shake(0.026, 1.4)
	shield.flash(1.5)
	if hunger:
		hunger.shockwave(2.2)
	for l in lasers:
		l.pulse(2.0)
	_play("glass_shatter", 1.0, 0.7)

func _ready() -> void:
	_siren = AudioStreamPlayer.new()
	_siren.bus = &"SFX"
	add_child(_siren)

func _process(delta: float) -> void:
	if panel == null or not panel.unlocked:
		return
	overlay.visible = _overlay_wanted()
	match state:
		State.IDLE:
			_watch(delta)
		State.MELTDOWN:
			_meltdown_tick(delta)

## En las vistas de monitor el aviso estorba... salvo que le esten arrancando
## una pieza al reactor y el jugador este mirando para otro lado.
func _overlay_wanted() -> bool:
	if not (views.current in views.cycle_views):
		return true
	if state != State.MELTDOWN or hunger == null or hunger.prompts == null:
		return false
	return hunger.prompts.offscreen_count() > 0

# --- Vigilancia ---------------------------------------------------------------------

func _watch(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if views.cinematic or views.is_busy():
		return
	# Solo para redactar la pista: lo que dispara los finales es sim.temp.
	var fans: int = panel.get_level(&"fans")
	var cool: int = panel.get_level(&"shield")

	# Congelamiento: manda la temperatura del nucleo, no las palancas. El
	# _cooldown lo cubre igual que al calor: al estabilizar un derretimiento
	# se queda con la energia abajo y el frio arriba, que es justo la receta
	# del congelamiento, y encadenar los dos finales de corrido es raro.
	if sim.shield_online and sim.temp < cryo_temp and _cooldown <= 0.0:
		_freeze_t += delta
		# Si esto viene de la purga criogenica, no se avisa nada: el diseno
		# pide que pase en silencio, sin un solo cartel.
		if not sim.purged:
			_showing = true
			overlay.show_notice("CRYO LOCK", Color(0.55, 0.9, 1.0))
			overlay.set_detail("CORE %s K" % _temp_text(sim.temp))
			overlay.set_hint("HOLD BELOW %d K" % int(cryo_temp))
			overlay.set_progress(_freeze_t / freeze_hold)
		if _freeze_t >= freeze_hold:
			_freeze()
		return
	# Se calento antes de tiempo: la cuenta retrocede en vez de perderse.
	if _freeze_t > 0.0:
		_freeze_t = maxf(_freeze_t - delta * 2.0, 0.0)
		_showing = true
		overlay.show_notice("CRYO LOCK LOST", Color(0.55, 0.9, 1.0))
		overlay.set_detail("CORE %s K" % _temp_text(sim.temp))
		overlay.set_hint("BELOW %d K TO RESUME" % int(cryo_temp))
		overlay.set_progress(_freeze_t / freeze_hold)
		if _freeze_t <= 0.0:
			_quiet()
		return

	# Sobrecalentamiento -> derretimiento, en escalones.
	var breach: bool = sim.shield_online and sim.shield_integrity < broken_shield
	var failing: bool = sim.temp > overheat_temp or breach
	# Con la purga buena en curso, el nucleo pica un momento antes de
	# desplomarse (se quedo sin refrigeracion y las reservas todavia estan
	# cayendo). Ese pico no cuenta: la suerte ya se decidio al apretar.
	if sim.purged and sim.quench_holds:
		failing = false
	if failing and _cooldown <= 0.0:
		# El escudo roto corre al doble: es una falla mas grave que el calor.
		_heat_t += delta * (2.0 if breach else 1.0)
		var left := maxf(meltdown_hold - _heat_t, 0.0)
		_showing = true
		if left <= final_count:
			overlay.show_alert("CONTAINMENT FAILURE", 0.33)
			overlay.set_detail("MELTDOWN IN %d" % int(ceil(left)))
			_warning_tick(delta, left)
		else:
			overlay.show_alert("SHIELD BREACH" if breach else "CORE OVERHEAT", 0.9)
			overlay.set_detail("CONTAINMENT %d%%" % int(round(left / meltdown_hold * 100.0)))
		overlay.set_hint(_cooling_hint(breach, fans, cool))
		overlay.set_progress(_heat_t / meltdown_hold)
		_strain(delta)
		if _heat_t >= meltdown_hold:
			_start_meltdown()
		return

	# Se enfrio a tiempo: la contencion se recupera (mas rapido de lo que cedio).
	if _heat_t > 0.0:
		_heat_t = maxf(_heat_t - delta * 2.5, 0.0)
		_showing = true
		overlay.show_notice("CONTAINMENT RECOVERING", Color(0.45, 0.95, 1.0))
		overlay.set_detail("%d%%" % int(round((1.0 - _heat_t / meltdown_hold) * 100.0)))
		overlay.set_hint("")
		overlay.set_progress(1.0 - _heat_t / meltdown_hold)
		if _heat_t <= 0.0:
			_quiet()
		return

	# Primer aviso frio: el nucleo va camino al congelamiento.
	if sim.shield_online and sim.temp < chill_temp and not sim.purged:
		_showing = true
		overlay.show_notice("CORE SUPERCOOLED", Color(0.55, 0.9, 1.0))
		overlay.set_detail("CORE %s K" % _temp_text(sim.temp))
		overlay.set_hint("CRYO LOCK BELOW %d K" % int(cryo_temp))
		# La barra se llena a medida que el nucleo se acerca al umbral.
		overlay.set_progress(clampf((chill_temp - sim.temp) / maxf(chill_temp - cryo_temp, 1.0), 0.0, 1.0))
		return

	# Primer aviso: todavia no pasa nada, pero la sala ya se queja.
	if sim.temp > warn_temp:
		_showing = true
		var heat := clampf((sim.temp - warn_temp) / maxf(overheat_temp - warn_temp, 1.0), 0.0, 1.0)
		overlay.show_notice("THERMAL WARNING", Color(1.0, 0.72, 0.2))
		overlay.set_detail("CORE %d K" % int(sim.temp))
		overlay.set_hint(_cooling_hint(false, fans, cool))
		overlay.set_progress(heat)
		for l in lasers:
			l.overload(heat * 0.35)
		_strain(delta)
		return

	if _showing:
		_quiet()

## Todo en orden: se limpia el aviso y los lasers dejan de chispear.
func _quiet() -> void:
	_showing = false
	overlay.clear()
	for l in lasers:
		l.overload(0.0)

## La temperatura como la canta el panel: con un decimal cuando ya esta frio,
## entera cuando son miles de grados.
func _temp_text(t: float) -> String:
	return "%.1f" % t if t < 100.0 else "%d" % int(round(t))

## Que le falta al jugador para bajar la temperatura. Se dice, no se adivina.
func _cooling_hint(breach: bool, fans: int, cool: int) -> String:
	if breach:
		return "RAISE SHIELD COOLANT"
	if fans < 5 or cool < 5:
		return "MORE FANS / SHIELD COOLANT"
	return "CUT LASER POWER"

## Bips de la cuenta atras: se aceleran y suben de tono. No es la sirena (esa
## viene despues y va mas baja).
func _warning_tick(delta: float, left: float) -> void:
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = 0.9 if left > 5.0 else 0.4
	_play("crt_click", -9.0, 1.0 + (final_count - left) * 0.04)

## La sala se queja mientras sube el calor: crujidos sueltos y un parpadeo.
func _strain(delta: float) -> void:
	_creak_t -= delta
	if _creak_t > 0.0:
		return
	_creak_t = randf_range(2.5, 6.0)
	_play("metal_groan", -16.0, randf_range(0.7, 0.95))
	views.shake(0.003, 0.25)
	if lighting:
		lighting.flicker(0.35)

# --- Derretimiento -----------------------------------------------------------------

## `violent` = el que viene de una purga que no alcanzo: arranca pasado el
## primer acto, no se puede frenar y da su propio final.
func _start_meltdown(violent: bool = false) -> void:
	state = State.MELTDOWN
	_beat_i = -1
	_showing = false
	_violent = violent
	music.play_track(music.load_stream(meltdown_track), meltdown_volume_db)
	overlay.show_alert("MELTDOWN", BEAT)
	overlay.set_progress(-1.0)
	lighting.alarm(true, BEAT)
	_start_siren()
	sim.meltdown = 0.25
	_wave_bar = -1
	_hunger_i = 0
	_act_i = 1
	_ending = &"failed_freeze" if violent else &"meltdown"
	# La cuenta no arranca hasta TEAR_FROM: el primer desgarro cae justo ahi.
	_tear_t = 0.0
	_tear_n = 0
	_burn_t = 0.0
	overlay.set_compact(true)
	if routing:
		routing.start()
	if hunger and hunger.outside:
		hunger.outside.emergency(true)
	# El disco crece mas alla de la recamara: corte por profundidad manual.
	driver.black_hole.draw_over_everything = true
	shield.flash(1.2)
	shield.tint_to(Color(1.0, 0.35, 0.3), Color(1.0, 0.75, 0.6), 20.0)
	views.shake(0.012, 0.5)
	_play("shield_ignite", 0.0, 0.6)
	if violent:
		# Se saltea el acto I: esto ya viene roto de fabrica.
		music.seek_track(ACT_II)
		overlay.flash_banner("QUENCH FAILURE", 3.0)

func _meltdown_tick(delta: float) -> void:
	var t: float = music.track_time()
	if t < 0.0:
		return
	var m := clampf(t / NO_RETURN, 0.0, 1.0)
	sim.meltdown = 0.25 + 0.75 * m
	sim.meltdown_eta = maxf(NO_RETURN - t, 0.0)
	var eta := int(ceil(sim.meltdown_eta))
	var act := _act(t)
	if act != _act_i:
		_act_i = act
		_enter_act(act)
	var ramp := clampf((t - 6.0) / 120.0, 0.0, 1.0)
	for l in lasers:
		# Al que le faltan piezas le va peor que al resto.
		l.overload(clampf(ramp + 0.15 * l.torn, 0.0, 1.0))
	_siren.volume_db = move_toward(_siren.volume_db, _siren_level(t), delta * 45.0)

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
		# Ondas expansivas, cada vez mas seguido.
		if t >= WAVES_FROM:
			var bar := int(t / BAR)
			var every := 3 if t < ACT_III else (2 if t < 150.0 else 1)
			if bar != _wave_bar and bar % every == 0:
				_wave_bar = bar
				var reach := clampf((t - WAVES_FROM) / (NO_RETURN - WAVES_FROM), 0.0, 1.0)
				hunger.shockwave(0.35 + 0.65 * reach)
		# Piezas que se arranca (con su ventana de rescate). Durante un corte
		# de camara no: el jugador no puede salvar lo que no esta viendo.
		if t >= TEAR_FROM and t < NO_RETURN - 2.0 and not views.cinematic:
			_tear_t -= delta
			if _tear_t <= 0.0:
				_tear_t = _tear_every(t)
				_tear_next(t, act)
		while _hunger_i < PRE_DEVOUR.size() and t >= PRE_DEVOUR[_hunger_i][0]:
			_hunger_event(PRE_DEVOUR[_hunger_i])
			_hunger_i += 1

	# Reles del refrigerante que se van quemando.
	if routing and routing.active and t >= ROUTE_FROM and t < NO_RETURN - 2.0:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_burn_t = _burn_every(t)
			# En el ultimo acto ya se queman aunque dejen el circuito sin salida.
			routing.burn_one(t >= ACT_III)

	# El jugador lo frena: cada acto pide mas que el anterior.
	var missing := _abort_gate(t)
	_meltdown_overlay(t, act, missing)
	if missing == "" and t < NO_RETURN - 1.0:
		_stabilize()
		return
	if t >= NO_RETURN - CUT_LEAD:
		_climax()

func _act(t: float) -> int:
	if t < ACT_II:
		return 1
	if t < ACT_III:
		return 2
	return 3

## Cada acto entra de un golpe, para que se note el escalon.
func _enter_act(act: int) -> void:
	if act <= 1:
		return
	views.shake(0.018, 0.7)
	shield.flash(0.9)
	shield.ripple(_random_dir())
	if lighting:
		lighting.flicker(1.0)
	if hunger:
		hunger.shockwave(1.2 if act == 2 else 1.6)
	_play("metal_groan", -2.0, 0.7)

## Cada cuanto se arranca una pieza.
func _tear_every(t: float) -> float:
	var every := 15.0 if t < ACT_II else (10.0 if t < ACT_III else 5.5)
	# El violento arranca cosas al doble de velocidad.
	return every * 0.5 if _violent else every

## Cuanto tiempo tiene el jugador para reengancharla.
func _tear_window(t: float) -> float:
	return lerpf(3.4, 1.5, clampf((t - TEAR_FROM) / (LOCKOUT - TEAR_FROM), 0.0, 1.0))

## Reparte el dano mientras hay partida (empieza por los mas enteros) y remata
## a los mas rotos en el ultimo acto. Un aspa cada tres tirones.
func _tear_next(t: float, act: int) -> void:
	_tear_n += 1
	var window := _tear_window(t)
	if act >= 2 and _tear_n % 3 == 0:
		var blade: Node3D = hunger.next_blade()
		if blade:
			hunger.tear_blade(blade, window)
			return
	var l: Node = hunger.next_torn_laser(act < 3)
	if l:
		hunger.tear_part(l, window)

## Cada cuanto se quema un rele del refrigerante.
func _burn_every(t: float) -> float:
	var every := 13.0 if t < ACT_II else (8.0 if t < ACT_III else 5.0)
	return every * 0.5 if _violent else every

## Lo que muestra el aviso durante el derretimiento. En la vista de la consola
## manda la consola: ahi el jugador necesita los numeros, no el reloj.
func _meltdown_overlay(t: float, act: int, missing: String) -> void:
	var eta := int(ceil(sim.meltdown_eta))
	var clock := "T-%02d:%02d" % [eta / 60, eta % 60]
	overlay.set_clock(clock)
	overlay.set_progress(-1.0)
	# Los ultimos 20 s si se ganaron el cartelon.
	overlay.set_compact(t < NO_RETURN - 20.0)
	overlay.show_alert(String(ACT_NAME[act]), BEAT)
	overlay.set_detail("POINT OF NO RETURN " + clock)
	overlay.set_hint(_meltdown_hint(missing))

## Que falta para poder frenar el derretimiento. "" = ya se puede.
func _abort_gate(t: float) -> String:
	# Sin refrigerante ni ventiladores no hay nada que hacer.
	if _violent or sim.purged:
		return "COOLANT RESERVES EMPTY"
	if t >= LOCKOUT:
		return "CONTAINMENT LOST"
	if sim.coolant < abort_coolant:
		return "COOLANT %d/%d" % [int(sim.coolant), int(abort_coolant)]
	if sim.fan_rpm < abort_fan_rpm:
		return "FANS %d/%d RPM" % [int(sim.fan_rpm), int(abort_fan_rpm)]
	if t >= ACT_II and hunger:
		var live: int = hunger.operational_lasers()
		if live < abort_emitters:
			return "NEED %d FIRING EMITTERS (%d)" % [abort_emitters, live]
	if t >= ACT_III and sim.lat_power + sim.dia_power > abort_laser_power:
		return "LASER POWER %d/%d" % [int(sim.lat_power + sim.dia_power), int(abort_laser_power)]
	return ""

## Si hay un anclaje pidiendo ayuda fuera de cuadro, eso manda: el jugador no
## puede adivinar que le estan arrancando algo mientras mira un monitor.
func _meltdown_hint(missing: String) -> String:
	if not views.cinematic and hunger and hunger.prompts \
			and hunger.prompts.offscreen_count() > 0:
		return "CLAMP FAILING - LOOK OUTSIDE"
	if routing and routing.active and not routing.flow:
		return "COOLANT FLOW CUT - RIGHT MONITOR"
	return missing

## La sirena entra fuerte, despues suena a rafagas de un compas (cada vez mas
## seguido) y se queda puesta en el ultimo tramo.
func _siren_level(t: float) -> float:
	if t < 10.0:
		return siren_db
	if t >= NO_RETURN - 22.0:
		return siren_db + 2.0
	var period := 4.0 if t < ACT_II else (3.0 if t < ACT_III else 2.0)
	return siren_db if fmod(t / BAR, period) < 1.0 else -60.0

func _start_siren() -> void:
	_siren.stream = await sfx.get_stream("siren")
	_siren.volume_db = -45.0
	_siren.play()
	create_tween().tween_property(_siren, "volume_db", siren_db, 1.6)

func _stop_siren(time: float) -> void:
	var t := create_tween()
	t.tween_property(_siren, "volume_db", -60.0, time)
	t.tween_callback(_siren.stop)

# --- Estabilizacion ---------------------------------------------------------------

func _stabilize() -> void:
	state = State.STABILIZING
	_act_i = 0
	overlay.set_compact(false)
	if routing:
		routing.stop()
	music.stop_track(3.0)
	_stop_siren(2.0)
	sim.meltdown_eta = -1.0
	overlay.show_notice("STABILIZING", Color(0.45, 0.95, 1.0))
	overlay.set_hint("")
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
	overlay.set_compact(false)
	overlay.clear()
	# Se acabaron los rescates: de aca en adelante manda la camara.
	if hunger and hunger.prompts:
		hunger.prompts.clear()
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
	endings.unlock(_ending)
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
				if hunger.alive(l):
					get_tree().create_timer(0.15 * i, false).timeout.connect(hunger.devour_laser.bind(l, 1.6))
					i += 1
			var blade: Node3D = hunger.next_blade()
			while blade:
				hunger.devour_blade(blade, 1.5)
				blade = hunger.next_blade()

## `violent` = la de CORE DETONATION: mas larga, mas fuerte, y pasa por rojo
## antes de irse a negro.
func _explosion(violent: bool = false) -> void:
	var calm: bool = settings != null and bool(settings.get_value("reduce_flashing"))
	_play("explosion", 4.0)
	if violent:
		_play("explosion", 2.0, 0.6)
		_play("shield_ignite", 4.0, 0.35)
	views.shake(0.05 if violent else 0.03, 2.6 if violent else 1.5)
	driver.black_hole.visible = false
	flash.visible = true
	flash.color = Color(1.0, 0.95, 0.85, 1.0 if not calm else 0.6)
	var t := create_tween()
	t.tween_interval(0.6 if violent else 0.25)
	t.tween_property(flash, "color", Color(1.0, 0.45, 0.2, 1.0), 1.0 if violent else 0.8)
	if violent:
		t.tween_property(flash, "color", Color(0.55, 0.05, 0.02, 1.0), 1.0)
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
	overlay.set_compact(false)
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

# --- Apagado de emergencia ----------------------------------------------------------

## Los dos switches quedaron en posicion (emergency_room.gd). Se corta la
## instalacion entera y los emisores laterales, reencendidos en naranja,
## desarman lo que quede de la singularidad.
func forced_shutdown() -> void:
	if state == State.CLIMAX or state == State.ENDING or state == State.FREEZE:
		return
	# Tarde: el nucleo ya tiene demasiada masa. Los laterales se encienden
	# igual, pero en vez de desarmarlo lo encienden.
	if sim.temp > shutdown_max_temp:
		_detonation()
		return
	state = State.CLIMAX
	_shutdown_sequence()

func _shutdown_sequence() -> void:
	var bh: Node3D = driver.black_hole
	views.cinematic = true
	overlay.set_compact(false)
	overlay.clear()
	if hunger and hunger.prompts:
		hunger.prompts.clear()
	music.stop_track(2.5)
	music.stop_background(2.0)
	_stop_siren(1.5)
	lighting.alarm(false)
	driver.alive = false
	sim.meltdown_eta = -1.0
	bars.show_bars("EMERGENCY SHUTDOWN")

	# 1. Se cae todo. Queda el agujero negro como unica luz de la sala.
	bars.set_caption("FACILITY POWER // OFFLINE", Color(1.0, 0.72, 0.2))
	_play("breaker_off", 2.0, 0.6)
	for l in lasers:
		l.set_beam(0.0, 0.6)
		l.set_light_scale(0.0, 1.4)
		l.overload(0.0)
	if hunger and hunger.outside:
		hunger.outside.shut_down(2.5)
	lighting.blackout()
	create_tween().tween_property(sim, "meltdown", 0.0, 3.0)
	await _wait(1.4)
	views.shake(0.012, 0.7)
	await _wait(1.4)

	await views.go_to(&"Window", 1.6)
	await _wait(1.4)

	# 2. Los laterales vuelven solos, en naranja: ya no contienen nada, ahora
	#    son una herramienta de corte.
	bars.set_caption("LATERAL ARRAY // MANUAL OVERRIDE", shutdown_light)
	for i in mini(lateral_count, lasers.size()):
		var l: Node = lasers[i]
		l.recolor(shutdown_deep, shutdown_mid, shutdown_hot, shutdown_light)
		l.set_light_scale(1.5, 0.7)
		l.charge_up(1.7, 0.9)
		l.pulse(1.4)
		_play("plasma_ignite", -3.0, 0.75)
		views.shake(0.006, 0.25)
		await _wait(0.45)
	await _wait(1.2)

	# 3. Disparan sobre el horizonte.
	bars.set_caption("DISINTEGRATION SEQUENCE", shutdown_light)
	for i in mini(lateral_count, lasers.size()):
		var l: Node = lasers[i]
		l.beam_stop = 0.0
		l.fire(bh.global_position, 2.8, 0.22)
		_play("beam_fire", 1.0, 0.65)
		views.shake(0.014, 0.35)
		await _wait(0.28)
	_play("shield_ignite", 2.0, 0.5)
	views.shake(0.02, 0.9)

	# 4. El disco se deshilacha: mas turbulencia, filamentos finos y mucho
	#    detalle lo parten en jirones. Y la lente deja de curvar la luz: no se
	#    encoge ni se apaga, se DESARMA.
	var shred := create_tween().set_parallel()
	shred.tween_property(bh, "turbulence", 1.0, 9.0)
	shred.tween_property(bh, "noise_detail", 14.0, 9.0)
	shred.tween_property(bh, "noise_octaves", 5, 4.0)
	shred.tween_property(bh, "filament_width", 0.05, 8.0)
	shred.tween_property(bh, "filament_contrast", 8.0, 6.0)
	shred.tween_property(bh, "filament_flatten", 0.0, 6.0)
	shred.tween_property(bh, "ring_contrast", 1.0, 6.0)
	shred.tween_property(bh, "disc_opacity", 1.1, 3.0)
	shred.tween_property(bh, "disc_brightness", 2.6, 4.0)
	shred.tween_property(bh, "swirl_speed", 5.0, 9.0)
	shred.tween_property(bh, "spiral_tightness", 0.2, 9.0)
	shred.tween_property(bh, "bend_strength", 0.0, 10.0)
	shred.tween_property(bh, "disc_color_cold", shutdown_light, 5.0)
	shred.tween_property(bh, "disc_color_hot", shutdown_hot, 5.0)

	# 5. La nube: el horizonte revienta en fragmentos, cada vez mas.
	var shots := [&"CineCenter", &"CineWide", &"Window", &"CineLow"]
	for i in 8:
		if hunger:
			hunger.disintegrate(0.4 + 0.11 * i, shutdown_light)
		for j in mini(lateral_count, lasers.size()):
			lasers[j].pulse(0.8 + 0.12 * i)
		views.shake(0.008 + 0.002 * i, 0.4)
		if i == 2:
			bars.set_caption("EVENT HORIZON // LOSING COHESION", shutdown_light)
		if i == 5:
			bars.set_caption("CONTAINMENT FIELD // DISPERSING", shutdown_light)
		if i % 3 == 2:
			views.go_to(shots[(i / 3) % shots.size()], 1.8)
		await _wait(1.1)

	# 6. El golpe final: el horizonte se va entero en la nube y los emisores
	#    se apagan. Nunca se lo ve encogerse: desaparece tapado por sus restos.
	if hunger:
		hunger.disintegrate(2.4, shutdown_hot)
		hunger.disintegrate(1.8, shutdown_light)
	_play("implosion", 1.0, 0.55)
	views.shake(0.03, 1.4)
	await _wait(0.35)
	bh.visible = false
	for i in mini(lateral_count, lasers.size()):
		lasers[i].set_beam(0.0, 1.2)
		lasers[i].set_light_scale(0.25, 2.0)
	await _wait(2.6)

	bars.set_caption("SINGULARITY DISPERSED", bars.ok_color)
	_play("cryo_freeze", -6.0, 0.6)
	await _wait(3.2)
	endings.unlock(&"shutdown")
	await _wait(1.6)
	await bars.hide_bars()
	state = State.ENDING
	restore.play("EMERGENCY SHUTDOWN")

# --- Core detonation ----------------------------------------------------------------

## El apagado de emergencia tirado tarde. Arranca IGUAL que el bueno (se corta
## la instalacion, los laterales vuelven en naranja y disparan) para que el
## jugador crea por un momento que llego a tiempo. Pero el nucleo ya tiene
## demasiada masa: en vez de deshilacharse se come el disparo, los laterales
## revientan por la realimentacion y el intento de destruirlo es lo que lo
## enciende. No se derrite: estalla hacia afuera, al compas de la pista.
##
## La pista salta a DET_START, asi que todo cae en tiempos fijos de "Kinetic
## Energy" aunque el jugador haya tirado el switch en cualquier momento.
func _detonation() -> void:
	state = State.CLIMAX
	_ending = &"detonation"
	var bh: Node3D = driver.black_hole
	var calm: bool = settings != null and bool(settings.get_value("reduce_flashing"))
	views.cinematic = true
	overlay.set_compact(false)
	overlay.clear()
	if hunger and hunger.prompts:
		hunger.prompts.clear()
	if routing:
		routing.stop()
	sim.meltdown_eta = 0.0
	music.seek_track(DET_START)
	_stop_siren(0.4)
	lighting.alarm(false)
	driver.alive = false
	var laterals: Array = lasers.slice(0, mini(lateral_count, lasers.size()))

	# 1. El intento. Lo mismo que el apagado bueno: se cae la instalacion.
	bars.show_bars("EMERGENCY SHUTDOWN")
	bars.set_caption("FACILITY POWER // OFFLINE", Color(1.0, 0.72, 0.2))
	_play("breaker_off", 2.0, 0.6)
	for l in lasers:
		l.set_beam(0.0, 0.5)
		l.set_light_scale(0.0, 1.0)
		l.overload(0.0)
	if hunger and hunger.outside:
		hunger.outside.shut_down(2.0)
	lighting.blackout()
	views.shake(0.012, 0.6)
	views.go_to(&"Window", 1.6)

	await _at(DET_START + 2.0)
	bars.set_caption("LATERAL ARRAY // MANUAL OVERRIDE", shutdown_light)
	for l in laterals:
		l.recolor(shutdown_deep, shutdown_mid, shutdown_hot, shutdown_light)
		l.set_light_scale(1.5, 0.6)
		l.charge_up(1.7, 0.8)
		l.pulse(1.4)
		_play("plasma_ignite", -3.0, 0.75)
		views.shake(0.006, 0.25)
		await _wait(0.4)

	await _at(DET_START + 4.0)
	bars.set_caption("DISINTEGRATION SEQUENCE", shutdown_light)
	for l in laterals:
		l.beam_stop = 0.0
		l.fire(bh.global_position, 2.8, 0.22)
		_play("beam_fire", 1.0, 0.65)
		views.shake(0.014, 0.3)
		await _wait(0.25)
	if hunger:
		hunger.disintegrate(0.5, shutdown_light)
	# Por un segundo parece que funciona: el disco empieza a deshilacharse.
	var fray := create_tween().set_parallel()
	fray.tween_property(bh, "turbulence", 0.9, 1.6)
	fray.tween_property(bh, "filament_contrast", 6.0, 1.6)
	fray.tween_property(bh, "disc_color_cold", shutdown_light, 1.6)

	# 2. No funciona. El nucleo se come el disparo: en vez de soltar la luz,
	#    la curva mas; en vez de apagarse, se enciende.
	await _at(DET_START + 5.6)
	fray.kill()
	var alarm_red := Color(1.0, 0.25, 0.2)
	bars.set_caption("CORE MASS ABOVE LIMIT", alarm_red)
	_play("metal_groan", 2.0, 0.55)
	views.go_to(&"CineCenter", 2.5)
	var absorb := create_tween().set_parallel()
	absorb.tween_property(bh, "bend_strength", 2.0, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	absorb.tween_property(bh, "disc_brightness", 2.4, 2.4)
	absorb.tween_property(bh, "swirl_speed", 9.0, 2.4)
	absorb.tween_property(bh, "turbulence", 0.3, 1.2)
	absorb.tween_property(bh, "disc_color_hot", Color(1.0, 0.97, 0.9), 2.0)
	for l in laterals:
		l.pulse(2.5)
		l.spark(1.2)
	views.shake(0.016, 1.0)

	await _at(DET_START + 6.8)
	bars.set_caption("ENERGY ABSORBED // FEEDBACK", alarm_red)
	for l in laterals:
		l.overload(1.0)
		l.charge_up(3.0, 0.8)
		l.spark(1.6)
	_play("shield_ignite", 2.0, 0.45)
	views.shake(0.022, 1.2)

	# 3. NO_RETURN: los laterales revientan por la realimentacion.
	await _at(NO_RETURN)
	bars.show_bars("CORE DETONATION")
	bars.set_caption("LATERAL ARRAY // DESTROYED", alarm_red)
	for i in laterals.size():
		if hunger and hunger.alive(laterals[i]):
			get_tree().create_timer(0.1 * i, false).timeout.connect(
				hunger.devour_laser.bind(laterals[i], 1.2))
	if hunger:
		hunger.shockwave(2.2)
		hunger.disintegrate(1.2, shutdown_hot)
		for i in hunger.monitors.size():
			var m: Node = hunger.monitors[i]
			if m.get("screen"):
				get_tree().create_timer(0.08 * i, false).timeout.connect(m.screen.fail)
	_micro_flash(0.55, calm)
	_play("explosion", -2.0, 1.3)
	views.shake(0.034, 1.4)
	shield.flash(2.0)
	# Y despues, el vacio: todo se hunde un instante antes del golpe.
	var inhale := create_tween().set_parallel()
	inhale.tween_property(bh, "sphere_radius", bh.sphere_radius * 0.55, 3.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	inhale.tween_property(bh, "disc_radius", bh.disc_radius * 0.6, 3.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	inhale.tween_property(bh, "disc_brightness", 0.35, 3.0)
	for l in lasers:
		l.set_beam(0.0, 1.0)
	await _at(NO_RETURN + 1.2)
	bars.set_caption("", alarm_red)
	_dolly = views.dolly(Vector3(0.0, 0.0, -0.3), 2.2)

	# 4. CLIMAX_T: la ignicion. El agujero negro revienta hacia afuera.
	await _cut(&"CineCenter", CLIMAX_T)
	inhale.kill()
	bars.set_caption("CORE IGNITION", alarm_red)
	shield.shatter()
	_climax_hunger()
	_micro_flash(0.9, calm)
	_play("explosion", 3.0, 0.7)
	_play("glass_shatter", 3.0)
	_play("shield_ignite", 4.0, 0.4)
	views.shake(0.04, 1.6)
	if hunger:
		hunger.shockwave(2.8)
		hunger.disintegrate(2.2, Color(1.0, 0.95, 0.8))
		hunger.disintegrate(1.6, shutdown_mid)
	for l in lasers:
		l.overload(1.0)
	bh.disc_color_cold = Color(1.0, 0.32, 0.05)
	bh.disc_color_hot = Color(1.0, 0.98, 0.92)
	var burst := create_tween().set_parallel()
	var burst_t := FINAL_HIT - CLIMAX_T - 4.0
	burst.tween_property(bh, "sphere_radius", 0.3, burst_t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	burst.tween_property(bh, "disc_radius", 3.5, burst_t * 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	burst.tween_property(bh, "disc_brightness", 3.0, 1.0)
	burst.tween_property(bh, "disc_opacity", 1.1, 1.0)
	burst.tween_property(bh, "disc_thickness_ratio", 0.12, 3.0)
	burst.tween_property(bh, "turbulence", 1.0, 2.0)
	burst.tween_property(bh, "noise_detail", 12.0, 3.0)
	burst.tween_property(bh, "filament_contrast", 7.0, 2.0)
	burst.tween_property(bh, "ring_contrast", 1.0, 2.0)
	burst.tween_property(bh, "doppler_strength", 1.0, 2.0)
	burst.tween_property(bh, "swirl_speed", 14.0, 6.0)
	burst.tween_property(bh, "bend_strength", 2.6, burst_t)
	burst.tween_property(bh, "disc_tilt_degrees", bh.disc_tilt_degrees + DISC_TILT * 0.5, 5.0).set_trans(Tween.TRANS_SINE)
	_detonation_beats(CLIMAX_T, FINAL_HIT, calm)

	# Cortes cada medio compas en vez de cada compas: la mitad del tiempo en
	# cada plano que el derretimiento normal.
	var shots := [&"CineWide", &"Window", &"CineLow", &"Room", &"CineCenter", &"CineWide",
		&"CineLow", &"Window", &"Room", &"CineCenter", &"Room"]
	var captions := {
		0: "GRAVITATIONAL RUNAWAY",
		3: "HORIZON UNBOUND",
		6: "IT IS NOT COLLAPSING",
		8: "IT IS IGNITING",
	}
	for i in shots.size():
		await _cut(shots[i], CLIMAX_T + BAR * 0.5 * (i + 2))
		if captions.has(i):
			bars.set_caption(captions[i], alarm_red)

	# 5. La llamarada llega a la sala. Mas grande y mas rapido que el
	#    derretimiento: ahi el horizonte se TRAGA la sala, aca la QUEMA.
	burst.kill()
	var left := maxf(FINAL_HIT - 0.5 - _now(), 0.5)
	var flare := create_tween().set_parallel()
	flare.tween_property(bh, "disc_radius", 45.0, left).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	flare.tween_property(bh, "sphere_radius", 1.2, left).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	flare.tween_property(bh, "disc_inner_ratio", 1.2, left)
	flare.tween_property(bh, "disc_falloff", 0.25, left)
	flare.tween_property(bh, "disc_brightness", 4.0, left)
	flare.tween_property(bh, "swirl_speed", 20.0, left)

	# 6. Sin implosion: el ultimo golpe es luz. Se funde a blanco ANTES del
	#    golpe y el estallido lo sostiene.
	await _at(FINAL_HIT - 0.5)
	flash.visible = true
	flash.color = Color(1.0, 0.97, 0.9, 0.0)
	create_tween().tween_property(flash, "color:a", 0.75 if calm else 1.0, 0.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_play("implosion", 2.0, 1.4)
	await _at(FINAL_HIT)
	flare.kill()
	_explosion(true)
	await get_tree().create_timer(3.4, false).timeout
	await bars.hide_bars()
	endings.unlock(&"detonation")
	await get_tree().create_timer(1.0, false).timeout
	state = State.ENDING
	restore.play("CORE DETONATION")

## Golpes al compas del estallido: mas fuertes que los del derretimiento, y
## en cada compas una onda, una rafaga de fragmentos y un destello.
func _detonation_beats(from: float, to: float, calm: bool) -> void:
	var b := int(ceil(from / BEAT))
	while b * BEAT < to - 1.5:
		await _at(b * BEAT)
		if state != State.CLIMAX:
			return
		var k := clampf((b * BEAT - from) / (to - from), 0.0, 1.0)
		views.shake(0.012 + 0.03 * k, 0.3)
		shield.flash(0.4 + k)
		if b % 4 == 0 and hunger:
			hunger.shockwave(1.4 + 1.2 * k)
			hunger.disintegrate(0.8 + 1.4 * k,
				Color(1.0, 0.95, 0.8) if b % 8 == 0 else shutdown_mid)
			_micro_flash(0.25 + 0.3 * k, calm)
		elif b % 2 == 0 and hunger and k > 0.4:
			hunger.disintegrate(0.5 + k, shutdown_light)
		b += 1

## Destello corto de pantalla (menos con "reduce flashing").
func _micro_flash(amount: float, calm: bool) -> void:
	if flash == null:
		return
	var a := amount * (0.3 if calm else 1.0)
	flash.visible = true
	flash.color = Color(1.0, 0.9, 0.75, a)
	var t := create_tween()
	t.tween_property(flash, "color:a", 0.0, 0.22 + 0.25 * amount)

## Espera que no depende de la musica (en el apagado ya no hay pista sonando).
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

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
