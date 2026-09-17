extends "res://scripts/clickable.gd"

# Cristal del ventanal: clicable (clickable.gd) y con el vidrio transparente.
#
# El vidrio de Blender llega por FBX como material opaco y taparia el exterior;
# aqui se reemplaza esa superficie por un vidrio semitransparente con brillo.

## Superficie del modelo que es el vidrio (0 = Material.015).
@export var glass_surface: int = 0
@export var glass_tint: Color = Color(0.72, 0.85, 0.95)
## Opacidad del vidrio: 0.15 = 85% transparente.
@export_range(0.0, 1.0, 0.01) var glass_opacity: float = 0.15
@export_range(0.0, 1.0, 0.01) var glass_roughness: float = 0.05

var glass_material: StandardMaterial3D

func _ready() -> void:
	glass_material = StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(glass_tint, glass_opacity)
	glass_material.roughness = glass_roughness
	glass_material.metallic_specular = 0.9
	var root: Node3D = model if model else self
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if glass_surface < mi.mesh.get_surface_count():
			mi.set_surface_override_material(glass_surface, glass_material)
	super._ready()
