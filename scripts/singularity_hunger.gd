extends Node

# El agujero negro reacciona con el mundo durante el derretimiento
# (lo maneja crisis_director.gd):
#
#   shockwave(fuerza)   onda expansiva desde el horizonte, en el plano del
#                       disco. Al pasar por cada cosa la golpea: lasers que
#                       chispean, aspas que se sacuden, luces que parpadean,
#                       monitores con interferencia, la camara tiembla...
#   devour(cosa)        se traga un laser, un aspa o una luz: primero cruje y
#                       suelta chispas, luego se arranca y cae en espiral
#                       hacia el horizonte, estirandose y encogiendose.
#   tear_part(laser)    NO se lo traga entero: le arranca UNA pieza. Las de
#                       arriba salen en cualquier orden y el cuerpo (Inferior)
#                       siempre al final, porque ahi vive el nucleo. Con la
#                       primera pieza el laser deja de disparar.
#   tear_blade(aspa)    lo mismo con un aspa suelta de los ventiladores.
#   restore_all()       si el jugador estabiliza, todo vuelve a su sitio.
#
# Antes de arrancar algo, el agujero negro tira de la pieza unos segundos: si
# hay `prompts` (clamp_prompts.gd), ese tiron se convierte en un anclaje de
# emergencia y el jugador puede salvarla clicandola a tiempo.
#
# Lo que se traga es una COPIA de las mallas; el original solo se oculta, asi
# restaurar es volver a mostrarlo.

const WAVE_SHADER = preload("res://shaders/shockwave.gdshader")

@export var black_hole: Node3D
@export var views: Node
@export var shield: Node3D
@export var lighting: Node
@export var outside: Node
## FanSpinner (fan_spinner.gd).
@export var fans: Node
@export var lasers: Array[Node] = []
## Monitores (info_monitor.gd).
@export var monitors: Array[Node] = []
## clamp_prompts.gd: los anclajes de emergencia (opcional).
@export var prompts: Node
## Padre de las luces del exterior.
@export var outside_lights: Node3D
@export var flash: ColorRect
@export var sfx: Node
@export var settings: Node
@export_group("Onda")
@export var wave_radius: float = 7.0
@export var wave_time: float = 1.9
@export var wave_color: Color = Color(1.0, 0.35, 0.25)

## Lo que ya se trago: [{node, restore: Callable}]
var _devoured: Array = []
## Copias en vuelo (se liberan al llegar o al restaurar).
var _flying: Array[Node3D] = []
## Piezas de las que esta tirando ahora mismo (todavia se pueden salvar).
var _pending: Array = []
## Sube con cada restore_all(): los tirones en curso se dan por cancelados.
var _generation: int = 0

# --- Onda expansiva ------------------------------------------------------------------

func shockwave(strength: float = 1.0) -> void:
	if black_hole == null:
		return
	var center := black_hole.global_position
	var normal := _disc_normal()
	var wave_seed := randf() * 100.0
	_play("shockwave", linear_to_db(clampf(0.35 + strength * 0.5, 0.2, 1.0)), randf_range(0.9, 1.1))

	var ring := _wave_mesh(PlaneMesh.new(), 0, strength, wave_seed)
	(ring.mesh as PlaneMesh).size = Vector2(2.0, 2.0)
	var shell := _wave_mesh(SphereMesh.new(), 1, strength * 0.7, wave_seed)
	var sphere := shell.mesh as SphereMesh
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var up := normal
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var ring_basis := Basis(side, up, side.cross(up))
	var t := create_tween().set_parallel()
	t.tween_method(func(x: float) -> void:
		var r := _wave_r(x)
		var fade := pow(1.0 - x, 1.5) * strength
		ring.global_transform = Transform3D(ring_basis.scaled(Vector3(r, 1.0, r)), center)
		shell.global_transform = Transform3D(Basis().scaled(Vector3.ONE * r), center)
		(ring.material_override as ShaderMaterial).set_shader_parameter("intensity", fade * 2.2)
		(shell.material_override as ShaderMaterial).set_shader_parameter("intensity", fade * 0.9),
		0.0, 1.0, wave_time)
	t.chain().tween_callback(func() -> void:
		ring.queue_free()
		shell.queue_free())

	if shield and shield.visible:
		shield.ripple(-normal)
		shield.flash(0.4 * strength)
	# Cada cosa recibe el golpe cuando el frente la alcanza.
	for l in lasers:
		if not alive(l):
			continue
		_at_radius(center, (l as Node3D).global_position, func() -> void:
			l.pulse(1.2 * strength)
			l.spark(strength))
	if fans:
		for mi in fans.blade_meshes():
			if _is_devoured(mi):
				continue
			_at_radius(center, mi.global_position, func() -> void:
				fans.rattle(mi, strength))
	for light in _lights():
		if _is_devoured(light):
			continue
		_at_radius(center, light.global_position, func() -> void:
			_light_hit(light, strength))
	var cam: Camera3D = views.camera if views else null
	if cam:
		_at_radius(center, cam.global_position, func() -> void:
			_room_hit(strength))

