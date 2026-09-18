extends "res://scripts/monitor_screen.gd"

# Monitor derecho (200x100): refrigeracion e inyeccion.
#
#   COOLANT FANS    velocidad real (grande), objetivo, ventilador que gira a la
#                   velocidad real
#   PLASMA INJECT   tasa de inyeccion (grande) y el electron en orbita: mas
#                   rapido con mas energia, y la orbita tiembla y se deforma
#                   con la inestabilidad
#
# Durante el derretimiento la pantalla cambia de trabajo: pasa a ser el
# tablero de reles del refrigerante y se opera con el mouse (ver abajo).

## coolant_routing.gd (lo pasa info_monitor.gd).
var routing: Node

var _fan_angle: float = 0.0
var _orbit_angle: float = 0.0
var _last_time: float = 0.0
## Celda bajo el puntero: [col, row] o vacio.
var _hover_cell: Array = []

func _draw_live() -> void:
	# El reloj se lleva al dia aunque la pantalla este en el tablero: si no, al
	# volver, el ventilador pegaria un salto de varios minutos.
	var dt := time - _last_time
	_last_time = time
	if _routing_live():
		_draw_routing()
		return
	_fan_angle = wrapf(_fan_angle + sim.fan_rpm / 60.0 * TAU * 0.05 * dt, 0.0, TAU)
	_orbit_angle = wrapf(_orbit_angle + (1.0 + sim.injection * 0.35) * dt * 2.0, 0.0, TAU)
	var half := int(size.x) / 2
	_draw_fans(Rect2i(0, 0, half - 1, int(size.y)))
	_draw_injection(Rect2i(half + 1, 0, int(size.x) - half - 1, int(size.y)))

func _draw_fans(r: Rect2i) -> void:
	var inner := panel_box(r, "COOLANT FANS")
	if not sim.lasers_online:
		no_signal(inner)
		return
	text("SPEED:", inner.position + Vector2i(0, 2), DIM)
	text("%d" % int(sim.fan_rpm), inner.position + Vector2i(0, 12), VALUE, 2)
	text("RPM", inner.position + Vector2i(0, 29), DIM)
	row("GOAL", "%d" % int(sim.fan_goal), inner.position.x, inner.end.y - 8, 50)
	# Ventilador.
	var c := Vector2(inner.end.x - 20, inner.end.y - 22)
	_circle(c, 17.0, FRAME)
	_circle(c, 3.0, VALUE)
	for i in 4:
		var a := _fan_angle + TAU * i / 4.0
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x)
		var tip := c + d * 14.0 + n * 3.0
		var root := c + d * 4.0
		draw_line(root.round(), tip.round(), COOL)
		draw_line((root + n * 2.0).round(), (tip - n * 2.0).round(), COOL)

func _draw_injection(r: Rect2i) -> void:
	var inner := panel_box(r, "PLASMA INJECT")
	if not sim.lasers_online:
		no_signal(inner)
		return
	text("RATE:", inner.position + Vector2i(0, 2), DIM)
	text("%.1f" % sim.injection, inner.position + Vector2i(0, 12), VALUE, 2)
	text("G/S", inner.position + Vector2i(0, 29), DIM)
	var inst: float = sim.instability
	row("STAB", "%.0f%%" % ((1.0 - inst) * 100.0), inner.position.x, inner.end.y - 8, 50,
		WARN if inst > 0.5 else VALUE)
	# Electron en orbita alrededor del nucleo.
	var c := Vector2(inner.end.x - 20, inner.end.y - 22)
	_circle(c, 7.0, VALUE)
	text("E-", Vector2i(c) - Vector2i(5, 3), VALUE)
	var tilt := 0.45 + 0.25 * sin(time * 0.7)
	var wobble := inst * 4.0
	var rot := time * 0.4
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		var rad := 16.0 + sin(a * 3.0 + time * 9.0) * wobble
		pts.append(c + _orbit_point(a, rad, tilt, rot))
	draw_polyline(pts, Color(FRAME, 0.9))
	var e := c + _orbit_point(_orbit_angle, 16.0, tilt, rot)
	draw_rect(Rect2(e.round() - Vector2(1, 1), Vector2(3, 3)), COOL)

func _orbit_point(a: float, rad: float, tilt: float, rot: float) -> Vector2:
	var p := Vector2(cos(a) * rad, sin(a) * rad * tilt)
	return p.rotated(rot)

