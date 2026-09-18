extends "res://scripts/mesh_interactable.gd"

# Pieza que lleva la camara a otra vista, y a CUAL depende de desde donde se
# la mire. Es lo que permite anidar enfoques.
#
# La mesa de la sala de emergencia, por ejemplo:
#     desde "Room"       -> "Emergency"        (la vista general del cuartito)
#     desde "Emergency"  -> "EmergencyPanel"   (ya adentro, al panel)
#
# `mesh_interactable.gd` solo sabe abrir UNA vista fija (view_name), asi que
# para esto hacen falta rutas. Los dos arreglos van apareados: from_views[i]
# es la vista desde la que responde y to_views[i] a la que lleva. Desde
# cualquier otra vista, la pieza no responde.

## Vistas desde las que responde.
@export var from_views: Array[StringName] = []
## A donde lleva desde cada una (mismo orden).
@export var to_views: Array[StringName] = []

## Vista a la que llevaria ahora mismo ("" = no responde desde aqui).
var _target: StringName = &""

func _ready() -> void:
	super._ready()
	if views:
		views.view_changed.connect(_on_view_changed)
		_on_view_changed(views.current)

func _on_view_changed(view: StringName) -> void:
	var i := from_views.find(view)
	_target = to_views[i] if i >= 0 and i < to_views.size() else &""
	enabled = not _target.is_empty()

func _on_clicked(_hit_position: Vector3) -> void:
	if _target.is_empty() or views == null or views.is_busy():
		return
	enabled = false  # suelta el hover y el cursor de mano
	views.go_to(_target)
