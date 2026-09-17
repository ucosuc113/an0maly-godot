extends Control

# Menu de pausa (ESC / P / START). Vive en main.tscn, en un CanvasLayer dentro
# del PixelViewport (misma rejilla de pixeles, cuantizacion y dithering que el
# resto), con process_mode ALWAYS para seguir vivo con el arbol pausado.
#
#   ESC -> la escena se congela y se oscurece con lineas de barrido -> una
#   linea se abre desde el centro y se despliega en un marco -> el texto y los
#   botones se materializan con el mismo disolvente del menu principal.
#
# Paginas: MAIN (RESUME / MAIN MENU) y CONFIRM (volver al menu pierde la
# partida). MAIN MENU funde a negro y recarga la escena; crt_monitor.gd ve la
# marca SKIP_BOOT_META y salta directo al menu principal, sin el arranque.
#
# Solo funciona en juego: GameIntro.room_revealed llama a enable().
#
# La tecla se lee con Input (global) y no con _unhandled_input: el
# PixelViewport solo recibe el mouse que le reenvia pixel_display.gd.

const PixelFont = preload("res://scripts/pixel_font.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")
const CrtMonitor = preload("res://scripts/crt_monitor.gd")

const PAUSE_ACTION := &"pause"

enum Page { MAIN, CONFIRM }

## Nodo con sfx.gd (opcional).
@export var sfx: Node
## ColorRect a pantalla completa por encima de todo (el del FlashLayer): se usa
## para el fundido a negro al volver al menu.
@export var fade: ColorRect
## Pausar solo si la ventana pierde el foco.
@export var pause_on_focus_loss: bool = true
@export var fade_out_time: float = 0.8

@export_group("Look")
@export var panel_size: Vector2i = Vector2i(156, 108)
@export var backdrop_color: Color = Color(0.0, 0.0, 0.0, 0.62)
## Oscurecido extra en filas alternas (lineas de barrido). 0 = sin lineas.
@export_range(0.0, 1.0) var scanline_alpha: float = 0.1
@export var panel_color: Color = Color(0.012, 0.012, 0.016, 0.8)
@export var frame_color: Color = Color(0.3, 0.3, 0.33)
@export var title_color: Color = Color(0.96, 0.95, 0.92)
@export var dim_color: Color = Color(0.42, 0.42, 0.45)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)

@onready var _resume: Control = $ResumeButton
@onready var _to_menu: Control = $MainMenuButton
@onready var _confirm: Control = $ConfirmButton
@onready var _cancel: Control = $CancelButton

## true en juego (la sala ya esta a la vista).
var enabled: bool = false

var _open: bool = false
var _busy: bool = false
var _page: Page = Page.MAIN
var _session_time: float = 0.0
var _time: float = 0.0
var _header: _Layer
var _body: _Layer

## 0..1: oscurecido de la escena.
var _backdrop: float = 0.0:
	set(value):
		_backdrop = value
		queue_redraw()
## 0..1: despliegue del marco (primero la linea horizontal, luego el alto).
var _frame: float = 0.0:
	set(value):
		_frame = value
		queue_redraw()

## Capa de dibujo con su propio disolvente (el material no se hereda).
class _Layer extends Control:
	var draw_fn: Callable
	var material_reveal: ShaderMaterial
	var reveal: float = 0.0:
		set(value):
			reveal = value
			material_reveal.set_shader_parameter("progress", value)

	func _init(fn: Callable) -> void:
		draw_fn = fn
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		material_reveal = ShaderMaterial.new()
		material_reveal.shader = REVEAL_SHADER
		material = material_reveal
		reveal = 0.0

	func _draw() -> void:
		draw_fn.call(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_register_action()

	_header = _Layer.new(_draw_header)
	_body = _Layer.new(_draw_body)
	add_child(_header)
	add_child(_body)
	move_child(_header, 0)
	move_child(_body, 1)

	_resume.pressed.connect(close)
	_to_menu.pressed.connect(_set_page.bind(Page.CONFIRM))
	_confirm.pressed.connect(_return_to_menu)
	_cancel.pressed.connect(_set_page.bind(Page.MAIN))
	for b in _buttons():
		b.hovered.connect(_play.bind("menu_hover"))
		b.pressed.connect(_play.bind("menu_click"))
		b.reveal = 0.0
		b.interactive = false

	resized.connect(_layout)
	_show_page(Page.MAIN)

func _register_action() -> void:
	if InputMap.has_action(PAUSE_ACTION):
		return
	InputMap.add_action(PAUSE_ACTION)
	for key in [KEY_ESCAPE, KEY_P]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(PAUSE_ACTION, e)
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_START
	InputMap.action_add_event(PAUSE_ACTION, j)

## La sala esta a la vista: desde ahora se puede pausar.
func enable() -> void:
	enabled = true
	_session_time = 0.0

func is_open() -> bool:
	return _open

func _process(delta: float) -> void:
	if enabled and not get_tree().paused:
		_session_time += delta
	if Input.is_action_just_pressed(PAUSE_ACTION):
		_on_pause_key()
	if visible:
		_time += delta
		_body.queue_redraw()  # indicador que parpadea

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss:
		open()

func _on_pause_key() -> void:
	if not _open:
		open()
	elif _busy:
		return
	elif _page == Page.CONFIRM:
		_play("menu_click")
		_set_page(Page.MAIN)
	else:
		close()

# --- Abrir / cerrar ---------------------------------------------------------

func open() -> void:
	if _open or _busy or not enabled:
		return
	_open = true
	_busy = true
	get_tree().paused = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_show_page(Page.MAIN)
	_time = 0.0
	visible = true
	_play("pause_in")

	var t := create_tween().set_parallel()
	t.tween_property(self, "_backdrop", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "_frame", 1.0, 0.38) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_header, "reveal", 1.0, 0.45).set_delay(0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_body, "reveal", 1.0, 0.35).set_delay(0.28).set_trans(Tween.TRANS_SINE)
	var shown := _page_buttons()
	for i in shown.size():
		t.tween_property(shown[i], "reveal", 1.0, 0.3) \
			.set_delay(0.34 + i * 0.08).set_trans(Tween.TRANS_SINE)
	await t.finished
	_set_interactive(true)
	_busy = false

