extends "res://scripts/monitor_screen.gd"

# Las tres pantallas de la sala de apagado de emergencia. Van con el mismo
# script y cambia `mode`, porque son tres lecturas del mismo subsistema:
#
#   COOLANT    (derecha)  integridad de la refrigeracion: caudal, ruta,
#                         ventiladores, escudo, y si las reservas se vaciaron
#   THERMAL    (izquierda) el detalle critico del nucleo, con la barra que va
#                         de verde a rojo
#   ENVELOPE   (arriba)   la barra completa, acostada (la pantalla de arriba
#                         es ancha y baja): una marca blanca dice donde esta el
#                         nucleo ahora y dos franjas grises en que rango sirve
#                         cada boton. Fuera de esos rangos, no se puede.

enum Mode { COOLANT, THERMAL, ENVELOPE }

## Techo de la escala termica (K). El derretimiento llega bastante mas arriba,
## pero de ahi para adelante ya no hay decision que tomar.
const SCALE_TOP := 30000.0

@export var mode: Mode = Mode.COOLANT

## crisis_director.gd (umbrales) y emergency_room.gd (estado de la sala). Los
## pasa screen_panel.gd.
var crisis: Node
var room: Node

func _draw_live() -> void:
	match mode:
		Mode.COOLANT:
			_draw_coolant()
		Mode.THERMAL:
			_draw_thermal()
		Mode.ENVELOPE:
			_draw_envelope()

# --- Derecha: refrigeracion ---------------------------------------------------------

func _draw_coolant() -> void:
	var w := int(size.x)
	var h := int(size.y)
	var purged: bool = sim.purged
	var inner := panel_box(Rect2i(0, 0, w, h), "COOLANT INTEGRITY",
		WARN if purged else FRAME)
	var y := inner.position.y + 2
	var col := inner.size.x

	# Caudal: lo que de verdad llega al escudo.
	var flow := clampf(sim.coolant / 100.0, 0.0, 1.0)
	text("FLOW", Vector2i(inner.position.x, y), DIM)
	text_right("%d%%" % int(flow * 100.0), inner.end.x, y,
		WARN if flow < 0.35 else VALUE)
	y += 9
	_meter(Rect2i(inner.position.x, y, col, 5), flow, COOL if not purged else WARN)
	y += 10

	row("FANS", "%d RPM" % int(sim.fan_rpm), inner.position.x, y, col,
		WARN if sim.fan_rpm < 100.0 else VALUE)
	y += 9
	row("ROUTE", "OK" if sim.route > 0.5 else "CUT", inner.position.x, y, col,
		OK if sim.route > 0.5 else WARN)
	y += 9
	var integ: float = sim.shield_integrity
	row("SHIELD", "%d%%" % int(integ), inner.position.x, y, col,
		WARN if integ < 70.0 else VALUE)
	y += 11

	# Lo unico que importa de verdad: si quedan reservas.
	var tag := "RESERVES EMPTY" if purged else "RESERVES NOMINAL"
	var tag_col: Color = WARN if purged else OK
	var on := not purged or fmod(time, 0.8) < 0.55
	frame(Rect2i(inner.position.x, y, col, 12), tag_col if on else tag_col.darkened(0.5))
	var tw := text_width(tag)
	text(tag, Vector2i(inner.position.x + (col - tw) / 2, y + 3),
		tag_col if on else tag_col.darkened(0.4))

# --- Izquierda: nucleo --------------------------------------------------------------

func _draw_thermal() -> void:
	var w := int(size.x)
	var h := int(size.y)
	var t: float = sim.temp
	var inner := panel_box(Rect2i(0, 0, w, h), "CORE THERMAL", _heat_color(t))
	var y := inner.position.y + 2
	var col := inner.size.x

	text("CORE", Vector2i(inner.position.x, y), DIM)
	text(_temp_text(t), Vector2i(inner.position.x, y + 9), _heat_color(t), 2)
	text("K", Vector2i(inner.position.x + text_width(_temp_text(t), 2) + 3,
		y + 18), DIM)
	y += 28

	# La barra de verde a rojo: el color ES el dato.
	_gradient_bar(Rect2i(inner.position.x, y, col, 7), _fraction(t))
	y += 12

	row("DISC", short(sim.disc_temp), inner.position.x, y, col)
	y += 9
	row("MASS", "%.2f" % sim.core_mass, inner.position.x, y, col)
	y += 9
	var inst: float = sim.instability
	row("INSTAB", "%d%%" % int(inst * 100.0), inner.position.x, y, col,
		WARN if inst > 0.5 else VALUE)
	y += 9
	var st := String(sim.status)
	var sc: Color = WARN if sim.alarm() > 0 else (COOL if t < 900.0 else VALUE)
	var stw := text_width(st)
	text(st, Vector2i(inner.position.x + (col - stw) / 2, y + 2), sc)

