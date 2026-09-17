extends Node

# Fase 1 (boton 01): luces del exterior + salen los lasers + se carga la
# energia. Secuencia cinematografica:
#
#   corte al ventanal completo -> franjas de cine y subtitulo
#   el exterior se enciende de arriba abajo (outside_power.gd)
#   salen los lasers laterales (azules), escalonados; cada golpe al asentarse
#   sacude la camara
#   se despliega la matriz diagonal (morados), desde las esquinas
#   ignicion: primero los laterales, luego los diagonales -> "EMITTERS ONLINE"
#   corte a la sala: se encienden los monitores de telemetria (solo muestran
#   lo que ya existe; el resto, NO SIGNAL)
#   salen las franjas -> vuelta a la vista del panel -> fase completa (se
#   destapa el boton 02)
#
# Toda la secuencia corre con un empuje lento de camara.

const PHASE := 1

@export var panel: Node
@export var views: Node
@export var bars: Node
@export var outside: Node
## Lasers laterales (laser_emitter.gd).
@export var lasers: Array[Node] = []
## Lasers diagonales (laser_emitter.gd).
@export var diagonal_lasers: Array[Node] = []
## Nodo con reactor_sim.gd: los lasers cuentan desde que se encienden.
@export var sim: Node
## Monitores (info_monitor.gd), en el orden en que se encienden.
@export var monitors: Array[Node] = []
@export var cinematic_view: StringName = &"Window"
@export var monitors_view: StringName = &"Room"
@export var return_view: StringName = &"Panel"
@export var laser_stagger: float = 0.45
@export var diagonal_stagger: float = 0.3
@export var ignite_stagger: float = 0.35
@export var diagonal_ignite_stagger: float = 0.22

var _pending: int = 0

func _ready() -> void:
	if panel:
		panel.register_phase(PHASE)
		panel.phase_started.connect(_on_phase_started)
	for l in lasers + diagonal_lasers:
		if l:
			l.locked.connect(_on_laser_locked)

func _on_phase_started(index: int) -> void:
	if index == PHASE:
		_run()

func _run() -> void:
	# Deja ver el boton hundiendose antes del corte.
	await _wait(0.45)
	views.cinematic = true
	await views.go_to(cinematic_view)
	var dolly: Tween = views.dolly(Vector3(0.0, 0.045, -0.3), 19.0)
	bars.show_bars("PHASE 01 // PLASMA INJECTION")
	await _wait(0.9)

	outside.power_on()
	await _wait(0.7)

	bars.set_caption("LATERAL EMITTERS // DEPLOY")
	await _all(lasers, "rise", laser_stagger)

	bars.set_caption("DIAGONAL ARRAY // DEPLOY")
	await _wait(0.3)
	await _all(diagonal_lasers, "rise", diagonal_stagger)

	bars.set_caption("EMITTERS LOCKED // IGNITION")
	await _wait(0.6)
	if sim:
		sim.lasers_online = true
	await _all(lasers, "ignite", ignite_stagger)
	await _wait(0.2)
	await _all(diagonal_lasers, "ignite", diagonal_ignite_stagger)

	bars.set_caption("EMITTERS ONLINE", bars.ok_color)
	await _wait(2.2)

	# Telemetria: los monitores de la sala se encienden uno tras otro.
	if not monitors.is_empty():
		bars.set_caption("TELEMETRY // LINK")
		if dolly and dolly.is_valid():
			dolly.kill()
		await views.go_to(monitors_view)
		await _wait(0.5)
		for m in monitors:
			if m:
				m.power_on()
				await _wait(0.45)
		await _wait(2.4)
		bars.set_caption("TELEMETRY ONLINE", bars.ok_color)
		await _wait(1.4)

	await bars.hide_bars()
	if dolly and dolly.is_valid():
		dolly.kill()
	views.cinematic = false
	await views.go_to(return_view)
	panel.complete_phase(PHASE)

## Llama `method` en cada laser, escalonado, y espera a que terminen todos.
func _all(group: Array[Node], method: String, stagger: float) -> void:
	_pending = 0
	for i in group.size():
		if group[i]:
			_one(group[i], method, i * stagger)
	while _pending > 0:
		await get_tree().process_frame

func _one(laser: Node, method: String, delay: float) -> void:
	_pending += 1
	await _wait(delay)
	await laser.call(method)
	_pending -= 1

func _on_laser_locked() -> void:
	views.shake(0.006, 0.22)

func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds, false).timeout