func close() -> void:
	if not _open or _busy:
		return
	_busy = true
	_set_interactive(false)
	_play("pause_out")

	var t := create_tween().set_parallel()
	for b in _page_buttons():
		t.tween_property(b, "reveal", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	t.tween_property(_body, "reveal", 0.0, 0.14)
	t.tween_property(_header, "reveal", 0.0, 0.18).set_delay(0.04)
	t.tween_property(self, "_frame", 0.0, 0.22).set_delay(0.08) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.tween_property(self, "_backdrop", 0.0, 0.2).set_delay(0.12)
	await t.finished
	visible = false
	get_tree().paused = false
	_open = false
	_busy = false

## Funde a negro y recarga la escena; el monitor se salta el arranque y el
## menu principal aparece solo.
func _return_to_menu() -> void:
	if _busy:
		return
	_busy = true
	enabled = false
	_set_interactive(false)
	if fade:
		fade.visible = true
		fade.color = Color(0.0, 0.0, 0.0, 0.0)
		var t := create_tween()
		t.tween_property(fade, "color:a", 1.0, fade_out_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await t.finished
	await get_tree().create_timer(0.25).timeout
	get_tree().root.set_meta(CrtMonitor.SKIP_BOOT_META, true)
	get_tree().paused = false
	get_tree().reload_current_scene()

# --- Paginas -----------------------------------------------------------------

func _set_page(page: Page) -> void:
	if _busy or page == _page:
		return
	_busy = true
	_set_interactive(false)
	var t := create_tween().set_parallel()
	for b in _page_buttons():
		t.tween_property(b, "reveal", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	t.tween_property(_body, "reveal", 0.0, 0.14)
	await t.finished

	_show_page(page)
	t = create_tween().set_parallel()
	t.tween_property(_body, "reveal", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	var shown := _page_buttons()
	for i in shown.size():
		t.tween_property(shown[i], "reveal", 1.0, 0.28) \
			.set_delay(0.08 + i * 0.08).set_trans(Tween.TRANS_SINE)
	await t.finished
	_set_interactive(true)
	_busy = false

func _show_page(page: Page) -> void:
	_page = page
	var shown := _page_buttons()
	for b in _buttons():
		b.visible = b in shown
		b.reveal = 0.0
	_layout()

func _buttons() -> Array[Control]:
	return [_resume, _to_menu, _confirm, _cancel]

func _page_buttons() -> Array[Control]:
	if _page == Page.MAIN:
		return [_resume, _to_menu]
	return [_confirm, _cancel]

func _set_interactive(value: bool) -> void:
	for b in _buttons():
		b.interactive = value and b.visible

func _play(sound: String) -> void:
	if sfx:
		sfx.play(sound)

# --- Maqueta -------------------------------------------------------------------
# Coordenadas relativas a la esquina del marco (panel_size):
#   10  PAUSED (x2)          29  subtitulo
#   41  separador            47  aviso (CONFIRM)
#   52/68 botones MAIN       60/76 botones CONFIRM
#   h-16 separador           h-11 pie

func _panel_origin() -> Vector2i:
	return (Vector2i(size) - panel_size) / 2

func _layout() -> void:
	if _resume == null:
		return
	var o := _panel_origin()
	var ys := [52, 68] if _page == Page.MAIN else [60, 76]
	var shown := _page_buttons()
	for i in shown.size():
		var b: Control = shown[i]
		var bs := Vector2i(b.get_combined_minimum_size())
		b.size = Vector2(bs)
		b.position = Vector2(o.x + (panel_size.x - bs.x) / 2, o.y + ys[i])
	queue_redraw()

func _draw() -> void:
	if _backdrop <= 0.0:
		return
	var bd := backdrop_color
	bd.a *= _backdrop
	draw_rect(Rect2(Vector2.ZERO, size), bd)
	if scanline_alpha > 0.0:
		var sc := Color(0.0, 0.0, 0.0, scanline_alpha * _backdrop)
		for y in range(0, int(size.y), 2):
			draw_rect(Rect2(0, y, size.x, 1), sc)

	if _frame <= 0.0:
		return
	# 0..0.45 se abre la linea; 0.45..1 se despliega el alto.
	var open_w := smoothstep(0.0, 0.45, _frame)
	var open_h := smoothstep(0.45, 1.0, _frame)
	var o := _panel_origin()
	var w: int = maxi(2, int(round(panel_size.x * open_w / 2.0)) * 2)
	var h: int = maxi(1, int(round(panel_size.y * open_h / 2.0)) * 2)
	var box := Rect2i(o.x + (panel_size.x - w) / 2, o.y + (panel_size.y - h) / 2, w, h)

	var fill := panel_color
	fill.a *= open_h
	draw_rect(box, fill)
	var line := frame_color if open_h > 0.0 else accent_color
	_hline(box.position.x, box.end.x, box.position.y, line)
	if h > 1:
		_hline(box.position.x, box.end.x, box.end.y - 1, line)
		_vline(box.position.x, box.position.y, box.end.y, line)
		_vline(box.end.x - 1, box.position.y, box.end.y, line)

	# Esquinas naranjas, cuando el marco ya tiene alto.
	if h >= 12:
		var c := accent_color
		c.a = open_h
		var L := 6
		for corner in [box.position, Vector2i(box.end.x - 1, box.position.y),
				Vector2i(box.position.x, box.end.y - 1), box.end - Vector2i.ONE]:
			var sx := 1 if corner.x == box.position.x else -1
			var sy := 1 if corner.y == box.position.y else -1
			draw_rect(Rect2(mini(corner.x, corner.x + sx * (L - 1)), corner.y, L, 1), c)
			draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * (L - 1)), 1, L), c)

func _hline(x0: int, x1: int, y: int, color: Color) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, 1), color)

