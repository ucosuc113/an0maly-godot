@tool
extends Control

# Barra BACK para salir de una vista (camera_views.gd). Pensada tambien para
# celular: una tecla ancha y baja, como una barra espaciadora, centrada abajo
# (o arriba, con at_top).
#
# Mismo lenguaje que los menus: marco gris fino con esquinas naranjas, texto
# gris que se ilumina, linea naranja que se abre desde el centro al pasar el
# mouse, y aparece/desaparece con el disolvente. Al presionarla se hunde 1 px
# como una tecla. En escritorio muestra la tecla de atajo; en tactil no.

signal pressed

const PixelFont = preload("res://scripts/pixel_font.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

@export var text: String = "BACK":
	set(value):
		text = value
		queue_redraw()
@export var key_hint: String = "SPACE"
@export var bar_size: Vector2i = Vector2i(124, 15):
	set(value):
		bar_size = value
		_layout()
## Distancia al borde (abajo, o arriba con at_top), en pixeles.
@export var bottom_margin: int = 7:
	set(value):
		bottom_margin = value
		_layout()
## Arriba en vez de abajo (vistas divididas: abajo esta el panel).
@export var at_top: bool = false:
	set(value):
		at_top = value
		_layout()
@export var sfx: Node

@export_group("Look")
@export var fill_color: Color = Color(0.012, 0.012, 0.016, 0.72)
@export var frame_color: Color = Color(0.3, 0.3, 0.33)
@export var frame_hover_color: Color = Color(0.55, 0.55, 0.58)
@export var idle_color: Color = Color(0.62, 0.62, 0.65)
@export var hover_color: Color = Color(0.96, 0.95, 0.92)
@export var dim_color: Color = Color(0.36, 0.36, 0.39)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)

var reveal: float = 1.0:
	set(value):
		reveal = value
		if _material:
			_material.set_shader_parameter("progress", value)
var interactive: bool = false:
	set(value):
		interactive = value
		if not value:
			_set_hovered(false)

var _material: ShaderMaterial
var _hovered: bool = false
var _hover_t: float = 0.0
var _flash: float = 0.0
## Clic/toque sostenido sobre la barra.
var _holding: bool = false
var _time: float = 0.0
var _show_hint: bool = true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = REVEAL_SHADER
	material = _material
	_layout()
	if Engine.is_editor_hint():
		return
	reveal = 0.0
	visible = false
	_show_hint = not (OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios"))
	resized.connect(_layout)

## El boton en si es un Control hijo invisible con el area exacta de la barra:
## asi el resto de la pantalla no bloquea clics al mundo 3D.
var _hit: Control

func _layout() -> void:
	if not is_inside_tree():
		return
	if _hit == null:
		_hit = Control.new()
		_hit.name = "HitArea"
		_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hit, false, Node.INTERNAL_MODE_FRONT)
		if not Engine.is_editor_hint():
			_hit.mouse_entered.connect(_set_hovered.bind(true))
			_hit.mouse_exited.connect(_set_hovered.bind(false))
			_hit.gui_input.connect(_on_hit_input)
	var r := _bar_rect(0)
	# Un poco mas generosa que lo dibujado: mas facil de tocar con el dedo.
	_hit.position = Vector2(r.position - Vector2i(4, 3))
	_hit.size = Vector2(r.size + Vector2i(8, 6))
	queue_redraw()

func _bar_rect(offset_y: int) -> Rect2i:
	var s := Vector2i(size)
	var y := bottom_margin if at_top else s.y - bottom_margin - bar_size.y
	return Rect2i((s.x - bar_size.x) / 2, y + offset_y, bar_size.x, bar_size.y)

