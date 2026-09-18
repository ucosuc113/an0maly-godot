extends Control

# Avisos de crisis en pantalla (en juego, no en cinematicas):
#
#   show_alert(text)      borde rojo que late + cartel "⚠ TEXTO ⚠" arriba
#   show_notice(text, c)  cartel sin borde rojo (p. ej. STABILIZING, en cian)
#   set_detail(text)      segunda linea (cuenta regresiva, porcentaje)
#   set_hint(text)        tercera linea, mas apagada: QUE hacer para salir de
#                         esta (que palanca falta, donde mirar)
#   set_progress(v)       barra bajo el cartel (-1 = sin barra)
#   clear()
#
# show_alert / show_notice se pueden llamar todos los cuadros: si el cartel no
# cambio, no hacen nada (si no, cada cuadro crearia un tween del borde).
#
# MODO COMPACTO (el derretimiento dura tres minutos: un cartelon en el medio
# de la pantalla todo ese rato tapa justo lo que hay que mirar).
#
#   set_compact(true)     en vez del cuadro central, una franja fina arriba a
#                         la izquierda: un punto que late, el reloj
#                         (set_clock) y la pista en gris
#   flash_banner(t, s)    saca el cuadro grande unos segundos y vuelve a la
#                         franja (cambios de acto, avisos que si importan).
#                         Tiene prioridad: mientras dura, ni show_alert ni
#                         set_detail pueden pisarlo, aunque los llamen todos
#                         los cuadros.
#
# El borde rojo se dibuja en escalones de pixeles, como el resto de la UI.

const PixelFont = preload("res://scripts/pixel_font.gd")

@export var alert_color: Color = Color(1.0, 0.2, 0.15)
@export var settings: Node
@export var sfx: Node
## Esquina de la franja compacta.
@export var strip_origin: Vector2i = Vector2i(9, 9)

var _text: String = ""
var _detail: String = ""
var _hint: String = ""
var _clock: String = ""
var _color: Color = Color.WHITE
var _alert: bool = false
var _progress: float = -1.0
var _time: float = 0.0
var _vignette: float = 0.0
var _period: float = 0.667
var _compact: bool = false
## Mensaje del cuadro grande y segundos que le quedan. Mientras esta puesto,
## manda sobre _text / _detail / _hint.
var _banner_text: String = ""
var _banner_t: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_alert(text: String, period: float = 0.667) -> void:
	_period = period
	if _text == text and _alert:
		return
	_text = text
	_alert = true
	_color = alert_color
	create_tween().tween_property(self, "_vignette", 1.0, 0.6)

func show_notice(text: String, color: Color) -> void:
	if _text == text and not _alert and _color == color:
		return
	_text = text
	_color = color
	_alert = false
	create_tween().tween_property(self, "_vignette", 0.0, 1.0)

func set_detail(text: String) -> void:
	_detail = text

## Tercera linea: la salida. Vacio = sin linea.
func set_hint(text: String) -> void:
	_hint = text

## Reloj corto de la franja compacta (p. ej. "T-01:23").
func set_clock(text: String) -> void:
	_clock = text

func set_progress(v: float) -> void:
	_progress = v

## En compacto el cartel se encoge a una franja de esquina.
func set_compact(value: bool) -> void:
	if _compact == value:
		return
	_compact = value

## Saca el cuadro grande `seconds` segundos aunque este en compacto, y aunque
## quien maneje el aviso siga escribiendo su propio cartel cada cuadro.
func flash_banner(text: String, seconds: float = 2.5) -> void:
	_banner_text = text
	_banner_t = maxf(_banner_t, seconds)
	create_tween().tween_property(self, "_vignette", 1.0, 0.4)

## Hay un cartel de flash_banner en pantalla.
func banner_active() -> bool:
	return _banner_t > 0.0 and _banner_text != ""

func clear() -> void:
	_text = ""
	_detail = ""
	_hint = ""
	_clock = ""
	_progress = -1.0
	_alert = false
	_banner_text = ""
	_banner_t = 0.0
	create_tween().tween_property(self, "_vignette", 0.0, 0.8)

func _process(delta: float) -> void:
	_time += delta
	if _banner_t > 0.0:
		_banner_t = maxf(_banner_t - delta, 0.0)
	if _text != "" or _vignette > 0.0 or banner_active():
		queue_redraw()