func _vline(x: int, y0: int, y1: int, color: Color) -> void:
	draw_rect(Rect2(x, y0, 1, y1 - y0), color)

func _dotted(canvas: CanvasItem, y: int, x0: int, x1: int, color: Color) -> void:
	for x in range(x0, x1, 2):
		canvas.draw_rect(Rect2(x, y, 1, 1), color)

func _text_centered(canvas: CanvasItem, text: String, y: int, color: Color,
		scale: int = 1, tracking: int = 0) -> void:
	var o := _panel_origin()
	var tw := PixelFont.text_width(text, scale, tracking)
	PixelFont.draw(canvas, text, Vector2(o.x + (panel_size.x - tw) / 2, y), color, scale, tracking)

## Titulo y separadores: fijos en las dos paginas.
func _draw_header(canvas: CanvasItem) -> void:
	var o := _panel_origin()
	_text_centered(canvas, "PAUSED", o.y + 10, title_color, 2, 2)
	var sep := frame_color
	_dotted(canvas, o.y + 41, o.x + 12, o.x + panel_size.x - 12, sep)
	_dotted(canvas, o.y + panel_size.y - 16, o.x + 12, o.x + panel_size.x - 12, sep)

## Lo que cambia con la pagina: subtitulo, aviso y pie.
func _draw_body(canvas: CanvasItem) -> void:
	var o := _panel_origin()
	var y := o.y + 29
	if _page == Page.MAIN:
		# Indicador que parpadea (como el REC de una camara, en pausa).
		var text := "SIMULATION HALTED"
		var tw := PixelFont.text_width(text)
		var x := o.x + (panel_size.x - tw - 6) / 2
		if fmod(_time, 1.0) < 0.6:
			canvas.draw_rect(Rect2(x, y + 2, 3, 3), accent_color)
		PixelFont.draw(canvas, text, Vector2(x + 6, y), accent_color.darkened(0.15))
	else:
		_text_centered(canvas, "RETURN TO MAIN MENU?", y, accent_color)
		_text_centered(canvas, "PROGRESS WILL BE LOST", o.y + 47, dim_color)

	var fy := o.y + panel_size.y - 11
	var secs := int(_session_time)
	var clock := "T+%02d:%02d" % [secs / 60, secs % 60]
	PixelFont.draw(canvas, clock, Vector2(o.x + 10, fy), dim_color)
	var hint := "[ESC] RESUME" if _page == Page.MAIN else "[ESC] BACK"
	var hw := PixelFont.text_width(hint)
	PixelFont.draw(canvas, hint, Vector2(o.x + panel_size.x - 10 - hw, fy), dim_color)
