extends Control

# Lo que se ve DENTRO de la pantalla del CRT. Vive en un SubViewport propio que
# crt_monitor.gd usa como textura del panel. Todo se dibuja en _draw con
# PixelFont, a 1 texel = 1 pixel de la escena.
#
# Paginas:
#   BOOT      comandos rapidos (arranque o carga de una pagina)
#   MENU      boton INITIALIZE SYSTEMS (primer encendido)
#   SETTINGS  ajustes del jugador (GameSettings) y boton BACK
#
# Las zonas clicables se registran al dibujar (_hits: id -> Rect2i). El monitor
# pasa el pixel del puntero a hover()/click()/wheel(); click() devuelve la
# accion que el monitor debe ejecutar ("initialize", "back"), "changed" si
# modifico un ajuste, o "".

signal page_ready
## Cada paso impreso durante una secuencia (para el sonido de tecleo).
## op: L/A/R/S (ver start_boot); text: lo que se imprimio.
signal step_printed(op: String, text: String)

const PixelFont = preload("res://scripts/pixel_font.gd")

enum Phase { BLANK, BOOT, MENU, SETTINGS }

## Tamano para el que esta maquetada la terminal. Si la pantalla es mas
## grande, crt_monitor.gd la centra.
const CONTENT_SIZE := Vector2i(180, 136)
const MARGIN := Vector2i(8, 8)
const LINE_H := 9
## Columnas por linea: los estados ("OK", "ARMED"...) se alinean a la derecha aqui.
const COLS := 27
const INITIALIZE_TEXT := "INITIALIZE SYSTEMS"
const BACK_TEXT := "◀ BACK"

## Filas de SETTINGS, en orden. kind: "toggle" (ON/OFF) o "level" (0..10).
const SETTING_ROWS := [
	{"id": "fullscreen", "label": "FULLSCREEN", "kind": "toggle"},
	{"id": "master_volume", "label": "MASTER VOLUME", "kind": "level"},
	{"id": "music_volume", "label": "MUSIC VOLUME", "kind": "level"},
	{"id": "sfx_volume", "label": "SFX VOLUME", "kind": "level"},
	{"id": "mute_unfocused", "label": "MUTE IN BACKGROUND", "kind": "toggle"},
	{"id": "reduce_flashing", "label": "REDUCE FLASHING", "kind": "toggle"},
	{"id": "bloom", "label": "BLOOM", "kind": "toggle"},
	{"id": "extra_lights", "label": "EXTRA LIGHTS", "kind": "toggle"},
]
const ROWS_Y := 25
const ROW_H := 10
const LABEL_X := 16
const BAR_X := 122
const SEG_W := 4
const SEG_GAP := 1

## Color de fosforo. Ambar: combina con el disco caliente del agujero negro.
@export var phosphor: Color = Color(1.0, 0.66, 0.12)
@export var background: Color = Color(0.015, 0.008, 0.0)

## Nodo con game_settings.gd (lo asigna crt_monitor.gd).
var settings: Node

var phase: Phase = Phase.BLANK
var hover_id: String = "":
	set(value):
		if hover_id != value:
			hover_id = value
			queue_redraw()
var pressed_id: String = "":
	set(value):
		pressed_id = value
		queue_redraw()

# Cada linea es una lista de segmentos [texto, tono]. Tonos: 0 tenue, 1 normal,
# 2 brillante (los "OK").
var _lines: Array = []
var _hits: Dictionary = {}
var _time: float = 0.0
var _page_time: float = 0.0
var _saved_flash: float = 0.0
## Se incrementa en cada secuencia nueva o en blank(): una secuencia vieja que
## despierta de un await ve que ya no es la actual y se detiene.
var _sequence: int = 0

func _process(delta: float) -> void:
	_time += delta
	_page_time += delta
	_saved_flash = maxf(_saved_flash - delta, 0.0)
	# Parpadeos y barridos: redibujar cada frame es barato a 180x136.
	if phase != Phase.BLANK:
		queue_redraw()

