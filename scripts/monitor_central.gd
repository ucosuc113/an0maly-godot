extends "res://scripts/monitor_screen.gd"

# Monitor central (240x146): estado del reactor.
#
#   encabezado   estado general (con avisos que parpadean)
#   STRUCTURE    esquema de la camara vista de frente: 3 lasers laterales
#                (azul), 4 diagonales (morado), escudo (fase 2) y
#                singularidad con su disco (fase 3); barras de potencia a los
#                lados.
#   ACC. DISC / SHIELD / LASERS       columna del medio
#   CORE / OUTPUT / SEQUENCE          columna derecha
#
# Lo que todavia no existe muestra NO SIGNAL.

## Lasers (laser_emitter.gd), en el orden de la escena: el primero lateral es
## el del fondo, los otros dos los de las paredes.
var lateral_lasers: Array = []
var diagonal_lasers: Array = []
## control_panel.gd (estado de las fases).
var panel: Node

func _draw_live() -> void:
	_draw_header()
	_draw_structure(Rect2i(0, 14, 104, 132))
	_draw_middle(106)
	_draw_right(174)

func _draw_header() -> void:
	var r := Rect2i(0, 0, int(size.x), 13)
	var alarm: int = sim.alarm()
	var col := TITLE
	var t := String(sim.status)
	if alarm > 0:
		col = WARN if alarm == 2 or fmod(time, 0.8) < 0.55 else WARN.darkened(0.5)
		t = "⚠ " + t + " ⚠"
	elif sim.shield_forming:
		col = COOL if fmod(time, 0.8) < 0.55 else COOL.darkened(0.4)
	elif sim.lasers_online:
		col = OK
	frame(r, col if alarm > 0 else FRAME)
	text_centered(t, 3, col)

# --- Esquema ------------------------------------------------------------------

func _draw_structure(r: Rect2i) -> void:
	var inner := panel_box(r, "STRUCTURE")
	var c := Vector2i(inner.position.x + inner.size.x / 2, inner.position.y + inner.size.y / 2 + 4)

	# Barras de potencia: lateral a la izquierda, diagonal a la derecha.
	_power_bar(Rect2i(inner.position.x, inner.position.y + 14, 4, inner.size.y - 16),
		sim.lat_power / 900.0, LATERAL)
	_power_bar(Rect2i(inner.end.x - 4, inner.position.y + 14, 4, inner.size.y - 16),
		sim.dia_power / 700.0, DIAGONAL)

	# Escudo (fase 2).
	if sim.shield_online:
		var dens: float = sim.shield_density / 100.0
		var sc := COOL.lerp(WARN, 1.0 - sim.shield_integrity / 100.0)
		sc.a = 0.35 + 0.65 * dens * (0.85 + 0.15 * sin(time * 4.0))
		_ellipse(c, Vector2(36, 24), sc)
		if dens > 0.6:
			_ellipse(c, Vector2(35, 23), Color(sc, sc.a * 0.5))
	else:
		_ellipse_dashed(c, Vector2(36, 24), Color(DIM, 0.35))

	# Singularidad y disco (fase 3).
	if sim.singularity_online:
		var tilt := 0.28
		_ellipse(c, Vector2(24, 24 * tilt), Color(0.75, 0.8, 1.0))
		_ellipse(c, Vector2(18, 18 * tilt), Color(0.6, 0.65, 0.9))
		draw_rect(Rect2(c.x - 2, c.y - 2, 5, 5), BG)
		frame(Rect2i(c.x - 3, c.y - 3, 7, 7), VALUE)
	else:
		# Punto de convergencia vacio: una mira.
		draw_rect(Rect2(c.x - 3, c.y, 7, 1), DIM)
		draw_rect(Rect2(c.x, c.y - 3, 1, 7), DIM)

	# Lasers laterales: fondo (arriba, visto de punta) e izquierda / derecha.
	if lateral_lasers.size() >= 3:
		_laser_end(Vector2i(c.x, c.y - 30), lateral_lasers[0])
		_laser_bar(Vector2i(inner.position.x + 27, c.y), Vector2i(1, 0), lateral_lasers[1])
		_laser_bar(Vector2i(inner.end.x - 28, c.y), Vector2i(-1, 0), lateral_lasers[2])
	# Diagonales: desde las esquinas hacia el centro.
	var corners := [
		Vector2i(inner.end.x - 12, inner.position.y + 14),
		Vector2i(inner.position.x + 11, inner.position.y + 14),
		Vector2i(inner.end.x - 12, inner.end.y - 4),
		Vector2i(inner.position.x + 11, inner.end.y - 4),
	]
	for i in mini(diagonal_lasers.size(), 4):
		var from: Vector2i = corners[i]
		var dir := Vector2(c - from).normalized()
		_laser_diag(from, dir, diagonal_lasers[i])

	# Haces hacia el centro cuando la singularidad existe.
	if sim.singularity_online and fmod(time * 6.0, 1.0) < 0.7:
		for i in mini(diagonal_lasers.size(), 4):
			var from: Vector2i = corners[i]
			var to := Vector2(from).lerp(Vector2(c), 0.85)
			draw_line(Vector2(from) + Vector2(c - from).normalized() * 14.0, to, Color(DIAGONAL, 0.5))

