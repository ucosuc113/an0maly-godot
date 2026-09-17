extends Node

# TEMPORAL: gira un nodo 3D con el mouse para inspeccionarlo desde cualquier
# angulo. Para quitarlo, borra el nodo DebugOrbit de main.tscn y este archivo.
#
#   Clic derecho + arrastrar  -> girar
#   Rueda                     -> girar sobre el eje de la vista (roll)
#   R                         -> volver a la orientacion inicial
#
# Usa el clic derecho para no chocar con el clic izquierdo de pixel_display.gd.

@export var target: Node3D
## Grados por pixel arrastrado.
@export var sensitivity: float = 0.4
@export var roll_step_degrees: float = 5.0

var _dragging: bool = false
var _initial_basis: Basis

func _ready() -> void:
	if target:
		_initial_basis = target.basis

func _input(event: InputEvent) -> void:
	if target == null:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_rotate_global(Vector3.BACK, deg_to_rad(roll_step_degrees))
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_rotate_global(Vector3.BACK, -deg_to_rad(roll_step_degrees))

	elif event is InputEventMouseMotion and _dragging:
		var d: Vector2 = event.relative * deg_to_rad(sensitivity)
		# Ejes fijos de pantalla (la camara mira a -Z sin rotar): arrastrar a la
		# derecha gira alrededor de Y, arrastrar hacia abajo alrededor de X.
		_rotate_global(Vector3.UP, d.x)
		_rotate_global(Vector3.RIGHT, d.y)

	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_R:
		target.basis = _initial_basis

func _rotate_global(axis: Vector3, angle: float) -> void:
	# Rotar la base respecto a ejes del mundo (no los locales) hace que el giro
	# siempre siga al mouse, sin importar cuanto se haya girado antes.
	target.basis = Basis(axis, angle) * target.basis
