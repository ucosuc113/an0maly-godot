extends "res://scripts/monitor_screen.gd"

# Monitor derecho (200x100): refrigeracion e inyeccion.
#
#   COOLANT FANS    velocidad real (grande), objetivo, ventilador que gira a la
#                   velocidad real
#   PLASMA INJECT   tasa de inyeccion (grande) y el electron en orbita: mas
#                   rapido con mas energia, y la orbita tiembla y se deforma
#                   con la inestabilidad

var _fan_angle: float = 0.0
var _orbit_angle: float = 0.0
var _last_time: float = 0.0

func _draw_live() -> void:
	var dt := time - _last_time
	_last_time = time
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