func show_bar() -> void:
	visible = true
	_time = 0.0
	var t := create_tween()
	t.tween_property(self, "reveal", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	await t.finished
	interactive = true
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP

func hide_bar() -> void:
	interactive = false
	_holding = false
	if _hit:
		_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not visible:
		return
	var t := create_tween()
	t.tween_property(self, "reveal", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	await t.finished
	if not interactive:
		visible = false

## Destello de "tecla presionada" (tambien cuando se usa el atajo).
func flash() -> void:
	_flash = 1.0
	_play("menu_click")
	queue_redraw()

func _set_hovered(value: bool) -> void:
	value = value and interactive
	if _hovered == value:
		return
	_hovered = value
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if value else Input.CURSOR_ARROW)
	if value:
		_play("menu_hover")

func _on_hit_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_holding = true
		elif _holding:
			# Se activa al soltar (como una tecla): se puede arrepentir
			# arrastrando fuera de la barra.
			_holding = false
			if Rect2(Vector2.ZERO, _hit.size).has_point(event.position):
				flash()
				pressed.emit()
		_hit.accept_event()

func _play(sound: String) -> void:
	if sfx:
		sfx.play(sound)

func _process(delta: float) -> void:
	if not visible or Engine.is_editor_hint():
		return
	_time += delta
	var goal := 1.0 if _hovered else 0.0
	_hover_t = move_toward(_hover_t, goal, delta * 7.0)
	_flash = maxf(_flash - delta * 3.0, 0.0)
	queue_redraw()

func _draw() -> void:
	var e := ease(_hover_t, -2.0)
	# Hundida 1 px mientras se sostiene y durante el destello.
	var sunk := _holding or _flash > 0.6
	var r := _bar_rect(1 if sunk else 0)

	draw_rect(r, fill_color)
	var fc := frame_color.lerp(frame_hover_color, e).lerp(accent_color, _flash)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), fc)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), fc)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), fc)
	# "Grosor" de tecla: una fila mas oscura debajo que desaparece al hundirse.
	if not sunk:
		draw_rect(Rect2(r.position.x + 1, r.end.y, r.size.x - 2, 1), Color(0, 0, 0, 0.6))

	# Esquinas naranjas.
	var L := 4
	var ac := accent_color
	for corner in [r.position, Vector2i(r.end.x - 1, r.position.y),
			Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
		var sx := 1 if corner.x == r.position.x else -1
		var sy := 1 if corner.y == r.position.y else -1
		draw_rect(Rect2(mini(corner.x, corner.x + sx * (L - 1)), corner.y, L, 1), ac)
		draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * (L - 1)), 1, L), ac)

	# Texto con chevrons que apuntan al borde (hacia donde "sales").
	var tw := PixelFont.text_width(text, 1, 1)
	var ty := r.position.y + (r.size.y - PixelFont.GLYPH_H) / 2
	var tx := r.position.x + (r.size.x - tw) / 2
	var col := idle_color.lerp(hover_color, e).lerp(accent_color, _flash)
	PixelFont.draw(self, text, Vector2(tx, ty), col, 1, 1)

	var bob := 1 if fmod(_time, 1.2) < 0.6 and e > 0.5 else 0
	var arrow := "▲" if at_top else "▼"
	if at_top:
		bob = -bob
	var chev := accent_color
	chev.a = lerpf(0.55, 1.0, e)
	var gap := int(round(lerpf(8.0, 5.0, e)))
	PixelFont.draw(self, arrow, Vector2(tx - gap - PixelFont.GLYPH_W, ty + bob), chev)
	PixelFont.draw(self, arrow, Vector2(tx + tw + gap, ty + bob), chev)

	# Linea que se abre desde el centro bajo el texto.
	var lw: int = int(round((tw + 2 * gap + 2 * PixelFont.GLYPH_W) * e / 2.0)) * 2
	if lw > 0:
		var lc := accent_color
		lc.a = e
		draw_rect(Rect2(r.position.x + (r.size.x - lw) / 2, r.end.y - 3, lw, 1), lc)

	# Atajo de teclado (solo escritorio), como una tecla a la derecha de la barra.
	if _show_hint and not key_hint.is_empty():
		var hw := PixelFont.text_width(key_hint)
		var hint_x := r.position.x + bar_size.x + 6
		draw_rect(Rect2(hint_x - 2, ty - 2, hw + 4, PixelFont.GLYPH_H + 4), fill_color)
		PixelFont.draw(self, key_hint, Vector2(hint_x, ty), dim_color)
		draw_rect(Rect2(hint_x - 2, ty - 2, hw + 4, 1), dim_color)
		draw_rect(Rect2(hint_x - 2, ty + PixelFont.GLYPH_H + 1, hw + 4, 1), dim_color)