func _laser_color(laser: Node, base: Color) -> Color:
	match laser.stage:
		&"online":
			return base
		&"ready":
			return VALUE
		&"rising":
			return ACCENT if fmod(time, 0.4) < 0.25 else ACCENT.darkened(0.5)
	return Color(DIM, 0.5)

func _laser_bar(tip: Vector2i, dir: Vector2i, laser: Node) -> void:
	var col := _laser_color(laser, LATERAL)
	var length := 18
	var start := tip - dir * length
	var r := Rect2i(Vector2i(mini(start.x, tip.x), tip.y - 2), Vector2i(length, 5))
	if laser.stage == &"online":
		draw_rect(r, Color(col, 0.35))
	frame(r, col)
	# Recamara (bola) encendida.
	if laser.stage == &"online":
		draw_rect(Rect2(start.x + dir.x * 5 - 1, tip.y - 1, 3, 3), col.lightened(0.4))

func _laser_end(center: Vector2i, laser: Node) -> void:
	var col := _laser_color(laser, LATERAL)
	frame(Rect2i(center.x - 4, center.y - 4, 9, 9), col)
	if laser.stage == &"online":
		draw_rect(Rect2(center.x - 2, center.y - 2, 5, 5), Color(col, 0.6))
		draw_rect(Rect2(center.x, center.y, 1, 1), col.lightened(0.5))

func _laser_diag(from: Vector2i, dir: Vector2, laser: Node) -> void:
	var col := _laser_color(laser, DIAGONAL)
	var a := Vector2(from)
	var b := a + dir * 12.0
	var n := Vector2(-dir.y, dir.x)
	draw_line(a + n, b + n, col)
	draw_line(a - n, b - n, col)
	draw_line(a + n, a - n, col)
	draw_line(b + n, b - n, col)
	if laser.stage == &"online":
		draw_line(a, b, Color(col, 0.6))

func _power_bar(r: Rect2i, value: float, col: Color) -> void:
	var segs := 12
	var seg_h := r.size.y / segs
	var lit := int(round(clampf(value, 0.0, 1.0) * segs))
	for i in segs:
		var y := r.end.y - (i + 1) * seg_h
		var c := col if i < lit else Color(DIM, 0.25)
		draw_rect(Rect2(r.position.x, y, r.size.x, seg_h - 1), c)

