extends CanvasLayer

# Contador de FPS del ajuste SHOW FPS. Va en el viewport raiz, fuera del
# PixelViewport: nitido, sin cuantizar, y chico en cualquier pantalla.

var _label: Label
var _t: float = 1.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	add_child(_label)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		_label.text = "%d FPS" % Engine.get_frames_per_second()
		_layout()

## Alto de letra: ~1.8% de la ventana, sin bajar de ~2 mm fisicos (pantallas densas).
func _layout() -> void:
	var win := get_viewport().get_visible_rect().size
	var dpi := float(DisplayServer.screen_get_dpi())
	var font_px := roundi(maxf(win.y * 0.018, dpi * 0.08))
	font_px = clampi(font_px, 10, 64)
	_label.add_theme_font_size_override("font_size", font_px)
	_label.add_theme_constant_override("outline_size", maxi(2, font_px / 6))
	var safe := Rect2(Vector2.ZERO, win)
	if OS.has_feature("mobile"):
		var s := DisplayServer.get_display_safe_area()
		var screen := Vector2(DisplayServer.screen_get_size())
		if s.size.x > 0 and screen.x > 0:
			var k := win / screen
			safe = Rect2(Vector2(s.position) * k, Vector2(s.size) * k)
	var margin := font_px * 0.5
	_label.size = _label.get_minimum_size()
	_label.position = Vector2(safe.end.x - _label.size.x - margin, safe.position.y + margin * 0.6)