## Radio del frente para el avance x (0..1): sale disparado y frena.
func _wave_r(x: float) -> float:
	return wave_radius * (1.0 - pow(1.0 - x, 3.0))

## Llama a `what` cuando el frente llega a `pos`.
func _at_radius(center: Vector3, pos: Vector3, what: Callable) -> void:
	var d := center.distance_to(pos)
	if d >= wave_radius:
		return
	var x := 1.0 - pow(1.0 - d / wave_radius, 1.0 / 3.0)
	get_tree().create_timer(x * wave_time, false).timeout.connect(what)

func _wave_mesh(mesh: PrimitiveMesh, mode: int, strength: float, wave_seed: float) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = WAVE_SHADER
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("color", wave_color)
	mat.set_shader_parameter("intensity", strength)
	mat.set_shader_parameter("seed", wave_seed)
	mat.render_priority = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.layers = 1 | 2
	mi.extra_cull_margin = wave_radius * 2.0
	add_child(mi)
	return mi

func _light_hit(light: Light3D, strength: float) -> void:
	var e := light.light_energy
	var t := create_tween()
	t.tween_property(light, "light_energy", e * (1.0 + 2.0 * strength), 0.04)
	t.tween_property(light, "light_energy", e * 0.1, 0.08)
	t.tween_property(light, "light_energy", e, 0.2)
	_burst(light.global_position, int(10 + 20 * strength), 1.2, Color(1.0, 0.85, 0.5))

## La onda cruza la sala.
func _room_hit(strength: float) -> void:
	views.shake(0.006 + 0.014 * strength, 0.45)
	if lighting:
		lighting.flicker(strength)
	for m in monitors:
		if m.get("screen"):
			m.screen.glitch(clampf(strength, 0.3, 1.0))
	if flash and not _calm() and not flash.visible:
		flash.visible = true
		flash.color = Color(1.0, 0.4, 0.3, 0.16 * strength)
		var t := create_tween()
		t.tween_property(flash, "color:a", 0.0, 0.35)
		t.tween_callback(func() -> void:
			if flash.color.a <= 0.001:
				flash.visible = false)

# --- Tragar -------------------------------------------------------------------------

func is_devoured(node: Node) -> bool:
	return _is_devoured(node)

func _is_devoured(node: Node) -> bool:
	for d in _devoured:
		if d.node == node:
			return true
	return false

## Siguiente laser sin tragar, en el orden de `order` (indices de `lasers`).
func next_laser(order: Array) -> Node:
	for i in order:
		if i < lasers.size() and alive(lasers[i]):
			return lasers[i]
	return null

## Sigue en pie: ni tragado entero ni sin cuerpo.
func alive(l: Node) -> bool:
	return l != null and not _is_devoured(l) and not bool(l.get("dead"))

## Sigue disparando (no le falta ninguna pieza).
func operational_lasers() -> int:
	var n := 0
	for l in lasers:
		if alive(l) and l.operational():
			n += 1
	return n

## Laser al que le toca perder una pieza. `spread` reparte el dano entre
## todos (empieza por los mas enteros); si no, remata a los mas rotos.
func next_torn_laser(spread: bool) -> Node:
	var left: Array = lasers.filter(func(l: Node) -> bool:
		return alive(l) and _next_part(l) != null)
	if left.is_empty():
		return null
	left.sort_custom(func(a: Node, b: Node) -> bool:
		return a.torn < b.torn if spread else a.torn > b.torn)
	# Entre los que empatan, uno al azar (si no, siempre cae el mismo).
	var best: int = left[0].torn
	var tied: Array = left.filter(func(l: Node) -> bool: return l.torn == best)
	return tied.pick_random()