# --- Arriba: la envolvente ----------------------------------------------------------

func _draw_envelope() -> void:
	var w := int(size.x)
	var h := int(size.y)
	var t: float = sim.temp
	frame(Rect2i(0, 0, w, h), _heat_color(t))
	text("THERMAL ENVELOPE", Vector2i(4, 2), TITLE)
	var label := _temp_text(t) + " K"
	text_right(label, w - 4, 2, _heat_color(t))

	# La barra va acostada porque la pantalla es ancha y baja: frio a la
	# izquierda, critico a la derecha.
	var bar := Rect2i(4, 12, w - 8, maxi(h - 26, 6))
	for i in bar.size.x:
		var f := float(i) / maxf(bar.size.x - 1, 1)
		draw_rect(Rect2(bar.position.x + i, bar.position.y, 1, bar.size.y),
			_ramp(f).darkened(0.6))
	frame(bar, FRAME)

	# Los dos rangos, uno arriba y otro abajo del mismo carril: asi se leen
	# aunque se superpongan.
	if crisis:
		_band(bar, crisis.purge_unlock_temp, crisis.purge_safe_temp, "CRYO", 0)
		_band(bar, 0.0, crisis.shutdown_max_temp, "SHUTDN", 1)

	# Donde esta el nucleo ahora.
	var x := bar.position.x + int(round(_norm(t) * (bar.size.x - 1)))
	draw_rect(Rect2(x - 1, bar.position.y - 3, 2, bar.size.y + 6), Color.WHITE)
	draw_rect(Rect2(x - 3, bar.position.y - 5, 6, 2), Color.WHITE)

	# Escala.
	# Los numeros van a mano: short() usa 1e4 como "K" (30000 -> "3.0K"), que
	# sirve para leer tendencias pero aca confunde, porque estos son los
	# umbrales exactos con los que el jugador decide.
	for step in [0.0, 0.5, 1.0]:
		var sx := bar.position.x + int(round(step * (bar.size.x - 1)))
		var v := "%dK" % int(step * SCALE_TOP / 1000.0)
		var tw := text_width(v)
		var tx := clampi(sx - tw / 2, 1, w - tw - 1)
		text(v, Vector2i(tx, bar.end.y + 2), DIM)

## Franja de "aqui este boton sirve", acostada sobre el carril. `slot` 0 va
## pegada al borde de arriba y 1 al de abajo, para que dos rangos superpuestos
## se sigan distinguiendo.
func _band(bar: Rect2i, low: float, high: float, label: String, slot: int) -> void:
	var x0 := bar.position.x + int(round(_norm(low) * (bar.size.x - 1)))
	var x1 := bar.position.x + int(round(_norm(high) * (bar.size.x - 1)))
	var y := bar.position.y + 1 if slot == 0 else bar.end.y - 4
	var wide := maxi(x1 - x0, 2)
	draw_rect(Rect2(x0, y, wide, 3), Color(0.8, 0.8, 0.83, 0.5))
	draw_rect(Rect2(x0, y, 1, 3), Color(0.9, 0.9, 0.93))
	draw_rect(Rect2(x1 - 1, y, 1, 3), Color(0.9, 0.9, 0.93))
	var tw := text_width(label)
	if wide > tw + 4:
		text(label, Vector2i(x0 + (wide - tw) / 2, y - 2), Color(0.9, 0.9, 0.93))

# --- Ayudas -------------------------------------------------------------------------

func _fraction(t: float) -> float:
	return _norm(t)

func _norm(t: float) -> float:
	return clampf(t / SCALE_TOP, 0.0, 1.0)

## Verde (frio) -> amarillo -> rojo (critico).
func _ramp(f: float) -> Color:
	if f < 0.5:
		return OK.lerp(ACCENT, f * 2.0)
	return ACCENT.lerp(WARN, (f - 0.5) * 2.0)

func _heat_color(t: float) -> Color:
	if t < 120.0:
		return COOL
	return _ramp(_norm(t))

func _gradient_bar(r: Rect2i, f: float) -> void:
	var fill := int(round(r.size.x * clampf(f, 0.0, 1.0)))
	for i in r.size.x:
		var col := _ramp(float(i) / maxf(r.size.x - 1, 1))
		draw_rect(Rect2(r.position.x + i, r.position.y, 1, r.size.y),
			col if i < fill else col.darkened(0.72))
	frame(r, FRAME)

func _meter(r: Rect2i, f: float, col: Color) -> void:
	draw_rect(r, Color(col, 0.18))
	draw_rect(Rect2(r.position.x, r.position.y,
		int(round(r.size.x * clampf(f, 0.0, 1.0))), r.size.y), col)
	frame(r, FRAME)

func _temp_text(t: float) -> String:
	return "%.1f" % t if t < 100.0 else short(t)