func _draw() -> void:
	_draw_vignette()
	var flashing := banner_active()
	if _text == "" and not flashing:
		return
	if _compact and not flashing:
		_draw_strip()
	else:
		_draw_box(flashing)

## Borde rojo que late con el pulso.
func _draw_vignette() -> void:
	if _vignette <= 0.0:
		return
	var w := int(size.x)
	var h := int(size.y)
	var calm: bool = settings != null and bool(settings.get_value("reduce_flashing"))
	var beat := 1.0 - fmod(_time, _period) / _period
	var k := _vignette * (0.35 + (0.25 if calm else 0.65) * beat * beat)
	for i in 5:
		var a := k * (0.32 - i * 0.06)
		var c := Color(alert_color, maxf(a, 0.0))
		var d := i * 3
		draw_rect(Rect2(d, d, w - d * 2, 3), c)
		draw_rect(Rect2(d, h - d - 3, w - d * 2, 3), c)
		draw_rect(Rect2(d, d + 3, 3, h - d * 2 - 6), c)
		draw_rect(Rect2(w - d - 3, d + 3, 3, h - d * 2 - 6), c)

## Franja de esquina: punto que late + reloj + pista. Nada en el medio.
func _draw_strip() -> void:
	var o := strip_origin
	var on := not _alert or fmod(_time, _period) < _period * 0.55
	var fc := _color if on else _color.darkened(0.55)
	# El punto late con el pulso aunque el texto no parpadee.
	draw_rect(Rect2(o.x, o.y + 1, 3, 3), fc)
	var x := o.x + 6
	if _clock != "":
		PixelFont.draw(self, _clock, Vector2(x, o.y), _color)
		x += PixelFont.text_width(_clock) + 7
	if _hint != "":
		PixelFont.draw(self, _hint, Vector2(x, o.y), Color(0.62, 0.62, 0.66))
	if _progress >= 0.0:
		var pw := 46
		draw_rect(Rect2(o.x, o.y + 10, pw, 1), Color(_color, 0.25))
		draw_rect(Rect2(o.x, o.y + 10, int(pw * clampf(_progress, 0.0, 1.0)), 1), _color)

## Cuadro central de siempre. Con `flashing`, el mensaje de flash_banner va
## solo: sin cuenta, sin pista y sin barra, para que se lea de un golpe.
func _draw_box(flashing: bool = false) -> void:
	var w := int(size.x)
	var body_text := _banner_text if flashing else _text
	var detail := "" if flashing else _detail
	var hint := "" if flashing else _hint
	var progress := -1.0 if flashing else _progress
	var label := ("⚠ " + body_text + " ⚠") if (_alert or flashing) else body_text
	var tw := PixelFont.text_width(label)
	var bw := maxi(tw, maxi(PixelFont.text_width(detail), PixelFont.text_width(hint))) + 14
	var bh := 13 + (9 if detail != "" else 0) + (9 if hint != "" else 0) \
		+ (5 if progress >= 0.0 else 0)
	var r := Rect2i((w - bw) / 2, 22, bw, bh)
	draw_rect(r, Color(0.01, 0.01, 0.015, 0.85))
	var on := not (_alert or flashing) or fmod(_time, 0.8) < 0.55
	var fc := (alert_color if flashing else _color) if on \
		else (alert_color if flashing else _color).darkened(0.5)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), fc)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), fc)
	PixelFont.draw(self, label, Vector2((w - tw) / 2, r.position.y + 3), fc)
	var y := r.position.y + 12
	if detail != "":
		var dw := PixelFont.text_width(detail)
		PixelFont.draw(self, detail, Vector2((w - dw) / 2, y), Color(0.96, 0.95, 0.92))
		y += 9
	if hint != "":
		var hw := PixelFont.text_width(hint)
		PixelFont.draw(self, hint, Vector2((w - hw) / 2, y), Color(0.62, 0.62, 0.66))
		y += 9
	if progress >= 0.0:
		var pw := bw - 14
		draw_rect(Rect2(r.position.x + 7, y, pw, 3), Color(_color, 0.25))
		draw_rect(Rect2(r.position.x + 7, y, int(pw * clampf(progress, 0.0, 1.0)), 3), _color)
