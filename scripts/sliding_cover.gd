extends Node

# Tapa que se desliza para destapar algo (los cristales de los botones 2 y 3,
# la tapa de las palancas). Vive como nodo en main.tscn junto al modelo.
#
#   await $Cover.open()
#
# Primero baja un poco (se "suelta"), luego se desliza hacia la pared y queda
# escondida dentro de ella; al final se oculta. Con opacity < 1 la tapa se
# vuelve vidrio (los materiales se reemplazan por copias transparentes).

signal opened

@export var target: Node3D
## Desplazamiento total del deslizamiento, en metros (espacio del mundo).
## Por defecto hacia la pared (-X), un poco mas que el fondo de la tapa.
@export var slide: Vector3 = Vector3(-0.17, 0.0, 0.0)
## Cuanto baja antes de deslizarse.
@export var drop: float = 0.004
@export var duration: float = 0.9
## 1 = opaca. 0.2 = vidrio 80% transparente.
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
@export var sfx: Node

var is_open: bool = false

func _ready() -> void:
	if target == null:
		return
	# El juego siempre empieza con la tapa puesta, aunque en el editor se haya
	# ocultado para trabajar debajo.
	target.visible = true
	if opacity < 1.0:
		_make_glass()

func _make_glass() -> void:
	for mi: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as BaseMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = opacity
			m.roughness = 0.05
			m.metallic_specular = 0.9
			mi.set_surface_override_material(s, m)

func open() -> void:
	if is_open or target == null:
		return
	is_open = true
	if sfx:
		sfx.play("cover_slide")
	var start := target.global_position
	var down := start + Vector3(0.0, -drop, 0.0)
	var t := create_tween()
	t.tween_property(target, "global_position", down, duration * 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(target, "global_position", down + slide, duration * 0.85) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	target.visible = false
	opened.emit()
