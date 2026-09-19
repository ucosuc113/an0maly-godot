extends Node

# Simulacion del reactor: convierte las palancas (control_panel.gd) y las
# fases en los numeros que muestran los monitores (y, despues, en lo que le
# pasa al agujero negro y en los finales).
#
# Cada sistema tiene un objetivo (lo que pide la palanca) y un valor real que
# lo sigue con inercia: el jugador ve venir las consecuencias.
#
#   route       caudal de refrigerante: si el jugador deja cortado el tablero
#               de reles (coolant_routing.gd) durante el derretimiento, el
#               escudo se queda sin refrigeracion y se degrada mucho mas rapido
#   lasers      potencia lateral / diagonal (fase 1)
#   fans        velocidad de los ventiladores (fase 1)
#   injection   inyeccion de plasma (fase 1)
#   temp        temperatura del nucleo. Los lasers la suben y la refrigeracion
#               la baja, pero el refrigerante del escudo es CRIOGENICO: con
#               caudal alto y los lasers bajos empuja el nucleo por debajo del
#               ambiente, hasta CRYO_FLOOR. Esa es la competencia real entre
#               las palancas de energia y las de frio, y es lo que leen los
#               finales: nadie mira en que numero quedo una palanca, miran la
#               temperatura.
#   shield      densidad, estres, integridad, refrigeracion (fase 2)
#   core/disc   masa, giro, carga, desalineacion, disco de acrecion (fase 3)
#
# Los valores son de ciencia ficcion: sirven para leer tendencias, no para
# hacer cuentas.

signal status_changed(status: StringName)

## Hasta donde puede bajar el nucleo (la misma cifra que canta el final de
## congelamiento).
const CRYO_FLOOR := 0.3
## Umbrales de LECTURA para el estado del panel. Los que disparan los finales
## viven en crisis_director.gd (overheat_temp / cryo_temp).
const HOT := 9000.0
const COLD := 120.0
## Piso de temperatura en derretimiento: FLOOR + meltdown * SPAN. Con meltdown
## yendo de 0.25 a 1.0 por la pista, va de 16.5K a 39K.
const MELTDOWN_FLOOR := 9000.0
const MELTDOWN_SPAN := 30000.0

@export var panel: Node
## coolant_routing.gd (opcional): el tablero de reles del refrigerante.
@export var routing: Node
## Cuanto enfria cada punto de caudal por debajo del ambiente. Subirlo hace
## mas facil llegar al congelamiento con los lasers encendidos.
@export var cryo_power: float = 16.0

## Sistemas activos (los encienden las fases).
var lasers_online: bool = false
var shield_online: bool = false
var singularity_online: bool = false
## Fase 2 en curso: el escudo existe pero todavia se esta formando.
var shield_forming: bool = false
## Fase 3 en curso: la singularidad se esta formando (antes del drop).
var singularity_forming: bool = false

# --- Crisis (las maneja crisis_director.gd) ------------------------------------------
## 0..1: derretimiento en curso (calor, inestabilidad y escudo que cede).
var meltdown: float = 0.0
## Segundos hasta el punto de no retorno (-1 = sin cuenta regresiva).
var meltdown_eta: float = -1.0
## 0..1: estabilizacion forzada (lleva todo a valores seguros).
var stabilizing: float = 0.0
## 0..1: congelamiento criogenico.
var frozen: float = 0.0

# --- Valores (objetivo / real) ------------------------------------------------------
var lat_goal: float = 0.0
var lat_power: float = 0.0
var dia_goal: float = 0.0
var dia_power: float = 0.0
var fan_goal: float = 0.0
var fan_rpm: float = 0.0
var injection: float = 0.0
var temp: float = 22.0
var coolant: float = 0.0
## 0..1: cuanto refrigerante llega de verdad (1 = ruta entera).
var route: float = 1.0
## El boton criogenico vacio las reservas sobre el nucleo. No tiene vuelta:
## desde aqui no queda refrigerante NI se pueden volver a encender los
## ventiladores (por lore, el liquido que los mueve se fue todo).
var purged: bool = false
var purge_t: float = 0.0
var purge_time: float = 30.0
## El golpe de refrigerante alcanzo: el nucleo se va al fondo y se queda ahi.
## Si no alcanzo, el frenazo sube y se agota, y despues no queda nada.
var quench_holds: bool = true
var shield_density: float = 0.0
var shield_stress: float = 0.0
var shield_integrity: float = 100.0
var disc_saturation: float = 0.0
var disc_temp: float = 0.0
var disc_spin: float = 0.0
var core_mass: float = 0.0
var core_spin: float = 0.0
var core_charge: float = 0.0
var core_misalign: float = 0.0
var core_flux: float = 0.0
var generation: float = 0.0
## 0 = estable, 1 = a punto de reventar.
var instability: float = 0.0
var status: StringName = &"STANDBY"

