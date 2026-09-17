extends Node

# Controla los materiales emisivos de un modelo importado (FBX/GLB): color,
# energia e intensidad, en vivo. Vive como nodo en main.tscn.
#
# Toma las superficies cuyo material emite (energia > 0 al importar) o, si
# material_names no esta vacio, solo las de esos nombres (los de Blender, p. ej.
# "Material.010"). Cada material se duplica: cambiar uno no afecta a otros
# modelos que compartan el recurso importado.
#
#   $GlowPortal.glow_color = Color.RED
#   $GlowPortal.fade_to(0.0, 1.5)          # apagar en 1.5 s
#
# Ojo: en el renderer Compatibility la emision hace brillar la superficie pero
# NO ilumina lo de alrededor. Para que alumbre, acompanala con luces reales
# (lights: un nodo con Light3D dentro): este nodo les copia el color y escala su
# energia con la intensidad.

@export var target: Node3D
## Nombres de material a controlar. Vacio = todos los que emiten.
@export var material_names: PackedStringArray = []
@export var glow_color: Color = Color(1, 1, 1):
	set(value):
		glow_color = value
		_apply()
## Energia de emision a intensidad 1.
@export_range(0.0, 16.0, 0.05) var glow_energy: float = 2.0:
	set(value):
		glow_energy = value
		_apply()
## Multiplicador para animar (0 = apagado, 1 = normal, >1 = sobrecarga).
@export_range(0.0, 4.0, 0.01) var intensity: float = 1.0:
	set(value):
		intensity = value
		_apply()
## Nodo opcional con las luces (Light3D, a cualquier profundidad) que
## acompanan al brillo.
@export var lights: Node
## Si es true, toma color y energia del material importado en vez de los
## valores de arriba (solo al iniciar).
@export var use_imported_values: bool = false

var _materials: Array[StandardMaterial3D] = []
## Luz -> energia configurada en el editor (la de intensidad 1).
var _light_energy: Dictionary = {}
var _tween: Tween

func _ready() -> void:
	if lights:
		for l: Light3D in lights.find_children("*", "Light3D", true, false):
			_light_energy[l] = l.light_energy
	if target == null:
		return
	for mi: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null or not _wanted(mat):
				continue
			var own := mat.duplicate() as StandardMaterial3D
			own.emission_enabled = true
			mi.set_surface_override_material(s, own)
			_materials.append(own)
			if use_imported_values and _materials.size() == 1:
				glow_color = mat.emission
				glow_energy = mat.emission_energy_multiplier
	if _materials.is_empty():
		push_warning("GlowControl: no encontre materiales emisivos en %s" % target.name)
	_apply()

func _wanted(mat: StandardMaterial3D) -> bool:
	if material_names.is_empty():
		return mat.emission_enabled and mat.emission_energy_multiplier > 0.0
	return mat.resource_name in material_names

func _apply() -> void:
	# Los setters corren al cargar la escena, antes de _ready: ahi todavia no
	# se guardo la energia original de la luz.
	if not is_node_ready():
		return
	for m in _materials:
		m.emission = glow_color
		m.emission_energy_multiplier = glow_energy * intensity
	for l: Light3D in _light_energy:
		l.light_color = glow_color
		l.light_energy = _light_energy[l] * intensity

## Anima la intensidad hasta `to` en `time` segundos.
func fade_to(to: float, time: float) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "intensity", to, time).set_trans(Tween.TRANS_SINE)
	return _tween