# --- Secuencias -----------------------------------------------------------

func start_boot() -> void:
	# [espera antes del paso, operacion, texto, tono]
	#   L = linea nueva, A = anadir a la ultima, R = reemplazar la ultima,
	#   S = rellenar con puntos y poner un estado alineado a la derecha
	var steps: Array = [
		[0.00, "L", "AN∅MALY BIOS V2.07", 2],
		[0.04, "L", "NULLPOINT SYSTEMS", 0],
		[0.06, "L", "", 1],
		[0.05, "L", "CPU 68030 25MHZ", 1],
		[0.07, "S", "OK", 2],
	]
	# Contador de memoria: la cifra corre en pocas actualizaciones.
	for kb in [512, 1024, 2048, 3072, 4096]:
		steps.append([0.025, "R" if kb != 512 else "L", "MEM %05dK" % kb, 1])
	steps.append([0.03, "S", "OK", 2])
	steps += [
		[0.08, "L", "> MOUNT /DEV/CORE0", 1],
		[0.07, "S", "OK", 2],
		[0.06, "L", "> LOAD SINGULARITY.SYS", 1],
	]
	# Barra de progreso de la carga.
	for i in range(0, 11, 2):
		var bar := "[" + "#".repeat(i) + ".".repeat(10 - i) + "] %3d%%" % (i * 10)
		steps.append([0.035, "L" if i == 0 else "R", "  " + bar, 0 if i < 10 else 2])
	steps += [
		[0.07, "L", "> CALIB LASER ARRAY", 1],
		[0.05, "L", "  L1", 1],
		[0.05, "A", " OK L2", 1],
		[0.05, "A", " OK L3", 1],
		[0.05, "A", " OK L4", 1],
		[0.05, "A", " OK", 2],
		[0.05, "L", "> SYNC PHASE LOCK", 1],
		[0.05, "S", "OK", 2],
		[0.04, "L", "> CONTAINMENT", 1],
		[0.06, "S", "ARMED", 2],
		[0.04, "L", "> GRAVITY WELL", 1],
		[0.06, "S", "STANDBY", 1],
		[0.10, "L", "", 1],
		[0.06, "L", "SYSTEM READY.", 2],
		[0.22, "L", "", 1],
	]
	if await _run_steps(steps):
		_open_page(Phase.MENU)

## Carga corta antes de mostrar los ajustes (mismo lenguaje que el arranque).
func start_settings() -> void:
	var steps: Array = [
		[0.00, "L", "> MOUNT /USR/CFG", 1],
		[0.06, "S", "OK", 2],
		[0.05, "L", "> READ USER.CFG", 1],
		[0.08, "S", "%d KEYS" % SETTING_ROWS.size(), 2],
		[0.05, "L", "> OPEN SETTINGS", 1],
		[0.16, "L", "", 1],
	]
	if await _run_steps(steps):
		_open_page(Phase.SETTINGS)

## Devuelve false si la secuencia se cancelo (blank() a mitad de camino).
func _run_steps(steps: Array) -> bool:
	_sequence += 1
	var my_sequence := _sequence
	phase = Phase.BOOT
	_lines.clear()
	_hits.clear()
	for step in steps:
		if step[0] > 0.0:
			await get_tree().create_timer(step[0]).timeout
			if my_sequence != _sequence:
				return false
		_apply_step(step[1], step[2], step[3])
		queue_redraw()
		step_printed.emit(step[1], step[2])
	phase = Phase.BLANK
	queue_redraw()
	await get_tree().create_timer(0.12).timeout
	return my_sequence == _sequence

func _open_page(page: Phase) -> void:
	_page_time = 0.0
	hover_id = ""
	pressed_id = ""
	phase = page
	page_ready.emit()

