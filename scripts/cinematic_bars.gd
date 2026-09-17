extends Control

# Franjas de cine para las secuencias (fases del panel). Vive en un CanvasLayer
# dentro del PixelViewport. Las franjas negras entran desde arriba y abajo;
# en la de abajo se escribe un subtitulo tipo terminal, con un cursor y una
# marca naranja; en la de arriba, un indicador "REC" y el reloj de la toma.
#
#   await bars.show_bars("PHASE 01 // PLASMA INJECTION")
#   bars.set_caption("EMITTERS ONLINE", bars.ok_color)
#   await bars.hide_bars()

const PixelFont = preload("res://scripts/pixel_font.gd")

@export var bar_height: int = 16
@export var text_color: Color = Color(0.96, 0.95, 0.92)
@export var dim_color: Color = Color(0.42, 0.42, 0.45)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)
@export var ok_color: Color = Color(0.45, 1.0, 0.55)
@export var sfx: Node
@export var type_interval: float = 0.035

var _open: float = 0.0:
	set(value):
		_open = value
		queue_redraw()
var _caption: String = ""
var _shown_chars: int = 0
var _caption_color: Color
var _time: float = 0.0
var _typing: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_color = text_color
	visible = false

func show_bars(caption: String = "") -> void:
	visible = true
	_time = 0.0
	_caption = ""
	_shown_chars = 0
	var t := create_tween()
	t.tween_property(self, "_open", 1.0, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await t.finished
	if not caption.is_empty():
		await set_caption(caption)

func hide_bars() -> void:
	var t := create_tween()
	t.tween_property(self, "_open", 0.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	await t.finished
	visible = false

## Escribe el subtitulo letra por letra (reemplaza el anterior).
func set_caption(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	_typing += 1
	var id := _typing
	_caption = text
	_caption_color = text_color if color.a == 0.0 else color
	_shown_chars = 0
	for i in text.length():
		if id != _typing:
			return
		_shown_chars = i + 1
		if text[i] != " " and sfx:
			sfx.play("crt_type", -12.0, randf_range(0.95, 1.1))
		queue_redraw()
		await get_tree().create_timer(type_interval, false).timeout

func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()

func _draw() -> void:
	if _open <= 0.0:
		return
	var w := int(size.x)
	var h := int(size.y)
	var bh := int(round(bar_height * ease(_open, 0.5)))
	draw_rect(Rect2(0, 0, w, bh), Color.BLACK)
	draw_rect(Rect2(0, h - bh, w, bh), Color.BLACK)
	if _open < 0.99:
		return
	# Lineas finas en el borde interior de las franjas.
	draw_rect(Rect2(0, bh - 1, w, 1), Color(dim_color, 0.5))
	draw_rect(Rect2(0, h - bh, w, 1), Color(dim_color, 0.5))

	# Arriba: REC que parpadea + reloj de la toma.
	var ty := (bh - PixelFont.GLYPH_H) / 2
	if fmod(_time, 1.0) < 0.6:
		draw_rect(Rect2(8, ty + 2, 3, 3), accent_color)
	PixelFont.draw(self, "REC", Vector2(14, ty), dim_color)
	var secs := int(_time)
	var clock := "%02d:%02d:%02d" % [secs / 60, secs % 60, int(fmod(_time, 1.0) * 24.0)]
	PixelFont.draw(self, clock, Vector2(w - 8 - PixelFont.text_width(clock), ty), dim_color)

	# Abajo: marca + subtitulo + cursor.
	if _caption.is_empty():
		return
	var cy := h - bh + (bh - PixelFont.GLYPH_H) / 2
	var shown := _caption.substr(0, _shown_chars)
	var tw := PixelFont.text_width(_caption)
	var x := (w - tw) / 2
	draw_rect(Rect2(x - 7, cy + 2, 3, 3), accent_color)
	PixelFont.draw(self, shown, Vector2(x, cy), _caption_color)
	if fmod(_time, 0.8) < 0.5:
		var cx := x + PixelFont.text_width(shown) + (1 if shown.length() > 0 else 0)
		PixelFont.draw(self, "█", Vector2(cx, cy), Color(_caption_color, 0.8))
