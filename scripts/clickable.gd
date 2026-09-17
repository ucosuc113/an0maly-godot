extends StaticBody3D

# Objeto 3D clicable. pixel_display.gd lanza el rayo y llama a on_clicked /
# on_pointer_move / on_pointer_exit; aqui se convierten en senales.
#
# La colision se crea sola a partir de las mallas de `model` (o de este mismo
# nodo si esta vacio): una caja que las envuelve o, con collision_from_mesh, la
# forma exacta de cada malla. Mientras el objeto esta oculto o `enabled` es
# false, la colision se apaga: no se puede clicar ni tapa clics a otros objetos.

signal clicked(hit_position: Vector3)
signal hover_changed(hovering: bool)

## Modelo a envolver. Vacio = los hijos de este nodo.
@export var model: Node3D
## Colision con la forma exacta de las mallas en vez de una caja.
@export var collision_from_mesh: bool = false
## Grosor minimo de la caja (para vidrios o planos casi sin espesor).
@export var min_thickness: float = 0.05
## Cursor de mano al pasar el mouse.
@export var pointing_cursor: bool = true

## false = no responde (p. ej. fuera de la vista donde se usa).
var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready():
			_update_enabled()

var _shapes: Array[CollisionShape3D] = []
var _hovering: bool = false

func _ready() -> void:
	_build_collision()
	_update_enabled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_update_enabled()

func _meshes() -> Array[Node]:
	var root: Node3D = model if model else self
	return root.find_children("*", "MeshInstance3D", true, false)

func _build_collision() -> void:
	var inv := global_transform.affine_inverse()
	if collision_from_mesh:
		for mi: MeshInstance3D in _meshes():
			# La transformacion se aplica a los vertices, no a la forma: los
			# FBX llegan con escalas grandes (x12, x100) y Jolt descarta los
			# triangulos de una malla diminuta escalada.
			var xf := inv * mi.global_transform
			var faces := mi.mesh.get_faces()
			if faces.is_empty():
				continue
			for i in faces.size():
				faces[i] = xf * faces[i]
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			_add_shape(shape, Transform3D.IDENTITY)
		if _shapes.is_empty():
			push_warning("Clickable %s: no hay mallas para la colision." % name)
		return

	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes():
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		push_warning("Clickable %s: no hay mallas para envolver." % name)
		return
	var shape := BoxShape3D.new()
	shape.size = box.size.max(Vector3.ONE * min_thickness)
	_add_shape(shape, Transform3D(Basis.IDENTITY, box.get_center()))

func _add_shape(shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "AutoCollision"
	cs.shape = shape
	cs.transform = xf
	add_child(cs, true)
	_shapes.append(cs)

func _update_enabled() -> void:
	var on := is_interactive()
	for cs in _shapes:
		cs.set_deferred("disabled", not on)
	if not on:
		on_pointer_exit()

func is_interactive() -> bool:
	return enabled and is_visible_in_tree()

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