func _apply_step(op: String, text: String, tone: int) -> void:
	match op:
		"L":
			_lines.append([[text, tone]])
		"A":
			_lines[-1].append([text, tone])
		"R":
			_lines[-1] = [[text, tone]]
		"S":
			var used := 0
			for seg in _lines[-1]:
				used += seg[0].length()
			var dots: int = COLS - used - text.length() - 2
			_lines[-1].append([" " + ".".repeat(maxi(dots, 0)) + " ", 0])
			_lines[-1].append([text, tone])

func blank() -> void:
	# Cancela cualquier secuencia en curso.
	_sequence += 1
	phase = Phase.BLANK
	_hits.clear()
	hover_id = ""
	queue_redraw()

# --- Puntero --------------------------------------------------------------

## Solo cuenta lo ya revelado: no se puede clicar algo que aun no se ve.
func hit_test(px: Vector2i) -> String:
	if phase != Phase.MENU and phase != Phase.SETTINGS:
		return ""
	if _reveal() < 1.0:
		return ""
	for id in _hits:
		if (_hits[id] as Rect2i).has_point(px):
			return id
	return ""

func hover(px: Vector2i) -> String:
	hover_id = hit_test(px)
	return hover_id

func click(px: Vector2i) -> String:
	var id := hit_test(px)
	if id == "":
		return ""
	if id == "initialize" or id == "back":
		pressed_id = id
		return id
	var row := _row(id)
	if row.is_empty() or settings == null:
		return ""
	if row.kind == "toggle":
		settings.toggle(id)
	else:
		var bar := _bar_rect(_row_index(id))
		if not bar.grow(2).has_point(px):
			return ""
		var seg: int = clampi((px.x - bar.position.x) / (SEG_W + SEG_GAP), 0, 9)
		var value: int = seg + 1
		# Clicar el primer segmento cuando ya esta en 1 silencia (0).
		if value == 1 and int(settings.get_value(id)) == 1:
			value = 0
		settings.set_value(id, value)
	_saved_flash = 0.9
	return "changed"

## Rueda sobre una fila de volumen: +-1. Devuelve true si el valor cambio.
func wheel(px: Vector2i, direction: int) -> bool:
	var id := hit_test(px)
	var row := _row(id)
	if row.is_empty() or row.kind != "level" or settings == null:
		return false
	var before: int = settings.get_value(id)
	settings.set_value(id, before + direction)
	if int(settings.get_value(id)) == before:
		return false
	_saved_flash = 0.9
	return true

func _row(id: String) -> Dictionary:
	for r in SETTING_ROWS:
		if r.id == id:
			return r
	return {}

func _row_index(id: String) -> int:
	for i in SETTING_ROWS.size():
		if SETTING_ROWS[i].id == id:
			return i
	return -1

func _bar_rect(i: int) -> Rect2i:
	var w: int = 10 * (SEG_W + SEG_GAP) - SEG_GAP
	return Rect2i(BAR_X, ROWS_Y + i * ROW_H, w, PixelFont.GLYPH_H)

# --- Dibujo ---------------------------------------------------------------

func _tone(t: int) -> Color:
	match t:
		0:
			return phosphor.darkened(0.45)
		2:
			return phosphor.lerp(Color.WHITE, 0.45)
	return phosphor

