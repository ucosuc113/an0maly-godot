extends Node

# Estado del panel de control. Vive como nodo en main.tscn (ControlPanel).
#
#   Fases de inicializacion (botones, en orden):
#     1  luces del fondo + salen los lasers + se carga la energia
#     2  escudo gravitatorio alrededor del punto de la singularidad
#     3  singularidad: aparece el agujero negro
#   Con las 3 fases hechas se destapan las 4 palancas (niveles 1..5).
#
# Flujo de un boton:
#   press_phase(i) -> phase_started(i)  (quien hace los efectos los corre)
#   complete_phase(i) -> phase_completed(i) -> se desliza la tapa del boton
#   siguiente -> phase_ready(i + 1). Tras la fase 3 se desliza la tapa de las
#   palancas -> levers_unlocked.
#
# Las fases con secuencia propia (phase_one.gd...) se registran con
# register_phase() y llaman complete_phase() al terminar. Las demas se
# completan solas a los placeholder_duration segundos.

signal phase_started(phase: int)
signal phase_completed(phase: int)
signal phase_ready(phase: int)
signal level_changed(lever: StringName, level: int)
signal levers_unlocked

const LEVEL_MIN := 1
const LEVEL_MAX := 5
const PHASES := 3

## Nodos de las palancas (sus placas), por id.
@export var lever_lateral: Node3D
@export var lever_diagonal: Node3D
@export var lever_fans: Node3D
@export var lever_shield: Node3D
## Nodos de los botones de fase, en orden (fase 1, 2, 3).
@export var phase_buttons: Array[Node3D] = []
## Tapas (sliding_cover.gd) de los botones 2 y 3, en orden.
@export var button_covers: Array[Node] = []
## Tapa (sliding_cover.gd) de las 4 palancas.
@export var lever_cover: Node
## Duracion de cada fase mientras no haya efectos que la completen.
## 0 = esperar a que alguien llame complete_phase().
@export var placeholder_duration: float = 2.0

## Fases completadas (0..3).
var phase: int = 0
## Fase en curso (0 = ninguna).
var running: int = 0
## Ultimo boton destapado y listo para usarse.
var ready_upto: int = 1
var unlocked: bool = false
## Fases que completa su propia secuencia.
var _handled: Array[int] = []
var levels: Dictionary = {
	&"lateral": LEVEL_MIN,
	&"diagonal": LEVEL_MIN,
	&"fans": LEVEL_MIN,
	&"shield": LEVEL_MIN,
}

func lever_nodes() -> Dictionary:
	return {
		&"lateral": lever_lateral,
		&"diagonal": lever_diagonal,
		&"fans": lever_fans,
		&"shield": lever_shield,
	}

func levers_locked() -> bool:
	return not unlocked

## Estado de un boton de fase (1..3): "done", "running", "ready" o "locked".
func button_state(index: int) -> String:
	if index <= phase:
		return "done"
	if index == running:
		return "running"
	if index == phase + 1 and index <= ready_upto and running == 0:
		return "ready"
	return "locked"

## Una secuencia se hace cargo de la fase `index` (sin temporizador).
func register_phase(index: int) -> void:
	if index not in _handled:
		_handled.append(index)

## Inicia la fase `index` si es la que toca. Devuelve si se acepto.
func press_phase(index: int) -> bool:
	if button_state(index) != "ready":
		return false
	running = index
	phase_started.emit(index)
	if placeholder_duration > 0.0 and index not in _handled:
		await get_tree().create_timer(placeholder_duration).timeout
		complete_phase(index)
	return true

## La fase `index` termino (lo llama quien corre sus efectos).
func complete_phase(index: int) -> void:
	if running != index:
		return
	running = 0
	phase = index
	phase_completed.emit(index)
	if index < PHASES:
		var cover: Node = button_covers[index - 1] if index - 1 < button_covers.size() else null
		if cover:
			await cover.open()
		ready_upto = index + 1
		phase_ready.emit(index + 1)
	else:
		if lever_cover:
			await lever_cover.open()
		unlocked = true
		levers_unlocked.emit()

func get_level(lever: StringName) -> int:
	return levels.get(lever, LEVEL_MIN)

func set_level(lever: StringName, level: int) -> void:
	if levers_locked() or not levels.has(lever):
		return
	level = clampi(level, LEVEL_MIN, LEVEL_MAX)
	if levels[lever] == level:
		return
	levels[lever] = level
	level_changed.emit(lever, level)