func next_blade() -> Node3D:
	if fans == null:
		return null
	for mi: Node3D in fans.blade_meshes():
		if not _is_devoured(mi) and not (mi in _pending):
			return mi
	return null

## Luces del exterior sin tragar, la mas cercana al agujero primero.
func next_lights(count: int) -> Array:
	var out: Array = []
	var center := black_hole.global_position
	var left := _lights().filter(func(l: Light3D) -> bool: return not _is_devoured(l))
	left.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		return a.global_position.distance_to(center) < b.global_position.distance_to(center))
	for l in left:
		if out.size() >= count:
			break
		out.append(l)
	return out

func devour_laser(l: Node, fall_time: float = 2.2) -> void:
	if not alive(l):
		return
	var beam: float = l.beam_intensity
	_devoured.append({"node": l, "restore": func() -> void: l.restored(beam)})
	l.set_beam(0.0, 0.25)
	await _groan(l as Node3D, func() -> void:
		l.pulse(1.5)
		l.spark(1.0))
	if not _is_devoured(l):
		return
	var copy := _copy_meshes(l as Node3D)
	var glow := OmniLight3D.new()
	glow.light_color = l.light_color.lerp(Color(1.0, 0.2, 0.25), 0.6)
	glow.light_energy = 1.8
	glow.omni_range = 1.4
	glow.light_cull_mask = 2
	copy.add_child(glow)
	l.swallowed()
	_fall(copy, fall_time, 2.5)

# --- Desarmar (una pieza por vez) ----------------------------------------------------

## El agujero negro tira de una pieza de `l` durante `window` segundos y se la
## arranca, salvo que el jugador la reenganche (anclaje de emergencia).
## Devuelve true si se la llevo.
func tear_part(l: Node, window: float = 0.0, fall_time: float = 2.0) -> bool:
	if not alive(l):
		return false
	var part: Node3D = _next_part(l)
	if part == null:
		return false
	var gen := _generation
	_pending.append(part)
	var prompt: Node = prompts.open(part, window, l.light_color) if _can_prompt(window) else null
	# El temblor corre en paralelo al aviso: dura exactamente lo que la ventana.
	_shudder(part, window, func() -> void:
		l.pulse(1.1)
		l.spark(0.7), gen)
	var saved: bool = await _wait_prompt(prompt, window)
	_pending.erase(part)
	if gen != _generation or not is_instance_valid(part) or not is_instance_valid(l):
		return false
	if saved:
		l.clamp_part(part)
		_burst((part as Node3D).global_position, 14, 1.1, Color(0.65, 0.95, 1.0))
		return false

	# Se la lleva. El cuerpo es la ultima: ahi el laser queda muerto.
	var body: bool = part == l.body_part()
	_devoured.append({"node": part, "restore": func() -> void: l.restore_part(part)})
	var copy := _copy_meshes(part)
	l.tear_off(part)
	var glow := OmniLight3D.new()
	glow.light_color = l.light_color.lerp(Color(1.0, 0.25, 0.25), 0.55)
	glow.light_energy = 1.6
	glow.omni_range = 1.1
	glow.light_cull_mask = 2
	copy.add_child(glow)
	_burst((part as Node3D).global_position, 26 if body else 16, 1.6, Color(1.0, 0.8, 0.5))
	if views:
		views.shake(0.012 if body else 0.007, 0.35)
	_fall(copy, fall_time, 5.0 if not body else 2.5)
	return true

## Un aspa suelta, con la misma ventana de rescate.
func tear_blade(mi: Node3D, window: float = 0.0, fall_time: float = 1.8) -> bool:
	if mi == null or fans == null or _is_devoured(mi) or mi in _pending:
		return false
	var gen := _generation
	_pending.append(mi)
	var prompt: Node = prompts.open(mi, window, Color(0.7, 0.85, 1.0)) if _can_prompt(window) else null
	_shudder(mi, window, func() -> void: fans.rattle(mi, 1.2), gen)
	var saved: bool = await _wait_prompt(prompt, window)
	_pending.erase(mi)
	if gen != _generation or not is_instance_valid(mi):
		return false
	if saved:
		fans.rattle(mi, 0.3)
		_play("laser_lock", -6.0, randf_range(1.1, 1.25))
		_burst(mi.global_position, 12, 1.0, Color(0.65, 0.95, 1.0))
		return false
	_devoured.append({"node": mi, "restore": func() -> void: fans.set_blade_active(mi, true)})
	var copy := _copy_meshes(mi)
	fans.set_blade_active(mi, false)
	_burst(mi.global_position, 18, 1.8, Color(1.0, 0.8, 0.5))
	_fall(copy, fall_time, 6.0)
	return true