## Barrido de aparicion de la pagina actual (0..1).
func _reveal() -> float:
	return clampf(_page_time / 0.3, 0.0, 1.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	match phase:
		Phase.BOOT:
			_draw_boot()
		Phase.MENU:
			_draw_menu()
			_draw_reveal_cover()
		Phase.SETTINGS:
			_draw_settings()
			_draw_reveal_cover()

func _draw_boot() -> void:
	var rows: int = (int(size.y) - MARGIN.y * 2) / LINE_H
	var first: int = maxi(0, _lines.size() - rows)
	var y: int = MARGIN.y
	var end_x: int = MARGIN.x
	for li in range(first, _lines.size()):
		var x: int = MARGIN.x
		for seg in _lines[li]:
			PixelFont.draw(self, seg[0], Vector2(x, y), _tone(seg[1]))
			x += seg[0].length() * PixelFont.advance()
		end_x = x
		y += LINE_H
	# Cursor de bloque parpadeando tras el ultimo caracter.
	if fmod(_time, 0.24) < 0.12 and not _lines.is_empty():
		draw_rect(Rect2(end_x, y - LINE_H, 5, 7), phosphor)

## Tapa lo aun no revelado, con una linea brillante en el frente del barrido.
func _draw_reveal_cover() -> void:
	var reveal := _reveal()
	if reveal >= 1.0:
		return
	var y: float = reveal * size.y
	draw_rect(Rect2(0, y, size.x, size.y - y), background)
	draw_rect(Rect2(0, y, size.x, 1), phosphor.lerp(Color.WHITE, 0.5))

## Boton de texto con marco de 1 px y esquinas recortadas; relleno al pasar
## el mouse o al pulsarlo. Registra su zona clicable.
func _draw_frame_button(id: String, text: String, center_x: int, y: int) -> Rect2i:
	var bw: int = PixelFont.text_width(text) + 16
	var r := Rect2i(center_x - bw / 2, y, bw, 17)
	_hits[id] = r.grow(2)
	var rf := Rect2(r)
	var filled := hover_id == id or pressed_id == id
	if pressed_id == id:
		draw_rect(rf, phosphor.lerp(Color.WHITE, 0.6))
	elif hover_id == id:
		draw_rect(rf, phosphor)
	else:
		draw_rect(Rect2(rf.position.x + 1, rf.position.y, rf.size.x - 2, 1), phosphor)
		draw_rect(Rect2(rf.position.x + 1, rf.end.y - 1, rf.size.x - 2, 1), phosphor)
		draw_rect(Rect2(rf.position.x, rf.position.y + 1, 1, rf.size.y - 2), phosphor)
		draw_rect(Rect2(rf.end.x - 1, rf.position.y + 1, 1, rf.size.y - 2), phosphor)
	PixelFont.draw(self, text, Vector2(r.position.x + 8, r.position.y + 5),
			background if filled else phosphor)
	return r

func _draw_menu() -> void:
	var w: int = int(size.x)
	var cx: int = w / 2

	# Titulo grande con tracking, y el subtitulo tenue.
	var title := "AN∅MALY"
	var tw: int = PixelFont.text_width(title, 2, 1)
	PixelFont.draw(self, title, Vector2(cx - tw / 2, 24), phosphor, 2, 1)

	var sub := "CORE CONTROL UNIT"
	var sw: int = PixelFont.text_width(sub)
	PixelFont.draw(self, sub, Vector2(cx - sw / 2, 46), _tone(0))

	# Filete fino con un hueco central, a modo de separador.
	var line_y: int = 58
	draw_rect(Rect2(cx - 44, line_y, 40, 1), _tone(0))
	draw_rect(Rect2(cx + 4, line_y, 40, 1), _tone(0))
	draw_rect(Rect2(cx - 1, line_y - 1, 2, 3), phosphor)

	var r := _draw_frame_button("initialize", INITIALIZE_TEXT, cx, 72)

	# Flechas que "respiran" hacia el boton para invitar al clic.
	var nudge: int = 1 if fmod(_page_time, 0.8) < 0.4 else 0
	if hover_id != "initialize" and pressed_id != "initialize":
		PixelFont.draw(self, "▶", Vector2(r.position.x - 9 + nudge, r.position.y + 5), _tone(0))
		PixelFont.draw(self, "◀", Vector2(r.end.x + 4 - nudge, r.position.y + 5), _tone(0))

	# Pie: estado con cursor parpadeante.
	var status := "STATUS: STANDBY"
	var stw: int = PixelFont.text_width(status)
	var sx: int = cx - (stw + 6) / 2
	PixelFont.draw(self, status, Vector2(sx, 110), _tone(0))
	if fmod(_page_time, 1.0) < 0.5:
		draw_rect(Rect2(sx + stw + 2, 110, 5, 7), _tone(0))

func _draw_settings() -> void:
	var w: int = int(size.x)
	var right: int = w - MARGIN.x

	# Cabecera: titulo a la izquierda, archivo (o "SAVED") a la derecha.
	PixelFont.draw(self, "SYSTEM SETTINGS", Vector2(MARGIN.x, MARGIN.y), _tone(2))
	var tag := "SAVED" if _saved_flash > 0.0 else "USER.CFG"
	var tag_color := phosphor if _saved_flash > 0.0 else _tone(0)
	PixelFont.draw(self, tag, Vector2(right - PixelFont.text_width(tag), MARGIN.y), tag_color)
	_draw_dotted_line(19, MARGIN.x, right)

	for i in SETTING_ROWS.size():
		_draw_setting_row(i, right)

	_draw_dotted_line(106, MARGIN.x, right)
	_draw_frame_button("back", BACK_TEXT, w / 2, 112)

func _draw_setting_row(i: int, right: int) -> void:
	var row: Dictionary = SETTING_ROWS[i]
	var y: int = ROWS_Y + i * ROW_H
	var hot: bool = hover_id == row.id
	var band := Rect2i(MARGIN.x - 3, y - 2, right - MARGIN.x + 6, ROW_H)
	_hits[row.id] = band

	if hot:
		# Franja tenue detras de la fila y cursor a la izquierda.
		draw_rect(Rect2(band), phosphor.darkened(0.82))
		PixelFont.draw(self, "▶", Vector2(MARGIN.x - 1, y), phosphor)
	PixelFont.draw(self, row.label, Vector2(LABEL_X, y), phosphor if hot else _tone(1).darkened(0.12))

	var value: Variant = settings.get_value(row.id) if settings else null
	if row.kind == "toggle":
		_draw_toggle(bool(value), y, right)
	else:
		_draw_level(int(value) if value != null else 0, i, y)

## "ON  OFF": la opcion activa va rellena (texto oscuro sobre fosforo).
func _draw_toggle(on: bool, y: int, right: int) -> void:
	var off_x: int = right - PixelFont.text_width("OFF") - 1
	var on_x: int = off_x - 8 - PixelFont.text_width("ON")
	for opt in [["ON", on_x, on], ["OFF", off_x, not on]]:
		var tw: int = PixelFont.text_width(opt[0])
		if opt[2]:
			# 1 px de aire arriba y abajo: dos filas seguidas no se tocan.
			draw_rect(Rect2(opt[1] - 2, y - 1, tw + 4, PixelFont.GLYPH_H + 2), phosphor)
			PixelFont.draw(self, opt[0], Vector2(opt[1], y), background)
		else:
			PixelFont.draw(self, opt[0], Vector2(opt[1], y), _tone(0))

## Barra de 10 segmentos con el porcentaje a la izquierda.
func _draw_level(level: int, i: int, y: int) -> void:
	var bar := _bar_rect(i)
	for s in 10:
		var r := Rect2(bar.position.x + s * (SEG_W + SEG_GAP), y, SEG_W, PixelFont.GLYPH_H)
		draw_rect(r, phosphor if s < level else phosphor.darkened(0.78))
	var pct := "%d%%" % (level * 10)
	PixelFont.draw(self, pct, Vector2(bar.position.x - 3 - PixelFont.text_width(pct), y),
		_tone(0) if level > 0 else _tone(0).darkened(0.4))

func _draw_dotted_line(y: int, x0: int, x1: int) -> void:
	var c := _tone(0)
	for x in range(x0, x1, 2):
		draw_rect(Rect2(x, y, 1, 1), c)
