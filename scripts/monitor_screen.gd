extends Control

# Base de las pantallas de telemetria. Se dibuja dentro de un SubViewport del
# tamano de la pantalla (info_monitor.gd), en la fuente pixel del juego.
#
#   OFF   negro
#   BOOT  arranque: nombre del monitor, enlace con puntos y "OK"
#   LIVE  el contenido de cada monitor (_draw_live, en los hijos)
#
# Estilo (como las referencias): fondo negro, paneles con marco lila, titulos
# chicos, valores en blanco; los paneles sin datos muestran NO SIGNAL con
# ruido.

const PixelFont = preload("res://scripts/pixel_font.gd")

enum State { OFF, BOOT, LIVE }

const BG := Color(0.0, 0.0, 0.0)
const FRAME := Color(0.55, 0.5, 0.85)
const TITLE := Color(0.72, 0.68, 0.95)
const VALUE := Color(0.96, 0.95, 0.92)
const DIM := Color(0.42, 0.42, 0.48)
const ACCENT := Color(1.0, 0.52, 0.14)
const WARN := Color(1.0, 0.25, 0.2)
const OK := Color(0.45, 1.0, 0.55)
const LATERAL := Color(0.35, 0.68, 1.0)
const DIAGONAL := Color(0.78, 0.45, 1.0)
const HOT := Color(1.0, 0.3, 0.25)
const COOL := Color(0.35, 0.95, 1.0)

## Nombre que se muestra al arrancar.
@export var boot_title: String = "TELEMETRY"

var sim: Node
var state: State = State.OFF
var time: float = 0.0
var _boot_t: float = 0.0
var _redraw_t: float = 0.0
var _glitch: float = 0.0
## Sin datos: solo ERROR (el nucleo paso el punto de no retorno).
var failed: bool = false

func fail() -> void:
	failed = true
	glitch(1.0)

## Interferencia (onda expansiva): franjas corridas y ruido que se apagan.
func glitch(amount: float = 1.0) -> void:
	_glitch = maxf(_glitch, amount)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func power_on() -> void:
	state = State.BOOT
	_boot_t = 0.0
	queue_redraw()

func power_off() -> void:
	state = State.OFF
	queue_redraw()

func _process(delta: float) -> void:
	if state == State.OFF:
		return
	time += delta
	if _glitch > 0.0:
		_glitch = maxf(_glitch - delta * 1.2, 0.0)
		queue_redraw()
	if state == State.BOOT:
		_boot_t += delta
		if _boot_t >= 1.9:
			state = State.LIVE
	# ~15 cuadros por segundo: se lee y parece una pantalla de equipo.
	_redraw_t += delta
	if _redraw_t >= 1.0 / 15.0:
		_redraw_t = 0.0
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	match state:
		State.BOOT:
			_draw_boot()
		State.LIVE:
			if failed:
				_draw_error()
			else:
				_draw_live()
	if _glitch > 0.0:
		_draw_glitch()

func _draw_error() -> void:
	var w := int(size.x)
	var h := int(size.y)
	# Estatica roja de fondo.
	for i in 60:
		draw_rect(Rect2(randi() % maxi(w, 1), randi() % maxi(h, 1), 1 + randi() % 4, 1),
			Color(WARN, randf_range(0.05, 0.3)))
	var on := fmod(time, 0.8) < 0.5
	var red := WARN if on else Color(WARN, 0.35)
	frame(Rect2i(3, 3, w - 6, h - 6), red)
	frame(Rect2i(5, 5, w - 10, h - 10), Color(WARN, 0.3))
	var y := h / 2 - 22
	text_centered("⚠ SYSTEM FAILURE ⚠", y, red)
	text_centered("ERROR", y + 10, red, 2)
	text_centered(boot_title + " // NO DATA", y + 28, VALUE)
	# Codigos que cambian solos, como un volcado que no termina.
	var tick := int(time * 3.0)
	var code := hash(boot_title + str(tick)) & 0xFFFF
	text_centered("ERR 0x%04X  CORE BREACH" % code, y + 38, DIM)
	if int(time * 2.0) % 2 == 0:
		text_centered("_", y + 46, WARN)

func _draw_glitch() -> void:
	var w := size.x
	var h := int(size.y)
	var colors := [WARN, TITLE, VALUE, BG, BG]
	for i in int(4 + 16 * _glitch):
		var y := randi() % maxi(h, 1)
		var band := 1 + randi() % int(2 + 8 * _glitch)
		var shift := randf_range(-16.0, 16.0) * _glitch
		var c: Color = colors[randi() % colors.size()]
		draw_rect(Rect2(shift, y, w, band), Color(c, randf_range(0.3, 0.85)))
	if _glitch > 0.6 and randf() < 0.4:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.12))

