extends Control

# Avisos de crisis en pantalla (en juego, no en cinematicas):
#
#   show_alert(text)      borde rojo que late + cartel "⚠ TEXTO ⚠" arriba
#   show_notice(text, c)  cartel sin borde rojo (p. ej. STABILIZING, en cian)
#   set_detail(text)      segunda linea (cuenta regresiva, porcentaje)
#   set_progress(v)       barra bajo el cartel (-1 = sin barra)
#   clear()
#
# El borde rojo se dibuja en escalones de pixeles, como el resto de la UI.

const PixelFont = preload("res://scripts/pixel_font.gd")

@export var alert_color: Color = Color(1.0, 0.2, 0.15)
@export var settings: Node
@export var sfx: Node

var _text: String = ""
var _detail: String = ""
var _color: Color = Color.WHITE
var _alert: bool = false
var _progress: float = -1.0
var _time: float = 0.0
var _vignette: float = 0.0
var _period: float = 0.667

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_alert(text: String, period: float = 0.667) -> void:
	_text = text
	_alert = true
	_color = alert_color
	_period = period
	create_tween().tween_property(self, "_vignette", 1.0, 0.6)

func show_notice(text: String, color: Color) -> void:
	_text = text
	_color = color
	_alert = false
	create_tween().tween_property(self, "_vignette", 0.0, 1.0)

func set_detail(text: String) -> void:
	_detail = text

func set_progress(v: float) -> void:
	_progress = v

func clear() -> void:
	_text = ""
	_detail = ""
	_progress = -1.0
	_alert = false
	create_tween().tween_property(self, "_vignette", 0.0, 0.8)

func _process(delta: float) -> void:
	_time += delta
	if _text != "" or _vignette > 0.0:
		queue_redraw()

func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	# Borde rojo que late con el pulso.
	if _vignette > 0.0:
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
	if _text == "":
		return
	var label := ("⚠ " + _text + " ⚠") if _alert else _text
	var tw := PixelFont.text_width(label)
	var bw := maxi(tw, PixelFont.text_width(_detail)) + 14
	var bh := 13 + (9 if _detail != "" else 0) + (5 if _progress >= 0.0 else 0)
	var r := Rect2i((w - bw) / 2, 22, bw, bh)
	draw_rect(r, Color(0.01, 0.01, 0.015, 0.85))
	var on := not _alert or fmod(_time, 0.8) < 0.55
	var fc := _color if on else _color.darkened(0.5)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), fc)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), fc)
	PixelFont.draw(self, label, Vector2((w - tw) / 2, r.position.y + 3), fc)
	var y := r.position.y + 12
	if _detail != "":
		var dw := PixelFont.text_width(_detail)
		PixelFont.draw(self, _detail, Vector2((w - dw) / 2, y), Color(0.96, 0.95, 0.92))
		y += 9
	if _progress >= 0.0:
		var pw := bw - 14
		draw_rect(Rect2(r.position.x + 7, y, pw, 3), Color(_color, 0.25))
		draw_rect(Rect2(r.position.x + 7, y, int(pw * clampf(_progress, 0.0, 1.0)), 3), _color)
