extends ColorRect

# Transicion universal entre vistas (view_transition.gdshader). Vive en un
# CanvasLayer dentro del PixelViewport. camera_views.gd la usa asi:
#
#   await transition.cover()     # pantalla tapada
#   ...mover la camara...
#   await transition.uncover()   # pantalla destapada
#
# Mientras esta visible bloquea el mouse (nada se clica a mitad de camino).

const SHADER = preload("res://shaders/view_transition.gdshader")

@export var cover_time: float = 0.42
@export var uncover_time: float = 0.5
@export var cell_size: int = 10
@export var edge_color: Color = Color(1.0, 0.52, 0.14)
## Nodo con game_settings.gd: con REDUCE FLASHING las chispas se apagan.
@export var settings: Node

var _material: ShaderMaterial

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = Color.BLACK
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("cell", float(cell_size))
	material = _material
	visible = false
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	_material.set_shader_parameter("rect_size", size)

func is_covered() -> bool:
	return visible and float(_material.get_shader_parameter("progress")) >= 1.0

func cover() -> void:
	var edge := edge_color
	if settings and bool(settings.get_value("reduce_flashing")):
		edge = edge_color.darkened(0.75)
	_material.set_shader_parameter("edge_color", edge)
	_material.set_shader_parameter("uncovering", false)
	_set_progress(0.0)
	visible = true
	var t := create_tween()
	t.tween_method(_set_progress, 0.0, 1.0, cover_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

func uncover() -> void:
	_material.set_shader_parameter("uncovering", true)
	var t := create_tween()
	t.tween_method(_set_progress, 1.0, 0.0, uncover_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	visible = false

func _set_progress(v: float) -> void:
	_material.set_shader_parameter("progress", v)
