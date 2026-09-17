extends Control

# Flechas para recorrer un grupo de vistas (los monitores): dos pestanas altas
# a los lados de la pantalla, faciles de tocar en celular. Mismo estilo que la
# barra BACK (view_back_button.gd): marco gris, esquinas naranjas, se ilumina
# al pasar el mouse y destella al usarse.

signal prev_pressed
signal next_pressed

const PixelFont = preload("res://scripts/pixel_font.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

@export var tab_size: Vector2i = Vector2i(15, 44)
@export var side_margin: int = 5
@export var sfx: Node
@export var fill_color: Color = Color(0.012, 0.012, 0.016, 0.72)
@export var frame_color: Color = Color(0.3, 0.3, 0.33)
@export var frame_hover_color: Color = Color(0.55, 0.55, 0.58)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)
@export var idle_color: Color = Color(0.62, 0.62, 0.65)
@export var hover_color: Color = Color(0.96, 0.95, 0.92)

var _material: ShaderMaterial
var _areas: Array[Control] = []
## Por lado (0 = izquierda, 1 = derecha).
var _hover: Array[float] = [0.0, 0.0]
var _hovered: Array[bool] = [false, false]
var _flash: Array[float] = [0.0, 0.0]
var _interactive: bool = false
var _reveal: float = 0.0:
	set(value):
		_reveal = value
		_material.set_shader_parameter("progress", value)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = REVEAL_SHADER
	material = _material
	for side in 2:
		var a := Control.new()
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(a, false, Node.INTERNAL_MODE_FRONT)
		a.mouse_entered.connect(_set_hover.bind(side, true))
		a.mouse_exited.connect(_set_hover.bind(side, false))
		a.gui_input.connect(_on_input.bind(side))
		_areas.append(a)
	_reveal = 0.0
	visible = false
	resized.connect(_layout)
	_layout()

func _tab_rect(side: int) -> Rect2i:
	var y := (int(size.y) - tab_size.y) / 2
	var x := side_margin if side == 0 else int(size.x) - side_margin - tab_size.x
	return Rect2i(x, y, tab_size.x, tab_size.y)

func _layout() -> void:
	for side in _areas.size():
		var r := _tab_rect(side)
		_areas[side].position = Vector2(r.position - Vector2i(4, 6))
		_areas[side].size = Vector2(r.size + Vector2i(8, 12))

func show_bar() -> void:
	visible = true
	var t := create_tween()
	t.tween_property(self, "_reveal", 1.0, 0.3)
	await t.finished
	_set_interactive(true)

func hide_bar() -> void:
	_set_interactive(false)
	if not visible:
		return
	var t := create_tween()
	t.tween_property(self, "_reveal", 0.0, 0.14)
	await t.finished
	if not _interactive:
		visible = false

## Destello de uso (tambien con las teclas). dir -1 izquierda, +1 derecha.
func flash(dir: int) -> void:
	_flash[0 if dir < 0 else 1] = 1.0
	if sfx:
		sfx.play("menu_click")

func _set_interactive(value: bool) -> void:
	_interactive = value
	for a in _areas:
		a.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if not value:
		for side in 2:
			_set_hover(side, false)

func _set_hover(side: int, value: bool) -> void:
	value = value and _interactive
	if _hovered[side] == value:
		return
	_hovered[side] = value
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if value else Input.CURSOR_ARROW)
	if value and sfx:
		sfx.play("menu_hover")

func _on_input(event: InputEvent, side: int) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		flash(-1 if side == 0 else 1)
		if side == 0:
			prev_pressed.emit()
		else:
			next_pressed.emit()
		_areas[side].accept_event()

func _process(delta: float) -> void:
	if not visible:
		return
	for side in 2:
		_hover[side] = move_toward(_hover[side], 1.0 if _hovered[side] else 0.0, delta * 7.0)
		_flash[side] = maxf(_flash[side] - delta * 3.0, 0.0)
	queue_redraw()

func _draw() -> void:
	for side in 2:
		var e := ease(_hover[side], -2.0)
		var r := _tab_rect(side)
		# Se desplaza 1 px hacia afuera al usarse.
		if _flash[side] > 0.6:
			r.position.x += -1 if side == 0 else 1
		draw_rect(r, fill_color)
		var fc := frame_color.lerp(frame_hover_color, e).lerp(accent_color, _flash[side])
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), fc)
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), fc)
		draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), fc)
		draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), fc)
		# Esquinas naranjas.
		for corner in [r.position, Vector2i(r.end.x - 1, r.position.y),
				Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			var sx := 1 if corner.x == r.position.x else -1
			var sy := 1 if corner.y == r.position.y else -1
			draw_rect(Rect2(mini(corner.x, corner.x + sx * 2), corner.y, 3, 1), accent_color)
			draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * 2), 1, 3), accent_color)
		var glyph := "◀" if side == 0 else "▶"
		var col := idle_color.lerp(hover_color, e).lerp(accent_color, _flash[side])
		var bob := int(round(sin(Time.get_ticks_msec() * 0.006) * e)) * (-1 if side == 0 else 1)
		PixelFont.draw(self, glyph, Vector2(r.position.x + (r.size.x - PixelFont.GLYPH_W) / 2 + bob,
			r.position.y + (r.size.y - PixelFont.GLYPH_H) / 2), col)
