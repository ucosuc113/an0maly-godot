extends Node

# Agujero negro vivo: despues de nacer (fase 3) su aspecto sigue al estado del
# reactor (reactor_sim.gd), suavizado:
#
#   masa del nucleo      -> tamano del horizonte y curvatura de la luz
#   saturacion del disco -> tamano y opacidad del disco
#   temperatura          -> color (rojo -> naranja -> blanco azulado) y brillo
#   giro                 -> efecto doppler y velocidad del disco
#   inestabilidad        -> turbulencia, filamentos y bamboleo del disco
#   desalineacion        -> inclinacion que oscila
#
# Durante el nacimiento lo anima phase_three.gd directamente (alive = false);
# alive = true le pasa el control a la simulacion.

@export var black_hole: Node3D
@export var sim: Node
## Donde aparece (el centro del escudo).
@export var anchor: Node3D
## Rapidez con la que el aspecto sigue a la simulacion (1/s).
@export var follow: float = 1.2

var alive: bool = false
var _time: float = 0.0
var _base_tilt: Vector3

func _ready() -> void:
	if black_hole:
		_base_tilt = black_hole.disc_tilt_degrees
		black_hole.visible = false

## Lo coloca en el centro del escudo, apagado y diminuto.
func prepare() -> void:
	if anchor:
		black_hole.global_position = anchor.global_position
	black_hole.sphere_radius = 0.0005
	black_hole.disc_radius = 0.02
	black_hole.disc_opacity = 0.0
	black_hole.disc_brightness = 0.0
	black_hole.visible = true

func _process(delta: float) -> void:
	if not alive or black_hole == null or sim == null:
		return
	_time += delta
	var k := 1.0 - exp(-follow * delta)
	var inst: float = sim.instability
	var mass: float = sim.core_mass
	var sat: float = clampf(sim.disc_saturation / 100.0, 0.0, 1.0)
	var heat: float = clampf(sim.disc_temp / 90000.0, 0.0, 1.0)
	var melt: float = sim.meltdown
	var ice: float = sim.frozen
	var spin: float = clampf(sim.core_spin / 800000.0, 0.0, 1.0)

	var bh := black_hole
	var sphere := clampf(0.03 * (1.0 + 0.12 * log(1.0 + mass)), 0.022, 0.07) * (1.0 + melt * 0.4)
	bh.sphere_radius = lerpf(bh.sphere_radius, sphere, k)
	var disc := (0.36 + 0.14 * sat + 0.03 * sin(_time * 7.0) * inst) * (1.0 + melt * 1.0)
	bh.disc_radius = lerpf(bh.disc_radius, disc, k)
	# En el derretimiento el disco se acerca al horizonte y se vuelve denso.
	bh.disc_inner_ratio = lerpf(bh.disc_inner_ratio, 2.6 - 0.8 * melt, k)
	bh.disc_falloff = lerpf(bh.disc_falloff, 1.0 - 0.3 * melt, k)
	bh.disc_opacity = lerpf(bh.disc_opacity, 0.3 + 0.2 * sat + 0.6 * melt, k)
	# Curvatura acotada: muy alta, casi todos los rayos caen al horizonte y el
	# disco desaparece.
	bh.bend_strength = lerpf(bh.bend_strength, 1.3 + 0.3 * clampf(mass / 50.0, 0.0, 1.0), k)

	# Color por temperatura: rojo -> naranja -> blanco azulado.
	var cold := Color(0.9, 0.18, 0.04).lerp(Color(1.0, 0.55, 0.12), heat)
	cold = cold.lerp(Color(0.55, 0.7, 1.0), smoothstep(0.7, 1.0, heat))
	var hot := Color(1.0, 0.82, 0.55).lerp(Color(0.9, 0.96, 1.0), heat)
	# Derretimiento: blanco hirviendo con bordes rojo violeta.
	cold = cold.lerp(Color(1.0, 0.1, 0.35), melt)
	hot = hot.lerp(Color(1.0, 1.0, 0.95), melt)
	# Congelamiento: hielo.
	cold = cold.lerp(Color(0.55, 0.85, 1.0), ice)
	hot = hot.lerp(Color(0.95, 1.0, 1.0), ice)
	bh.disc_color_cold = bh.disc_color_cold.lerp(cold, k)
	bh.disc_color_hot = bh.disc_color_hot.lerp(hot, k)
	var flicker := 1.0 + inst * 0.35 * sin(_time * 23.0) * sin(_time * 9.0)
	bh.disc_brightness = lerpf(bh.disc_brightness,
		(1.4 + 1.6 * heat + inst * 1.5 + melt * 0.6) * flicker * (1.0 - ice * 0.6), k)

	bh.doppler_strength = lerpf(bh.doppler_strength, 0.2 + 0.6 * spin, k)
	bh.swirl_speed = lerpf(bh.swirl_speed, (0.7 + sim.disc_spin / 20000.0) * (1.0 - ice), k)
	bh.turbulence = lerpf(bh.turbulence, 0.6 + 0.4 * inst, k)
	# Contraste y ancho van juntos: subir el contraste con brazos finos (0.1)
	# deja la densidad en cero y el disco se deshace en jirones. Con el
	# derretimiento el disco se vuelve denso y solido.
	var fil: float = maxf(inst, melt)
	bh.filament_contrast = lerpf(bh.filament_contrast, 0.5 + 1.5 * fil, k)
	bh.filament_width = lerpf(bh.filament_width, 0.1 + 0.6 * fil, k)

	var wobble: float = (sim.core_misalign / 40.0 + inst * 6.0 + melt * 10.0) * (1.0 - ice)
	# Al derretirse el disco se inclina hacia la sala: se ve de frente, no de canto.
	bh.disc_tilt_degrees = _base_tilt + Vector3(20.0, 0.0, 6.0) * melt + Vector3(sin(_time * 1.3), 0.0, cos(_time * 0.9)) * wobble