## Historial para la grafica (monitor izquierdo): cada muestra es
## [lateral, diagonal, temperatura, refrigeracion], normalizados 0..1.
const HISTORY_SIZE := 120
const HISTORY_STEP := 0.25
var history: Array = []
var _history_t: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	if panel:
		panel.phase_completed.connect(_on_phase_completed)

func _on_phase_completed(phase: int) -> void:
	# La fase 1 la activa su secuencia (antes, cuando se encienden los lasers).
	match phase:
		1: lasers_online = true
		2: shield_online = true
		3: singularity_online = true

## Vacia las reservas sobre el nucleo. Irreversible.
func purge(seconds: float, holds: bool) -> void:
	if purged:
		return
	purged = true
	quench_holds = holds
	purge_time = seconds
	purge_t = 0.0

func level(id: StringName) -> int:
	return panel.get_level(id) if panel else 1

func _process(delta: float) -> void:
	_time += delta
	var lat := level(&"lateral")
	var dia := level(&"diagonal")
	var fans := level(&"fans")
	var cool := level(&"shield")

	# Lasers: la potencia sigue al objetivo a velocidad fija (se ve el retraso).
	lat_goal = 180.0 * lat if lasers_online else 0.0
	dia_goal = 140.0 * dia if lasers_online else 0.0
	lat_power = move_toward(lat_power, lat_goal, 55.0 * delta)
	dia_power = move_toward(dia_power, dia_goal, 45.0 * delta)
	# Purgado: los ventiladores no vuelven nunca.
	fan_goal = 0.0 if purged else (300.0 + 450.0 * fans if lasers_online else 0.0)
	fan_rpm = move_toward(fan_rpm, fan_goal, 400.0 * delta)
	injection = (lat_power + dia_power) * 0.013

	# Refrigeracion del escudo: los lasers laterales la hacen, y le quitan
	# algo de potencia efectiva. Con la ruta cortada no llega caudal.
	var routed: bool = routing == null or not routing.active or routing.flow
	route = _approach(route, 1.0 if routed else 0.0, 1.2, delta)
	var coolant_goal := 0.0 if purged else \
		((18.0 * cool + 10.0) * route if shield_online else 0.0)
	coolant = move_toward(coolant, coolant_goal, 12.0 * delta)
	var cooling := 1.0 + fan_rpm / 900.0 + coolant * 0.025

	# Balance termico: los lasers calientan, los ventiladores y el caudal se
	# lo llevan, y el caudal ademas empuja hacia abajo (criogenico).
	var temp_goal := 22.0 + (lat_power * 18.0 + dia_power * 26.0) / cooling
	temp_goal = maxf(temp_goal - coolant * cryo_power, CRYO_FLOOR)
	temp_goal += meltdown * 26000.0
	# Piso del derretimiento: la temperatura sigue al reloj de la pista y no a
	# como quedaron las palancas. Los umbrales de la sala de emergencia
	# (crisis_director.gd) son temperaturas, y asi caen siempre en el mismo
	# momento del derretimiento: 16.5K al arrancar, 39K en el no retorno.
	if meltdown > 0.0:
		temp_goal = maxf(temp_goal, MELTDOWN_FLOOR + meltdown * MELTDOWN_SPAN)
	# El golpe de la purga. Son las reservas ENTERAS de la instalacion cayendo
	# sobre el nucleo: mientras caen mandan sobre todo lo demas.
	if purged:
		purge_t += delta
		var k := clampf(purge_t / maxf(purge_time, 0.001), 0.0, 1.0)
		if quench_holds:
			# Alcanzo: baja hasta el fondo y se queda.
			temp_goal = lerpf(temp_goal, CRYO_FLOOR, ease(k, 0.5))
		else:
			# No alcanzo: el frenazo pega fuerte y se agota solo. Queda un
			# nucleo sin refrigeracion y sin reservas.
			temp_goal = lerpf(temp_goal, temp_goal * 0.28, sin(k * PI))
		temp_goal = maxf(temp_goal, CRYO_FLOOR)
	temp_goal = lerpf(temp_goal, 2800.0, stabilizing)
	temp_goal = lerpf(temp_goal, CRYO_FLOOR, frozen)
	temp = _approach(temp, temp_goal, 4.0 if meltdown <= 0.0 else 6.0, delta)

	# Escudo.
	if shield_online:
		shield_stress = _approach(shield_stress,
			(lat_power * 0.05 + dia_power * 0.09 + temp * 0.0015) * (1.6 - coolant / 100.0), 2.5, delta)
		if shield_stress > 100.0:
			shield_integrity -= (shield_stress - 100.0) * 0.02 * delta
		elif shield_stress < 80.0:
			shield_integrity += 0.8 * delta
		shield_integrity -= meltdown * 0.35 * delta
		# Sin caudal el escudo se cocina.
		shield_integrity -= (1.0 - route) * 1.8 * delta
		shield_integrity += stabilizing * 6.0 * delta
		shield_integrity = clampf(shield_integrity, 0.0, 100.0)
		shield_density = _approach(shield_density,
			clampf(100.0 - shield_stress * 0.25, 5.0, 100.0) * shield_integrity / 100.0, 1.5, delta)
	else:
		shield_density = _approach(shield_density, 0.0, 1.0, delta)

	# Singularidad y disco.
	if singularity_online:
		core_mass += dia_power * 0.0008 * delta
		core_spin = _approach(core_spin, (lat_power * 880.0 + dia_power * 310.0) * (1.0 + meltdown * 2.0) * (1.0 - frozen), 3.0, delta)
		core_charge = _approach(core_charge, (dia - lat) * 12.0, 2.0, delta)
		core_misalign = _approach(core_misalign, absf(lat - dia) * 120.0 + (100.0 - shield_integrity) * 3.0, 2.0, delta)
		core_flux = _approach(core_flux, (lat_power + dia_power) * core_spin * 1e-6, 1.5, delta)
		disc_saturation = _approach(disc_saturation, clampf((lat_power + dia_power) / 16.0, 0.0, 100.0), 3.0, delta)
		disc_temp = _approach(disc_temp, temp * 8.5, 3.0, delta)
		disc_spin = _approach(disc_spin, core_spin * 0.085, 3.0, delta)
		core_mass += meltdown * 4.0 * delta
		generation = _approach(generation, (lat_power + dia_power) * 3600.0 * (0.5 + disc_saturation / 200.0), 2.0, delta)
	else:
		generation = _approach(generation, (lat_power + dia_power) * 1.8, 1.0, delta)

	instability = clampf(maxf((temp - 6000.0) / 12000.0,
		maxf((100.0 - shield_integrity) / 100.0 if shield_online else 0.0, core_misalign / 1500.0)), 0.0, 1.0)
	instability = maxf(instability, meltdown)
	instability *= (1.0 - stabilizing) * (1.0 - frozen)
	_update_status()

	_history_t += delta
	while _history_t >= HISTORY_STEP:
		_history_t -= HISTORY_STEP
		history.append([lat_power / 900.0, dia_power / 700.0,
			clampf(temp / 20000.0, 0.0, 1.0), coolant / 100.0])
		if history.size() > HISTORY_SIZE:
			history.pop_front()

