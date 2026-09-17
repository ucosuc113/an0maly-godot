extends "res://scripts/monitor_screen.gd"

# Monitor izquierdo (200x100): potencia de los lasers y escudo.
#
#   LATERAL / DIAG   objetivo (lo que pide la palanca) y potencia real
#   SHIELD           densidad e integridad (fase 2)
#   COOLANT          refrigeracion del escudo (fase 2)
#   grafica          historial: lateral, diagonal, temperatura, refrigeracion

func _draw_live() -> void:
	var w := int(size.x)
	var box_w := w / 4
	_draw_power(Rect2i(0, 0, box_w, 34), "LATERAL", sim.lat_goal, sim.lat_power, LATERAL)
	_draw_power(Rect2i(box_w, 0, box_w, 34), "DIAG", sim.dia_goal, sim.dia_power, DIAGONAL)
	_draw_shield(Rect2i(box_w * 2, 0, box_w, 34))
	_draw_coolant(Rect2i(box_w * 3, 0, w - box_w * 3, 34))
	_draw_chart(Rect2i(0, 35, w, int(size.y) - 35))

func _draw_power(r: Rect2i, title: String, goal: float, power: float, col: Color) -> void:
	var inner := panel_box(r, title)
	if not sim.lasers_online:
		no_signal(inner)
		return
	row("GOAL", "%d" % int(goal), inner.position.x, inner.position.y, inner.size.x)
	# La potencia real cambia de color mientras persigue al objetivo.
	var chasing := absf(goal - power) > 1.0
	row("PWR", "%d" % int(power), inner.position.x, inner.position.y + 9, inner.size.x,
		ACCENT if chasing and fmod(time, 0.5) < 0.3 else col)

func _draw_shield(r: Rect2i) -> void:
	var inner := panel_box(r, "SHIELD")
	if not sim.shield_online:
		no_signal(inner)
		return
	row("DENS", "%.0f%%" % sim.shield_density, inner.position.x, inner.position.y, inner.size.x, COOL)
	var integ_col := WARN if sim.shield_integrity < 70.0 else VALUE
	row("INTG", "%.0f%%" % sim.shield_integrity, inner.position.x, inner.position.y + 9, inner.size.x, integ_col)

func _draw_coolant(r: Rect2i) -> void:
	var inner := panel_box(r, "COOLANT")
	if not sim.shield_online:
		no_signal(inner)
		return
	row("ENG", "%.0f%%" % sim.coolant, inner.position.x, inner.position.y, inner.size.x, COOL)
	# Barra de enganche.
	var bw := inner.size.x
	frame(Rect2i(inner.position.x, inner.position.y + 11, bw, 5), FRAME)
	draw_rect(Rect2(inner.position.x + 1, inner.position.y + 12,
		int((bw - 2) * sim.coolant / 100.0), 3), COOL)

func _draw_chart(r: Rect2i) -> void:
	frame(r, FRAME)
	var plot := Rect2i(r.position.x + 2, r.position.y + 10, r.size.x - 4, r.size.y - 12)
	# Leyenda.
	var lx := r.position.x + 3
	for item in [["LAT", LATERAL], ["DIA", DIAGONAL], ["TMP", HOT], ["CL", COOL]]:
		text(item[0], Vector2i(lx, r.position.y + 2), item[1])
		lx += text_width(item[0]) + 5
	text_right("HISTORY", r.end.x - 3, r.position.y + 2, TITLE)
	# Rejilla.
	for i in range(1, 4):
		var gy := plot.position.y + plot.size.y * i / 4
		for gx in range(plot.position.x, plot.end.x, 3):
			draw_rect(Rect2(gx, gy, 1, 1), Color(DIM, 0.35))
	if not sim.lasers_online:
		no_signal(plot)
		return
	var hist: Array = sim.history
	if hist.size() < 2:
		return
	var colors := [LATERAL, DIAGONAL, HOT, COOL]
	var n: int = sim.HISTORY_SIZE
	for k in 4:
		var pts := PackedVector2Array()
		for i in hist.size():
			var x := plot.end.x - 1 - (hist.size() - 1 - i) * float(plot.size.x - 1) / (n - 1)
			var v: float = clampf(hist[i][k], 0.0, 1.0)
			var y := plot.end.y - 1 - v * (plot.size.y - 1)
			pts.append(Vector2(x, y).round())
		draw_polyline(pts, colors[k])
