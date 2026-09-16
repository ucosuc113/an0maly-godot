extends Node

# Ilusion de "levantar la mirada" SIN mover la camara: se mueve el objeto
# (target) con la transformacion inversa exacta de la cabeza.
#
# Si la cabeza gira H (en espacio de camara), lo que la camara ve de un objeto
# W es (C*H)^-1 * W. Con la camara quieta en C, el mismo encuadre se consigue
# poniendo el objeto en  C * H^-1 * C^-1 * W.  Para el objeto es identico
# pixel a pixel (incluido el paralaje del cuello); el resto de la escena no se
# entera, asi que la camara puede seguir apuntando al escenario.
#
# Lo que lo hace leerse como una cabeza:
#   - Pivote en el cuello (debajo y detras de los ojos).
#   - Anticipacion: un pequeno bajon antes de subir.
#   - Arranque y frenada suaves, un leve pasarse de largo y asentarse.
#   - Un poco de inclinacion lateral durante el gesto.

signal finished

## Objeto a mover. Vacio = el padre de este nodo.
@export var target: Node3D
## Camara de referencia. No se modifica nunca.
@export var camera: Camera3D
## Angulo de "mirada" final. <= 0: automatico, el minimo para que el target
## salga entero de cuadro (+ look_margin).
@export var look_up_degrees: float = 0.0
@export var look_margin_degrees: float = 4.0
@export var duration: float = 1.9
@export var anticipation_degrees: float = 2.5
@export var anticipation_time: float = 0.25
## Cuanto se pasa del angulo final antes de asentarse (fraccion del angulo).
@export_range(0.0, 0.2) var overshoot: float = 0.035
@export var settle_time: float = 0.55
@export var roll_degrees: float = 2.0
## Pivote del cuello en coordenadas locales de la camara.
@export var neck_offset: Vector3 = Vector3(0.0, -0.35, 0.25)
## Ocultar el target al terminar (ya esta fuera de cuadro; asi tampoco
## atraviesa geometria del escenario que quede por debajo).
@export var hide_when_done: bool = true

var _rest: Transform3D
var _pitch: float = 0.0
var _roll: float = 0.0
var _playing: bool = false

func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	set_process(false)

func _process(_delta: float) -> void:
	_apply()

func _apply() -> void:
	var c := camera.global_transform
	target.global_transform = c * _head(_pitch, _roll).affine_inverse() \
		* c.affine_inverse() * _rest

## Giro de la cabeza alrededor del cuello, en espacio de camara.
func _head(pitch: float, roll: float) -> Transform3D:
	var rot := Basis.from_euler(Vector3(pitch, 0.0, roll), EULER_ORDER_YXZ)
	return Transform3D(Basis.IDENTITY, neck_offset) \
		* Transform3D(rot, Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -neck_offset)

func play() -> void:
	if _playing or target == null or camera == null:
		return
	_playing = true
	_rest = target.global_transform
	_pitch = 0.0
	_roll = 0.0
	set_process(true)

	var target_deg := look_up_degrees
	if target_deg <= 0.0:
		target_deg = _angle_to_clear() + look_margin_degrees
	var goal := deg_to_rad(minf(target_deg, 85.0))
	var peak := minf(goal * (1.0 + overshoot), deg_to_rad(88.0))
	var dip := -deg_to_rad(anticipation_degrees)

	var t := create_tween()
	t.tween_property(self, "_pitch", dip, anticipation_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_pitch", peak, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_pitch", goal, settle_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Inclinacion lateral: sube y vuelve a cero durante el movimiento principal.
	var r := create_tween()
	r.tween_interval(anticipation_time)
	r.tween_method(func(k: float) -> void: _roll = sin(k * PI) * deg_to_rad(roll_degrees),
		0.0, 1.0, duration + settle_time * 0.5)

	await t.finished
	if r.is_running():
		await r.finished
	_apply()
	set_process(false)
	if hide_when_done:
		target.visible = false
	_playing = false
	finished.emit()

## Menor angulo (grados) con el que todos los vertices del target quedan por
## debajo del borde inferior del cuadro, contando el desplazamiento del cuello.
func _angle_to_clear() -> float:
	var points := PackedVector3Array()
	for mi in target.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		for s in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(xf * v)
	if points.is_empty():
		return 45.0

	var c := camera.global_transform
	var tan_half := tan(deg_to_rad(camera.fov * 0.5))
	var deg := 0.0
	while deg < 85.0:
		# Mismo resultado que mover la camara a C*H: por construccion.
		var inv := (c * _head(deg_to_rad(deg), 0.0)).affine_inverse()
		var visible := false
		for p in points:
			var v := inv * p
			if v.z < 0.0 and v.y / -v.z > -tan_half:
				visible = true
				break
		if not visible:
			return deg
		deg += 0.5
	return 85.0
