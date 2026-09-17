@tool
extends Control

# Boton de texto del menu principal, pensado para flotar en la oscuridad: sin
# caja ni fondo. En reposo el texto es gris tenue; al pasar el mouse se
# ilumina, aparecen marcadores a los lados y una linea naranja se abre desde el
# centro. Todo en la rejilla de pixeles del juego (PixelFont, posiciones enteras).

signal pressed
## El puntero entro al boton (solo si esta interactivo).
signal hovered

const PixelFont = preload("res://scripts/pixel_font.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

@export var text: String = "BUTTON":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()
## El boton principal se ve un poco mas presente en reposo.
@export var primary: bool = false:
	set(value):
		primary = value
		queue_redraw()
@export var idle_color: Color = Color(0.5, 0.5, 0.53)
@export var primary_idle_color: Color = Color(0.72, 0.72, 0.74)
@export var hover_color: Color = Color(0.96, 0.95, 0.92)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)

## 0..1: aparicion con dithering (lo anima main_menu.gd).
var reveal: float = 1.0:
	set(value):
		reveal = value
		if _material:
			_material.set_shader_parameter("progress", value)
## Si es false no reacciona (mientras aparece o tras elegir una opcion).
var interactive: bool = true:
	set(value):
		interactive = value
		if not value:
			_set_hovered(false)

var _material: ShaderMaterial
var _hovered: bool = false
var _hover_t: float = 0.0
var _flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Reusa el material si ya existe (el editor lo guarda en la escena porque
	# este script es @tool); si no, crea uno propio para este boton.
	if material is ShaderMaterial and (material as ShaderMaterial).shader == REVEAL_SHADER:
		_material = material
	else:
		_material = ShaderMaterial.new()
		_material.shader = REVEAL_SHADER
		material = _material
	_material.set_shader_parameter("progress", reveal)
	if not Engine.is_editor_hint():
		mouse_entered.connect(_set_hovered.bind(true))
		mouse_exited.connect(_set_hovered.bind(false))

func _get_minimum_size() -> Vector2:
	# Espacio para los marcadores a los lados y la linea de abajo.
	return Vector2(PixelFont.text_width(text) + 28, 12)

func _set_hovered(value: bool) -> void:
	value = value and interactive
	if _hovered == value:
		return
	_hovered = value
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if value else Input.CURSOR_ARROW)
	if value:
		hovered.emit()

func _process(delta: float) -> void:
	var goal := 1.0 if _hovered else 0.0
	var changed := false
	if not is_equal_approx(_hover_t, goal):
		_hover_t = move_toward(_hover_t, goal, delta * 7.0)
		changed = true
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		changed = true
	if changed:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_flash = 1.0
		queue_redraw()
		accept_event()
		pressed.emit()

func _draw() -> void:
	var e := ease(_hover_t, -2.0)  # entrada y salida suaves
	var tw: int = PixelFont.text_width(text)
	var x0: int = int(size.x - tw) / 2
	var y0: int = int(size.y - PixelFont.GLYPH_H) / 2 - 1

	var base := primary_idle_color if primary else idle_color
	var col := base.lerp(hover_color, e)
	col = col.lerp(accent_color, _flash)
	PixelFont.draw(self, text, Vector2(x0, y0), col)

	if e <= 0.01:
		return

	# Marcadores: se acercan al texto desde 5 px hasta 2 px.
	var gap: int = int(round(lerpf(5.0, 2.0, e)))
	var marker := accent_color
	marker.a = e
	PixelFont.draw(self, "▶", Vector2(x0 - gap - PixelFont.GLYPH_W, y0), marker)
	PixelFont.draw(self, "◀", Vector2(x0 + tw + gap, y0), marker)

	# Linea que se abre desde el centro, 2 px bajo el texto.
	var lw: int = int(round(tw * e / 2.0)) * 2
	if lw > 0:
		draw_rect(Rect2(x0 + (tw - lw) / 2, y0 + PixelFont.GLYPH_H + 2, lw, 1), marker)