func _circle(c: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := int(maxf(12.0, rad * 3.0))
	for i in steps + 1:
		var a := TAU * i / steps
		pts.append((c + Vector2(cos(a), sin(a)) * rad).round())
	draw_polyline(pts, col)

# --- Rearmado de circuitos (derretimiento) ------------------------------------------
#
# Durante el derretimiento la pantalla deja la telemetria y pasa a ser el
# tablero de reles del refrigerante (coolant_routing.gd). Cada banco es una
# columna y cada canal una celda: se elige uno por columna y el caudal solo
# salta entre columnas vecinas si los canales estan pegados.

## Geometria del tablero, en pixeles de la pantalla (200x100).
const GX0 := 30
const GDX := 36
const GY0 := 32
const GDY := 23
const CELL := 13

func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(GX0 + col * GDX, GY0 + row * GDY)

## Celda bajo un punto de la pantalla, o [] si no hay ninguna.
func _cell_at(pos: Vector2) -> Array:
	for c in routing.COLS:
		for r in routing.ROWS:
			var k := _cell_center(c, r)
			if absf(pos.x - k.x) <= CELL * 0.5 + 2 and absf(pos.y - k.y) <= CELL * 0.5 + 2:
				return [c, r]
	return []

func on_screen_click(pos: Vector2) -> void:
	if not _routing_live():
		return
	var cell := _cell_at(pos)
	if not cell.is_empty():
		routing.select(cell[0], cell[1])

func on_screen_hover(pos: Vector2) -> void:
	_hover_cell = _cell_at(pos) if _routing_live() and pos.x >= 0.0 else []

func wants_pointer() -> bool:
	return not _hover_cell.is_empty()

func _routing_live() -> bool:
	return routing != null and routing.active and state == State.LIVE and not failed

func _draw_routing() -> void:
	var w := int(size.x)
	var ok: bool = routing.flow
	var col_ok := OK if ok else WARN
	panel_box(Rect2i(0, 0, w, int(size.y)), "COOLANT ROUTING", col_ok)

	# Entrada y salida.
	var first := _cell_center(0, routing.selected[0])
	var last := _cell_center(routing.COLS - 1, routing.selected[routing.COLS - 1])
	text("IN", Vector2i(6, int(first.y) - 3), DIM)
	text("OUT", Vector2i(w - 20, int(last.y) - 3), DIM)
	_pipe(Vector2(18, first.y), first, not routing.is_burned(0, routing.selected[0]))
	_pipe(last, Vector2(w - 22, last.y), not routing.is_burned(routing.COLS - 1, routing.selected[routing.COLS - 1]))

	# Tramos entre bancos: cortados si los canales no estan pegados.
	for c in routing.COLS - 1:
		var a := _cell_center(c, routing.selected[c])
		var b := _cell_center(c + 1, routing.selected[c + 1])
		_pipe(a, b, absi(routing.selected[c] - routing.selected[c + 1]) <= 1)

	# Celdas.
	for c in routing.COLS:
		for r in routing.ROWS:
			_draw_cell(c, r)

	# Estado abajo.
	var msg := "FLOW NOMINAL" if ok else "⚠ FLOW INTERRUPTED ⚠"
	var blink := ok or fmod(time, 0.7) < 0.45
	text_centered(msg, int(size.y) - 9, col_ok if blink else col_ok.darkened(0.5))

## Tramo de tuberia. Cortado = punteado rojo con un hueco en el medio.
func _pipe(a: Vector2, b: Vector2, joined: bool) -> void:
	if joined:
		draw_line(a.round(), b.round(), OK if routing.flow else COOL.darkened(0.3), 1.0)
		return
	var mid := (a + b) * 0.5
	var gap := (b - a).normalized() * 5.0
	draw_line(a.round(), (mid - gap).round(), WARN, 1.0)
	draw_line((mid + gap).round(), b.round(), WARN, 1.0)
	# Chispa en el corte.
	if fmod(time, 0.4) < 0.2:
		draw_rect(Rect2(mid.round() - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.9, 0.6))

func _draw_cell(c: int, r: int) -> void:
	var k := _cell_center(c, r)
	var box := Rect2i(int(k.x) - CELL / 2, int(k.y) - CELL / 2, CELL, CELL)
	var chosen: bool = routing.selected[c] == r
	var dead: bool = routing.is_burned(c, r)
	var hovered: bool = _hover_cell.size() == 2 and _hover_cell[0] == c and _hover_cell[1] == r

	if dead:
		frame(box, WARN.darkened(0.4))
		# Aspa: el canal se quemo.
		for i in CELL - 4:
			draw_rect(Rect2(box.position.x + 2 + i, box.position.y + 2 + i, 1, 1), WARN)
			draw_rect(Rect2(box.end.x - 3 - i, box.position.y + 2 + i, 1, 1), WARN)
		return
	if chosen:
		var fill := OK if routing.flow else WARN
		draw_rect(box, Color(fill, 0.25))
		frame(box, fill)
		draw_rect(Rect2(k.round() - Vector2(1, 1), Vector2(3, 3)), fill)
	else:
		frame(box, hover_color(hovered))
		if hovered:
			draw_rect(Rect2(k.round() - Vector2(1, 1), Vector2(3, 3)), VALUE)

func hover_color(hovered: bool) -> Color:
	return VALUE if hovered else DIM
