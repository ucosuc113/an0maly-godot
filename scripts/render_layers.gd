@tool
extends Node

# Separa que luces afectan a que mallas, usando capas de render.
#
# El renderer Compatibility limita las luces por objeto: si la malla del
# exterior recibe tambien las luces de la sala, esas le roban cupos a las de las
# tiras y algunas dejan de iluminar. Con capas, cada malla solo calcula sus
# propias luces (y ademas es mas barato).
#
#   mesh_targets  -> todas sus mallas pasan a `mesh_layers`
#   light_targets -> todas sus luces solo afectan a `light_mask`
#
# Es @tool para que el editor muestre lo mismo que el juego. Los cambios sobre
# modelos importados no se guardan en la escena: se aplican al abrirla.

@export var mesh_targets: Array[Node3D] = []:
	set(value):
		mesh_targets = value
		_apply()
@export_flags_3d_render var mesh_layers: int = 1:
	set(value):
		mesh_layers = value
		_apply()
@export var light_targets: Array[Node3D] = []:
	set(value):
		light_targets = value
		_apply()
@export_flags_3d_render var light_mask: int = 1:
	set(value):
		light_mask = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return
	for t in mesh_targets:
		if t == null:
			continue
		for g: VisualInstance3D in t.find_children("*", "GeometryInstance3D", true, false):
			g.layers = mesh_layers
		if t is GeometryInstance3D:
			t.layers = mesh_layers
	for t in light_targets:
		if t == null:
			continue
		for l: Light3D in t.find_children("*", "Light3D", true, false):
			l.light_cull_mask = light_mask
		if t is Light3D:
			t.light_cull_mask = light_mask