func _update_status() -> void:
	var s: StringName = &"STANDBY"
	if lasers_online:
		s = &"EMITTERS ONLINE"
	if shield_online:
		s = &"SHIELD FORMING" if shield_forming else &"SHIELD STABLE"
	if singularity_forming:
		s = &"SINGULARITY FORMING"
	if singularity_online:
		s = &"SINGULARITY STABLE"
	if shield_online and shield_integrity < 70.0:
		s = &"SHIELD DEGRADING"
	if temp > HOT:
		s = &"CORE OVERHEAT"
	if temp < COLD:
		s = &"CORE SUPERCOOLED"
	if instability > 0.85:
		s = &"CRITICAL"
	if meltdown > 0.0:
		s = &"MELTDOWN"
	if stabilizing > 0.0:
		s = &"STABILIZING"
	if frozen > 0.0:
		s = &"CRYO LOCK"
	if s != status:
		status = s
		status_changed.emit(s)

## Nivel de alarma del estado: 0 normal, 1 aviso, 2 critico.
func alarm() -> int:
	match status:
		&"CRITICAL", &"MELTDOWN":
			return 2
		&"SHIELD DEGRADING", &"CORE OVERHEAT":
			return 1
	return 0

## Acerca value a goal con constante de tiempo tau (segundos).
func _approach(value: float, goal: float, tau: float, delta: float) -> float:
	return lerpf(value, goal, 1.0 - exp(-delta / maxf(tau, 0.001)))