## Siguiente pieza de `l`: una suelta al azar y, cuando no quedan, el cuerpo.
func _next_part(l: Node) -> Node3D:
	var loose: Array = []
	for pt: Node3D in l.loose_parts():
		if _free_part(pt):
			loose.append(pt)
	if not loose.is_empty():
		return loose.pick_random()
	var body: Node3D = l.body_part()
	return body if _free_part(body) else null

func _free_part(pt: Node3D) -> bool:
	return pt != null and pt.visible and not _is_devoured(pt) and not (pt in _pending)

func _can_prompt(window: float) -> bool:
	return prompts != null and window > 0.0

## Espera a que el jugador resuelva el aviso (o a que se acabe la ventana).
func _wait_prompt(prompt: Node, window: float) -> bool:
	if prompt == null:
		await get_tree().create_timer(window, false).timeout
		return false
	return await prompt.resolved

## Tiron: la pieza se sacude cada vez mas fuerte mientras se puede salvar.
## Corre en paralelo al aviso y no limpia el temblor al terminar: de eso se
## encargan tear_off() (se la llevaron) o clamp_part() (la salvaron).
func _shudder(node: Node3D, seconds: float, sparks: Callable, gen: int) -> void:
	_play("metal_groan", -4.0, randf_range(0.85, 1.15))
	var holder: Node = node.get_parent()
	var can_shake: bool = holder != null and holder.has_method("shake_part")
	var unit: float = holder.local_unit() if can_shake else 1.0
	var steps := maxi(int(seconds / 0.05), 1)
	for i in steps:
		if not is_instance_valid(node) or gen != _generation or not (node in _pending):
			return
		var k := float(i) / steps
		if can_shake:
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			holder.shake_part(node, off * 0.013 * (0.25 + k) / unit)
		if i % 5 == 0:
			sparks.call()
		await get_tree().create_timer(0.05, false).timeout

# --- Tragar entero -------------------------------------------------------------------

func devour_blade(mi: Node3D, fall_time: float = 1.8) -> void:
	if mi == null or _is_devoured(mi):
		return
	_devoured.append({"node": mi, "restore": func() -> void: fans.set_blade_active(mi, true)})
	fans.rattle(mi, 1.5)
	await _groan(mi, func() -> void: fans.rattle(mi, 1.0))
	if not _is_devoured(mi):
		return
	var copy := _copy_meshes(mi)
	fans.set_blade_active(mi, false)
	_fall(copy, fall_time, 6.0)

func devour_light(light: Light3D, fall_time: float = 1.6) -> void:
	if light == null or _is_devoured(light):
		return
	_devoured.append({"node": light, "restore": func() -> void: light.visible = true})
	# La luz se aferra: parpadea, y sale arrancada como un orbe.
	var e := maxf(light.light_energy, 0.4)
	var t := create_tween()
	for f in [2.5, 0.2, 1.8, 0.1, 3.0]:
		t.tween_property(light, "light_energy", e * f, 0.06)
	await t.finished
	if not _is_devoured(light):
		return
	var orb := Node3D.new()
	orb.top_level = true
	add_child(orb)
	orb.global_position = light.global_position
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	sphere.radial_segments = 8
	sphere.rings = 4
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = light.light_color.lerp(Color.WHITE, 0.5)
	ball.material_override = mat
	ball.layers = 1 | 2
	orb.add_child(ball)
	var glow := OmniLight3D.new()
	glow.light_color = light.light_color
	glow.light_energy = e * 3.0
	glow.omni_range = maxf((light as OmniLight3D).omni_range, 1.0) if light is OmniLight3D else 1.5
	glow.light_cull_mask = light.light_cull_mask
	orb.add_child(glow)
	light.visible = false
	light.light_energy = e
	_burst(orb.global_position, 24, 1.5, light.light_color.lerp(Color.WHITE, 0.4))
	_play("spark", -6.0, randf_range(0.7, 1.0))
	_fall(orb, fall_time, 3.0)