func _draw_boot() -> void:
	var w := int(size.x)
	var h := int(size.y)
	var y := h / 2 - 12
	text_centered("AN∅MALY // " + boot_title, y, TITLE)
	var dots := ".".repeat(clampi(int(_boot_t * 8.0), 0, 8))
	text_centered("LINK " + dots.rpad(8), y + 11, DIM)
	# Barra de carga.
	var bw := mini(w - 40, 120)
	var bx := (w - bw) / 2
	frame(Rect2i(bx, y + 22, bw, 5), FRAME)
	var fill := int((bw - 2) * clampf(_boot_t / 1.5, 0.0, 1.0))
	draw_rect(Rect2(bx + 1, y + 23, fill, 3), FRAME)
	if _boot_t > 1.5:
		text_centered("OK", y + 30, OK)

## Contenido de cada monitor (se sobreescribe).
func _draw_live() -> void:
	pass

# --- Pantallas que se tocan --------------------------------------------------------
#
# info_monitor.gd convierte el clic sobre la malla de la pantalla en un punto
# en pixeles de ESTA pantalla y lo manda aca. Solo llegan mientras la camara
# esta en la vista enfocada del monitor.

## Clic en la pantalla, en pixeles (0,0 arriba a la izquierda).
func on_screen_click(_pos: Vector2) -> void:
	pass

## El puntero se movio por la pantalla. Vector2(-1, -1) = se fue.
func on_screen_hover(_pos: Vector2) -> void:
	pass

## Hay algo clicable bajo el puntero (para el cursor de mano).
func wants_pointer() -> bool:
	return false

# --- Ayudas de dibujo ------------------------------------------------------------

func text(t: String, pos: Vector2i, color: Color, scale: int = 1) -> void:
	PixelFont.draw(self, t, Vector2(pos), color, scale)

func text_width(t: String, scale: int = 1) -> int:
	return PixelFont.text_width(t, scale)

func text_centered(t: String, y: int, color: Color, scale: int = 1) -> void:
	text(t, Vector2i((int(size.x) - text_width(t, scale)) / 2, y), color, scale)

func text_right(t: String, right: int, y: int, color: Color, scale: int = 1) -> void:
	text(t, Vector2i(right - text_width(t, scale), y), color, scale)

func frame(r: Rect2i, color: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), color)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), color)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), color)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), color)

## Panel con marco y titulo. Devuelve el area interior.
func panel_box(r: Rect2i, title: String, color: Color = FRAME) -> Rect2i:
	frame(r, color)
	if not title.is_empty():
		text(title, r.position + Vector2i(3, 2), TITLE)
		return Rect2i(r.position.x + 3, r.position.y + 11, r.size.x - 6, r.size.y - 13)
	return Rect2i(r.position.x + 3, r.position.y + 3, r.size.x - 6, r.size.y - 6)

## Fila "ETIQUETA ....... valor" dentro de un ancho.
func row(label: String, value: String, x: int, y: int, width: int, color: Color = VALUE) -> void:
	text(label, Vector2i(x, y), DIM)
	text_right(value, x + width, y, color)

## Panel sin datos: NO SIGNAL que parpadea sobre ruido.
func no_signal(r: Rect2i) -> void:
	var seed := int(time * 12.0)
	for i in 40:
		var h := absi(hash(Vector3i(seed, i, r.position.x)))
		var px := r.position.x + (h % maxi(r.size.x, 1))
		var py := r.position.y + ((h >> 8) % maxi(r.size.y, 1))
		draw_rect(Rect2(px, py, 1, 1), Color(DIM, 0.6))
	if fmod(time, 1.2) < 0.85:
		var t := "NO SIGNAL"
		var tw := text_width(t)
		var cx := r.position.x + (r.size.x - tw) / 2
		var cy := r.position.y + (r.size.y - PixelFont.GLYPH_H) / 2
		draw_rect(Rect2(cx - 2, cy - 2, tw + 4, PixelFont.GLYPH_H + 4), BG)
		text(t, Vector2i(cx, cy), WARN.darkened(0.2))

## Numero corto con sufijo (K, M, G, T) para que quepa en pocas letras:
## un decimal si queda por debajo de 100 ("64.6K"), si no ninguno ("764K").
static func short(v: float) -> String:
	var a := absf(v)
	for unit in [[1e12, "T"], [1e9, "G"], [1e6, "M"], [1e4, "K"]]:
		if a >= unit[0]:
			var x: float = v / unit[0]
			if absf(x) < 100.0:
				return "%.1f%s" % [x, unit[1]]
			return "%d%s" % [int(round(x)), unit[1]]
	return str(int(round(v)))
