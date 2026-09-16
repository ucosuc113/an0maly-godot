extends Control

# Lo que se ve DENTRO de la pantalla del CRT. Vive en un SubViewport propio que
# crt_monitor.gd usa como textura del panel. Todo se dibuja en _draw con
# PixelFont, a 1 texel = 1 pixel de la escena.
#
# Fases: BOOT (comandos rapidos, < 2 s) -> MENU (boton) -> BLANK.

signal boot_finished

const PixelFont = preload("res://pixel_font.gd")

enum Phase { BLANK, BOOT, MENU }

const MARGIN := Vector2i(8, 8)
const LINE_H := 9
## Columnas por linea: los estados ("OK", "ARMED"...) se alinean a la derecha aqui.
const COLS := 27

## Color de fosforo. Ambar: combina con el disco caliente del agujero negro.
@export var phosphor: Color = Color(1.0, 0.66, 0.12)
@export var background: Color = Color(0.015, 0.008, 0.0)

var phase: Phase = Phase.BLANK
var hovered: bool = false:
	set(value):
		if hovered != value:
			hovered = value
			queue_redraw()
var pressed: bool = false:
	set(value):
		pressed = value
		queue_redraw()
## Rectangulo del boton en pixeles de pantalla (lo usa crt_monitor para el clic).
var button_rect: Rect2i

const BUTTON_TEXT := "INITIALIZE SYSTEMS"

# Cada linea es una lista de segmentos [texto, tono]. Tonos: 0 tenue, 1 normal,
# 2 brillante (los "OK").
var _lines: Array = []
var _time: float = 0.0
var _menu_time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	if phase == Phase.MENU:
		_menu_time += delta
	# Solo parpadeos y el barrido: redibujar cada frame es barato a 180x136.
	if phase != Phase.BLANK:
		queue_redraw()

# --- Secuencia de arranque ----------------------------------------------

func start_boot() -> void:
	phase = Phase.BOOT
	_lines.clear()
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

	for step in steps:
		if step[0] > 0.0:
			await get_tree().create_timer(step[0]).timeout
		_apply_step(step[1], step[2], step[3])
		queue_redraw()

	phase = Phase.BLANK
	queue_redraw()
	await get_tree().create_timer(0.12).timeout
	_menu_time = 0.0
	phase = Phase.MENU
	boot_finished.emit()

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
	phase = Phase.BLANK
	queue_redraw()

# --- Dibujo ---------------------------------------------------------------

func _tone(t: int) -> Color:
	match t:
		0:
			return phosphor.darkened(0.45)
		2:
			return phosphor.lerp(Color.WHITE, 0.45)
	return phosphor

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	match phase:
		Phase.BOOT:
			_draw_boot()
		Phase.MENU:
			_draw_menu()

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

func _draw_menu() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	var cx: int = w / 2

	# Barrido de encendido: la imagen se revela de arriba abajo.
	var reveal: float = clampf(_menu_time / 0.3, 0.0, 1.0)
	var reveal_y: float = reveal * h

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

	# Boton.
	var bw: int = PixelFont.text_width(BUTTON_TEXT) + 16
	var bh: int = 17
	button_rect = Rect2i(cx - bw / 2, 72, bw, bh)
	var r := Rect2(button_rect)
	var filled: bool = hovered or pressed
	if pressed:
		draw_rect(r, phosphor.lerp(Color.WHITE, 0.6))
	elif hovered:
		draw_rect(r, phosphor)
	else:
		# Marco de 1 px con esquinas recortadas: se lee mas fino que un rectangulo.
		var c := phosphor
		draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, 1), c)
		draw_rect(Rect2(r.position.x + 1, r.end.y - 1, r.size.x - 2, 1), c)
		draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), c)
		draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), c)
	var text_color: Color = background if filled else phosphor
	PixelFont.draw(self, BUTTON_TEXT,
			Vector2(r.position.x + 8, r.position.y + 5), text_color)

	# Flechas que "respiran" hacia el boton para invitar al clic.
	var nudge: int = 1 if fmod(_menu_time, 0.8) < 0.4 else 0
	if not filled:
		PixelFont.draw(self, "▶", Vector2(r.position.x - 9 + nudge, r.position.y + 5), _tone(0))
		PixelFont.draw(self, "◀", Vector2(r.end.x + 4 - nudge, r.position.y + 5), _tone(0))

	# Pie: estado con cursor parpadeante.
	var status := "STATUS: STANDBY"
	var stw: int = PixelFont.text_width(status)
	var sx: int = cx - (stw + 6) / 2
	PixelFont.draw(self, status, Vector2(sx, 110), _tone(0))
	if fmod(_menu_time, 1.0) < 0.5:
		draw_rect(Rect2(sx + stw + 2, 110, 5, 7), _tone(0))

	# Tapa lo aun no revelado, con una linea brillante en el frente del barrido.
	if reveal < 1.0:
		draw_rect(Rect2(0, reveal_y, w, h - reveal_y), background)
		draw_rect(Rect2(0, reveal_y, w, 1), phosphor.lerp(Color.WHITE, 0.5))