## Cualquier otra pieza (el cristal del ventanal, un monitor...): cruje,
## se arranca y cae. No se restaura (solo pasa en el climax).
func devour_prop(node: Node3D, fall_time: float = 2.4, rip_sound: String = "") -> void:
	if node == null or _is_devoured(node):
		return
	_devoured.append({"node": node, "restore": func() -> void: node.visible = true})
	await _groan(node, func() -> void:
		_burst(node.global_position, 18, 1.4, Color(1.0, 0.8, 0.5)))
	if not _is_devoured(node):
		return
	var copy := _copy_meshes(node)
	# Brillo propio: en la sala a oscuras la pieza se perderia.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.3)
	glow.light_energy = 1.5
	glow.omni_range = 1.2
	glow.light_cull_mask = 1 | 2
	copy.add_child(glow)
	node.visible = false
	if node is CollisionObject3D:
		(node as CollisionObject3D).input_ray_pickable = false
	if rip_sound != "":
		_play(rip_sound, 0.0, randf_range(0.85, 1.0))
	_burst(node.global_position, 40, 2.0, Color(1.0, 0.85, 0.6))
	if views:
		views.shake(0.015, 0.4)
	_fall(copy, fall_time, 1.5)

func restore_all() -> void:
	# Los tirones en curso se dan por cancelados y los avisos se cierran.
	_generation += 1
	_pending.clear()
	if prompts:
		prompts.clear()
	for l in lasers:
		if l and l.has_method("clear_shakes"):
			l.clear_shakes()
	for n in _flying:
		if is_instance_valid(n):
			n.queue_free()
	_flying.clear()
	var i := 0
	for d in _devoured:
		var node: Node = d.node
		var restore: Callable = d.restore
		get_tree().create_timer(0.25 * i, false).timeout.connect(func() -> void:
			restore.call()
			if is_instance_valid(node) and node is Node3D:
				_burst((node as Node3D).global_position, 20, 1.0, Color(0.5, 0.9, 1.0))
				_play("monitor_on", -8.0, randf_range(0.8, 1.1)))
		i += 1
	_devoured.clear()

# --- Piezas ---------------------------------------------------------------------

## Crujido previo: la pieza tiembla cada vez mas, con chispas.
func _groan(node: Node3D, sparks: Callable) -> void:
	_play("metal_groan", -2.0, randf_range(0.85, 1.15))
	var rest := node.position
	var steps := 18
	for i in steps:
		if not is_instance_valid(node) or not _is_devoured(node):
			return
		var k := float(i) / steps
		node.position = rest + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012 * (0.3 + k) / maxf(node.global_basis.get_scale().x, 0.001)
		if i % 6 == 0:
			sparks.call()
		await get_tree().create_timer(0.05, false).timeout
	if is_instance_valid(node):
		node.position = rest

## Copia estatica de las mallas visibles de `src`, en el mismo lugar.
func _copy_meshes(src: Node3D) -> Node3D:
	var list: Array = []
	if src is MeshInstance3D:
		list.append(src)
	list.append_array(src.find_children("*", "MeshInstance3D", true, false))
	list = list.filter(func(mi: MeshInstance3D) -> bool:
		return not mi.top_level and mi.is_visible_in_tree() and mi.mesh != null)
	# Pivote en el centro de la malla, no en el origen del modelo (que puede
	# quedar lejos): asi gira sobre si misma y cae desde donde se ve.
	var box := AABB()
	for i in list.size():
		var mi: MeshInstance3D = list[i]
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if i == 0 else box.merge(b)
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_transform = Transform3D(src.global_basis, box.get_center() if not list.is_empty() else src.global_position)
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in list:
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.material_override = mi.material_override
		for s in mi.get_surface_override_material_count():
			c.set_surface_override_material(s, mi.get_surface_override_material(s))
		c.layers = mi.layers
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(c)
		c.transform = inv * mi.global_transform
	return root