func _ellipse(c: Vector2i, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(Vector2(c) + Vector2(cos(a) * radius.x, sin(a) * radius.y).round())
	draw_polyline(pts, col)

func _ellipse_dashed(c: Vector2i, radius: Vector2, col: Color) -> void:
	for i in 24:
		var a := TAU * i / 24.0
		var p := Vector2(c) + Vector2(cos(a) * radius.x, sin(a) * radius.y).round()
		draw_rect(Rect2(p, Vector2.ONE), col)

# --- Columnas de datos --------------------------------------------------------------

func _draw_middle(x: int) -> void:
	var w := 66
	var disc := panel_box(Rect2i(x, 14, w, 42), "ACC. DISC")
	if sim.singularity_online:
		row("SAT", "%.1f%%" % sim.disc_saturation, disc.position.x, disc.position.y, disc.size.x)
		row("TEMP", short(sim.disc_temp), disc.position.x, disc.position.y + 9, disc.size.x)
		row("SPIN", short(sim.disc_spin), disc.position.x, disc.position.y + 18, disc.size.x)
	else:
		no_signal(disc)

	var shield := panel_box(Rect2i(x, 58, w, 33), "SHIELD")
	if sim.shield_online:
		var stress_col := WARN if sim.shield_stress > 100.0 else VALUE
		row("STRS", "%.0f%%" % sim.shield_stress, shield.position.x, shield.position.y, shield.size.x, stress_col)
		var integ_col := WARN if sim.shield_integrity < 70.0 else VALUE
		row("INTG", "%.1f%%" % sim.shield_integrity, shield.position.x, shield.position.y + 9, shield.size.x, integ_col)
	else:
		no_signal(shield)

	var lasers := panel_box(Rect2i(x, 93, w, 53), "LASERS")
	if sim.lasers_online:
		row("LAT", "%d" % int(sim.lat_power), lasers.position.x, lasers.position.y, lasers.size.x, LATERAL)
		row("DIA", "%d" % int(sim.dia_power), lasers.position.x, lasers.position.y + 9, lasers.size.x, DIAGONAL)
		var temp_col := WARN if sim.temp > 9000.0 else (ACCENT if sim.temp > 5000.0 else VALUE)
		row("TEMP", short(sim.temp), lasers.position.x, lasers.position.y + 18, lasers.size.x, temp_col)
		row("INJ", "%.1f" % sim.injection, lasers.position.x, lasers.position.y + 27, lasers.size.x)
	else:
		no_signal(lasers)

func _draw_right(x: int) -> void:
	var w := int(size.x) - x
	var core := panel_box(Rect2i(x, 14, w, 59), "CORE")
	if sim.singularity_online:
		var flux_ok: bool = sim.core_flux < 1e6
		row("FLUX", short(sim.core_flux) if flux_ok else "NAN", core.position.x, core.position.y, core.size.x,
			VALUE if flux_ok else WARN)
		row("MASS", short(sim.core_mass * 1e6) + "T", core.position.x, core.position.y + 9, core.size.x)
		row("SPIN", short(sim.core_spin), core.position.x, core.position.y + 18, core.size.x)
		row("CHRG", "%.0fC" % sim.core_charge, core.position.x, core.position.y + 27, core.size.x)
		var mis_col := WARN if sim.core_misalign > 400.0 else VALUE
		row("ALGN", "%.0fU" % sim.core_misalign, core.position.x, core.position.y + 36, core.size.x, mis_col)
	else:
		no_signal(core)

	var out := panel_box(Rect2i(x, 75, w, 24), "OUTPUT")
	if sim.lasers_online:
		# MW -> W, con sufijo: 3.9e6 MW = "3.9TW".
		row("GEN", short(sim.generation * 1e6) + "W", out.position.x, out.position.y, out.size.x)
	else:
		no_signal(out)

	var seq := panel_box(Rect2i(x, 101, w, 45), "SEQUENCE")
	if panel:
		for i in 3:
			var idx := i + 1
			var state: String = panel.button_state(idx)
			var col := DIM
			var tag := "LOCK"
			match state:
				"done":
					col = OK
					tag = "DONE"
				"running":
					col = ACCENT if fmod(time, 0.4) < 0.25 else VALUE
					tag = "RUN"
				"ready":
					col = VALUE
					tag = "READY"
			row("%02d" % idx, tag, seq.position.x, seq.position.y + i * 9, seq.size.x, col)
