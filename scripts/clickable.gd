extends StaticBody3D

# Objeto 3D clicable. pixel_display.gd lanza el rayo y llama a on_clicked /
# on_pointer_move / on_pointer_exit; aqui se convierten en senales.
#
# La colision se crea sola: una caja que envuelve las mallas de `model` (o de
# este mismo nodo si esta vacio). Mientras el objeto esta oculto, la colision
# se apaga: no se puede clicar lo que no se ve, ni tapa clics a otros objetos.

signal clicked(hit_position: Vector3)
signal hover_changed(hovering: bool)

## Modelo a envolver. Vacio = los hijos de este nodo.
@export var model: Node3D
## Grosor minimo de la caja (para vidrios o planos casi sin espesor).
@export var min_thickness: float = 0.05
## Cursor de mano al pasar el mouse.
@export var pointing_cursor: bool = true

var _shape: CollisionShape3D
var _hovering: bool = false

func _ready() -> void:
	_build_collision()
	_update_enabled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_update_enabled()

func _build_collision() -> void:
	var root: Node3D = model if model else self
	var inv := global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		push_warning("Clickable %s: no hay mallas para envolver." % name)
		return
	var size := box.size.max(Vector3.ONE * min_thickness)
	var shape := BoxShape3D.new()
	shape.size = size
	_shape = CollisionShape3D.new()
	_shape.name = "AutoCollision"
	_shape.shape = shape
	_shape.position = box.get_center()
	add_child(_shape)

func _update_enabled() -> void:
	var on := is_visible_in_tree()
	if _shape:
		_shape.set_deferred("disabled", not on)
	if not on:
		on_pointer_exit()

func is_interactive() -> bool:
	return is_visible_in_tree()

func on_pointer_move(_hit_position: Vector3) -> void:
	if not is_interactive() or _hovering:
		return
	_hovering = true
	if pointing_cursor:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	hover_changed.emit(true)

func on_pointer_exit() -> void:
	if not _hovering:
		return
	_hovering = false
	if pointing_cursor:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	hover_changed.emit(false)

func on_clicked(hit_position: Vector3) -> void:
	if is_interactive():
		clicked.emit(hit_position)
