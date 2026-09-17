extends Node

# Texturas de modelos importados (FBX) en filtro "nearest": los numeros y
# simbolos de las placas son pixel art de 5x7 / 15x9, y con el filtro lineal
# que trae el FBX se veian suavizados. Recorre las mallas de `targets` y cambia
# sus materiales con textura. Los materiales importados son compartidos: el
# cambio vale para todas las instancias (es lo que se quiere).

@export var targets: Array[Node3D] = []

func _ready() -> void:
	for t in targets:
		if t == null:
			continue
		for mi: MeshInstance3D in t.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m and m.albedo_texture:
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