## Caida en espiral hacia el horizonte: acelera, gira sobre si misma, se
## estira hacia el centro y se encoge hasta desaparecer.
func _fall(node: Node3D, time: float, spin: float) -> void:
	_flying.append(node)
	var trail := _trail()
	node.add_child(trail)
	var center := black_hole.global_position
	var normal := _disc_normal()
	var start := node.global_transform
	var offset := start.origin - center
	var tumble := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	# Lo lejano casi no gira al principio: si no, a varios metros la espiral lo
	# saca de cuadro. El giro se concentra al final, cerca del horizonte.
	var turns := clampf(1.4 / maxf(offset.length(), 0.5), 0.12, 1.6) * randf_range(0.9, 1.2) 			* (1.0 if randf() < 0.5 else -1.0)
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		if not is_instance_valid(node):
			return
		var k := u * u
		var ang := u * u * u * TAU * turns
		var pos := center + offset.rotated(normal, ang) * (1.0 - k)
		var size := lerpf(1.0, 0.02, pow(u, 1.6))
		# Estiramiento hacia el centro (espaguetizacion).
		var to_c := (center - pos)
		var stretch := 1.0 + 1.8 * k
		var rot := Basis(tumble, u * spin * TAU * 0.5 + k * spin * TAU)
		var b := rot * start.basis
		b = Basis.from_scale(Vector3.ONE * size) * b
		if to_c.length() > 0.001:
			# Escala mayor sobre el eje que apunta al centro.
			var along := Basis(Quaternion(Vector3.UP, to_c.normalized()))
			b = along * Basis.from_scale(Vector3(1.0, stretch, 1.0)) * along.inverse() * b
		node.global_transform = Transform3D(b, pos), 0.0, 1.0, time).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func() -> void:
		_play("devour", -1.0, randf_range(0.9, 1.1))
		_burst(center, 40, 2.2, Color(1.0, 0.6, 0.35))
		if views:
			views.shake(0.008, 0.3)
		for l in lasers:
			l.pulse(0.8)
		_flying.erase(node)
		if is_instance_valid(node):
			node.queue_free())

## Desintegracion (apagado de emergencia): el horizonte NO se encoge ni se
## apaga ni se agranda. Revienta en fragmentos que salen disparados en todas
## direcciones y se quedan flotando, porque esto pasa en el vacio y no hay
## nada que los frene ni que los haga caer. Se llama varias veces, cada vez
## mas fuerte, hasta que la nube tapa lo que quedaba.
func disintegrate(strength: float = 1.0, color: Color = Color(1.0, 0.6, 0.25)) -> void:
	if black_hole == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.88
	p.amount = maxi(int(140.0 * strength), 12)
	p.lifetime = 4.5 + 3.5 * strength
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(black_hole.sphere_radius * 1.15, 0.02)
	# Sin direccion: salen radiales desde la esfera de emision.
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.2 * strength
	p.initial_velocity_max = 1.5 * strength
	p.gravity = Vector3.ZERO
	p.damping_min = 0.1
	p.damping_max = 0.45
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 2.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.color_ramp = _spark_ramp(color)
	p.mesh = _shard_quad()
	p.layers = 1 | 2
	p.top_level = true
	add_child(p)
	p.global_position = black_hole.global_position
	p.emitting = true
	get_tree().create_timer(p.lifetime + 1.0, false).timeout.connect(p.queue_free)
	_play("shockwave", linear_to_db(clampf(0.35 + strength * 0.35, 0.2, 1.0)),
		randf_range(0.55, 0.75))

var _shard: QuadMesh

## Los fragmentos son mas grandes que las chispas: se tienen que leer como
## pedazos del horizonte, no como polvo.
func _shard_quad() -> QuadMesh:
	if _shard == null:
		_shard = QuadMesh.new()
		_shard.size = Vector2(0.06, 0.06)
		_shard.material = _spark_quad().material
	return _shard

func _trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	p.color_ramp = _spark_ramp(Color(1.0, 0.7, 0.4))
	p.mesh = _spark_quad()
	p.layers = 1 | 2
	return p

func _burst(pos: Vector3, amount: int, speed: float, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(amount, 1)
	p.lifetime = 0.7
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -2.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _spark_ramp(color)
	p.mesh = _spark_quad()
	p.layers = 1 | 2
	p.top_level = true
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3, false).timeout.connect(p.queue_free)

var _ramps: Dictionary = {}

func _spark_ramp(color: Color) -> Gradient:
	if _ramps.has(color):
		return _ramps[color]
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.9))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.3, color)
	_ramps[color] = g
	return g

var _quad: QuadMesh

func _spark_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_quad.material = mat
		_quad.size = Vector2(0.025, 0.025)
	return _quad

# --- Utilidades -----------------------------------------------------------------

func _lights() -> Array:
	if outside_lights == null:
		return []
	return outside_lights.find_children("*", "Light3D", true, false)

func _disc_normal() -> Vector3:
	var tilt: Vector3 = black_hole.disc_tilt_degrees
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(tilt.y), deg_to_rad(tilt.z)))
	return (black_hole.global_basis * b.y).normalized()

func _calm() -> bool:
	return settings != null and bool(settings.get_value("reduce_flashing"))

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
