extends Node3D

# Optimizaciones de render que no cambian la imagen (salvo el modo sin sombras):
# - las sombras las proyectan copias estaticas (SHADOWS_ONLY) de las mallas: un
#   material animado o un giro en la malla visible ya no redibuja las sombras
#   de todas las luces cercanas cada frame. Lo que gira sobre su eje (grupo
#   spin_shadow) proyecta la sombra en reposo; lo del grupo still_shadow, la
#   del momento en que se armo.
# - atlas de sombras con los 4 cuadrantes iguales: con tamanos distintos las
#   luces se roban los lugares entre si y se redibujan todas, siempre.
# - luces con energia 0 no existen para el render (igual costaban por pixel).
# - las AreaLight3D sin sombra se reemplazan por una omni calibrada: desde la
#   distancia de la camara aportan lo mismo (el relleno difiere a lo sumo un
#   escalon del dither) y cuestan una fraccion.
# - particulas sin sombra.
# - las pantallas 2D (SubViewport) solo se redibujan si la camara las ve.

const ATLAS_QUADS := Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16

## Luces apagadas fuera del render.
var hide_dark_lights: bool = true
## Sin sombras (calidad media y baja).
var fast: bool = false:
	set(value):
		fast = value
		_apply_shadows()
## Calidad baja: difuso Lambert y sin especular (el shader por luz cuesta ~30%
## menos; la imagen queda apenas mas oscura).
var cheap_lighting: bool = false:
	set(value):
		if cheap_lighting != value:
			cheap_lighting = value
			_apply_cheap()
## Calidad baja: las pantallas 2D se redibujan un frame si y otro no.
var half_rate_screens: bool = false
var _frame: int = 0

## [fuente, copia, modo, nodo que gira, relativo, base en reposo, id de la fuente]
var _pairs: Array = []
var _by_source: Dictionary = {}
var _lights: Array = []
## Luz -> [visible en el arbol, visible para el render]
var _light_state: Dictionary = {}
## AreaLight3D -> su omni de reemplazo.
var _stand_ins: Dictionary = {}
const AREA_OMNI_ENERGY := 0.8
var _screens: Array = []
var _root: Node
var _built: bool = false

enum { FOLLOW, SPIN, STILL }

func _ready() -> void:
	top_level = true
	process_priority = 1000
	_root = get_parent()
	uniform_atlas(_root as SubViewport)
	_build.call_deferred()

static func uniform_atlas(vp: SubViewport) -> void:
	if vp == null:
		return
	for q in 4:
		vp.set_positional_shadow_atlas_quadrant_subdiv(q, ATLAS_QUADS)

func _build() -> void:
	for l: Light3D in _root.find_children("*", "Light3D", true, false):
		_add_light(l)
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		_merge_surfaces(mi)
	for gi: GeometryInstance3D in _root.find_children("*", "GeometryInstance3D", true, false):
		_adopt(gi)
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		if _splittable(mi):
			_split(mi, SPLIT_CELL)
	_build_screen_gates()
	get_tree().node_added.connect(_on_node_added)
	_built = true
	_apply_shadows()
	_apply_cheap()

func _on_node_added(n: Node) -> void:
	if not _root.is_ancestor_of(n) or n.get_parent() == self:
		return
	if n is Light3D:
		_add_light(n)
	elif n is GeometryInstance3D:
		_adopt_later.call_deferred(n)

func _adopt_later(gi: GeometryInstance3D) -> void:
	if is_instance_valid(gi) and gi.is_inside_tree():
		_adopt(gi)

func _adopt(gi: GeometryInstance3D) -> void:
	if gi is CPUParticles3D or gi is GPUParticles3D:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var mi := gi as MeshInstance3D
	if mi == null or _by_source.has(mi.get_instance_id()) or mi.mesh == null or mi.skin != null:
		return
	var cs := mi.cast_shadow
	if mi.has_meta(&"_cs"):
		cs = mi.get_meta(&"_cs")
	if cs == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			or cs == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return
	var proxy := _make_proxy(mi, cs == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
	if proxy == null:
		return
	mi.set_meta(&"_cs", cs)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(proxy)
	proxy.global_transform = mi.global_transform
	proxy.visible = mi.is_visible_in_tree()
	var pair := [mi, proxy, FOLLOW, null, Transform3D(), Transform3D(), mi.get_instance_id()]
	var spinner := _ancestor_in_group(mi, &"spin_shadow")
	if spinner:
		pair[2] = SPIN
		pair[3] = spinner
		pair[4] = spinner.global_transform.affine_inverse() * mi.global_transform
		pair[5] = Transform3D(spinner.basis, Vector3.ZERO)
	elif _ancestor_in_group(mi, &"still_shadow"):
		pair[2] = STILL
	_pairs.append(pair)
	_by_source[mi.get_instance_id()] = proxy

func _ancestor_in_group(n: Node, group: StringName) -> Node3D:
	while n and n != _root:
		if n.is_in_group(group):
			return n as Node3D
		n = n.get_parent()
	return null

var _mat_cache: Dictionary = {}

func _make_proxy(mi: MeshInstance3D, double: bool) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	proxy.mesh = mi.mesh
	proxy.layers = mi.layers
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if mi.material_override:
		proxy.material_override = _static(mi.material_override, double)
		if proxy.material_override == null:
			proxy.free()
			return null
		return proxy
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null:
			continue
		var st := _static(m, double)
		if st == null:
			proxy.free()
			return null
		proxy.set_surface_override_material(s, st)
	return proxy

## Material quieto con la misma silueta de sombra. null si el shader deforma o
## recorta (la silueta no seria la misma).
func _static(m: Material, double: bool) -> Material:
	var key := [m, double]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Material = null
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var plain := b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and b.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and not b.grow
		if plain:
			out = _plain(BaseMaterial3D.CULL_DISABLED if double else b.cull_mode)
		else:
			var d := b.duplicate() as BaseMaterial3D
			d.next_pass = null
			if double:
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
			out = d
	elif m is ShaderMaterial:
		var code: String = (m as ShaderMaterial).shader.code if (m as ShaderMaterial).shader else ""
		var bad := ["discard", "ALPHA", "POSITION", "VERTEX =", "VERTEX +=", "VERTEX *=", "VERTEX -="]
		if not bad.any(func(b: String) -> bool: return b in code):
			var cull := BaseMaterial3D.CULL_BACK
			if double or "cull_disabled" in code:
				cull = BaseMaterial3D.CULL_DISABLED
			elif "cull_front" in code:
				cull = BaseMaterial3D.CULL_FRONT
			out = _plain(cull)
	_mat_cache[key] = out
	return out

func _plain(cull: int) -> StandardMaterial3D:
	var key := ["plain", cull]
	if not _mat_cache.has(key):
		var p := StandardMaterial3D.new()
		p.cull_mode = cull
		_mat_cache[key] = p
	return _mat_cache[key]

## Mallas grandes y quietas: se parten en trozos para que cada uno reciba solo
## las luces que lo alcanzan. Fuera de su alcance una luz suma exactamente 0,
## asi que la imagen no cambia; lo que cambia es que el shader deja de recorrer
## las 23 luces del exterior en cada pixel de la pared.
const SPLIT_MIN_SIZE := 2.5
const SPLIT_CELL := 1.5

func _splittable(mi: MeshInstance3D) -> bool:
	if not mi.mesh is ArrayMesh or mi.skin != null or mi.layers == 0 or mi.get_parent() == self:
		return false
	if _ancestor_in_group(mi, &"spin_shadow") or _ancestor_in_group(mi, &"still_shadow"):
		return false
	var n: Node = mi
	while n and n != _root:
		if n is CollisionObject3D or n.has_meta(&"no_split"):
			return false
		n = n.get_parent()
	var box: AABB = mi.global_transform * mi.get_aabb()
	return box.get_longest_axis_size() >= SPLIT_MIN_SIZE

func _split(mi: MeshInstance3D, cell: float) -> void:
	var xf := mi.global_transform
	## celda -> superficie -> [vertices originales usados, indices remapeados]
	var cells := {}
	var count := 0
	for s in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		for t in range(0, idx.size(), 3):
			var c := xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
			var key := Vector3i((c / cell).floor())
			if not cells.has(key):
				cells[key] = {}
				count += 1
			var per: Dictionary = cells[key]
			if not per.has(s):
				per[s] = [{}, PackedInt32Array(), arrays, mi.mesh.surface_get_format(s)]
			var entry: Array = per[s]
			var remap: Dictionary = entry[0]
			for k in 3:
				var v := idx[t + k]
				if not remap.has(v):
					remap[v] = remap.size()
				entry[1].append(remap[v])
	if count < 2:
		return
	for key in cells:
		var mesh := ArrayMesh.new()
		var mats: Array[Material] = []
		for s in cells[key]:
			var entry: Array = cells[key][s]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _sub_arrays(entry[2], entry[0], entry[1]), [], {},
				_custom_flags(entry[3]))
			mats.append(mi.get_active_material(s))
		var piece := MeshInstance3D.new()
		piece.name = "Split"
		piece.mesh = mesh
		for i in mats.size():
			piece.set_surface_override_material(i, mats[i])
		piece.layers = mi.layers
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.gi_mode = mi.gi_mode
		mi.add_child(piece)
	mi.layers = 0

## Superficies de una malla cuyos materiales solo difieren en el albedo se
## fusionan en una (el color viaja por vertice): un draw en vez de varios, y en
## calidad alta cada draw se repite por cada luz con sombra que la toca.
const MERGED_SHADER = preload("res://shaders/merged_albedo.gdshader")

func _merge_surfaces(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mi.skin != null or mi.material_override or mesh.get_surface_count() < 2 \
			or mesh.get_blend_shape_count() > 0 or not _marked(mi, &"merge_surfaces"):
		return
	var groups := {}
	for s in mesh.get_surface_count():
		if mi.get_surface_override_material(s) or mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES \
				or _has_lods(mesh, s):
			continue
		var key := _merge_key(mesh.surface_get_material(s) as StandardMaterial3D)
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(s)
	var merged := {}
	for key in groups:
		if groups[key].size() > 1:
			for s in groups[key]:
				merged[s] = key
	if merged.is_empty():
		return
	var added := []
	for key in groups:
		if groups[key].size() < 2:
			continue
		var arrays := _concat(mesh, groups[key])
		if arrays.is_empty():
			return
		added.append([arrays, _merged_material(mesh.surface_get_material(groups[key][0]) as StandardMaterial3D)])
	# Copia exacta (compresion y LOD incluidos) sin las superficies fundidas.
	var out := mesh.duplicate() as ArrayMesh
	var overrides: Array[Material] = []
	for s in mesh.get_surface_count():
		if not merged.has(s):
			overrides.append(mi.get_surface_override_material(s))
	var gone: Array = merged.keys()
	gone.sort()
	gone.reverse()
	for s in gone:
		out.surface_remove(s)
	for a in added:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a[0], [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.surface_set_material(out.get_surface_count() - 1, a[1])
		overrides.append(null)
	# La shadow mesh importada tiene las superficies viejas: con otro orden
	# Godot leeria indices de otra geometria.
	out.shadow_mesh = null
	mi.mesh = out
	for i in overrides.size():
		mi.set_surface_override_material(i, overrides[i])

func _marked(n: Node, meta: StringName) -> bool:
	while n and n != _root:
		if n.has_meta(meta):
			return true
		n = n.get_parent()
	return false

func _merge_key(m: StandardMaterial3D) -> String:
	if m == null or m.get_class() != "StandardMaterial3D" or m.next_pass:
		return ""
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.albedo_texture or m.roughness_texture \
			or m.metallic_texture or m.normal_enabled or m.rim_enabled or m.clearcoat_enabled \
			or m.anisotropy_enabled or m.ao_enabled or m.heightmap_enabled or m.subsurf_scatter_enabled \
			or m.backlight_enabled or m.refraction_enabled or m.detail_enabled or m.grow \
			or m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return ""
	if m.emission_enabled and (m.emission_energy_multiplier != 0.0 or m.emission_texture):
		return ""
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or m.cull_mode != BaseMaterial3D.CULL_BACK \
			or m.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or m.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX \
			or m.disable_receive_shadows or m.disable_ambient_light or m.disable_fog or m.no_depth_test \
			or m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY or m.shadow_to_opacity \
			or m.use_point_size or m.fixed_size or m.render_priority != 0:
		return ""
	return "%s|%s|%s" % [m.roughness, m.metallic, m.metallic_specular]

func _merged_material(m: StandardMaterial3D) -> ShaderMaterial:
	var key := ["merged", m.roughness, m.metallic, m.metallic_specular]
	if not _mat_cache.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = MERGED_SHADER
		sm.set_shader_parameter("roughness", m.roughness)
		sm.set_shader_parameter("metallic", m.metallic)
		sm.set_shader_parameter("specular", m.metallic_specular)
		_mat_cache[key] = sm
	return _mat_cache[key]

## Une las superficies (mismo formato) y guarda el albedo lineal de cada una
## en CUSTOM0. [] si los formatos no coinciden.
func _concat(mesh: ArrayMesh, surfaces: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()
	var base := 0
	for s in surfaces:
		var a := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if (a[k] == null) != (out[k] == null) and s != surfaces[0]:
				return []
			if a[k] == null:
				continue
			if out[k] == null:
				out[k] = a[k].duplicate()
			else:
				out[k].append_array(a[k])
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		var c := m.albedo_color.srgb_to_linear()
		var colors: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null and m.vertex_color_use_as_albedo else PackedColorArray()
		var start := custom.size()
		custom.resize(start + verts.size() * 4)
		for i in verts.size():
			var v := c
			if not colors.is_empty():
				var vc := colors[i]
				if m.vertex_color_is_srgb:
					vc = vc.srgb_to_linear()
				v = Color(c.r * vc.r, c.g * vc.g, c.b * vc.b)
			custom[start + i * 4] = v.r
			custom[start + i * 4 + 1] = v.g
			custom[start + i * 4 + 2] = v.b
			custom[start + i * 4 + 3] = 1.0
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				indices.append(base + i)
		else:
			for i in idx:
				indices.append(base + i)
		base += verts.size()
	out[Mesh.ARRAY_CUSTOM0] = custom
	out[Mesh.ARRAY_INDEX] = indices
	return out

## Con LOD no se funde: la superficie unida no podria elegir el mismo nivel
## que cada original (se vio en el cabezal de los laseres).
func _has_lods(mesh: ArrayMesh, s: int) -> bool:
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
	return not (d.get("lods", []) as Array).is_empty()

## Solo los bits de formato de los canales CUSTOM (el resto lo deduce Godot).
func _custom_flags(format: int) -> int:
	var out := 0
	for c in 4:
		var shift := Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS
		out |= format & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
	return out

func _sub_arrays(src: Array, remap: Dictionary, indices: PackedInt32Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var order := PackedInt32Array()
	order.resize(remap.size())
	for v in remap:
		order[remap[v]] = v
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX or src[a] == null:
			continue
		var data = src[a]
		var width := 1
		if a == Mesh.ARRAY_TANGENT:
			width = 4
		elif a >= Mesh.ARRAY_CUSTOM0 and a <= Mesh.ARRAY_CUSTOM3 and data is PackedFloat32Array:
			width = data.size() / (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		elif a >= Mesh.ARRAY_CUSTOM0 or a == Mesh.ARRAY_BONES or a == Mesh.ARRAY_WEIGHTS:
			continue
		var dst = data.duplicate()
		dst.resize(order.size() * width)
		for i in order.size():
			for w in width:
				dst[i * width + w] = data[order[i] * width + w]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = indices
	return out

func _add_light(l: Light3D) -> void:
	if l in _lights or l.has_meta(&"stand_in"):
		return
	_lights.append(l)
	if l is AreaLight3D and not l.shadow_enabled:
		var o := OmniLight3D.new()
		o.set_meta(&"stand_in", true)
		o.light_specular = 0.0
		o.omni_range = (l as AreaLight3D).area_range
		o.omni_attenuation = (l as AreaLight3D).area_attenuation
		o.light_cull_mask = l.light_cull_mask
		add_child(o)
		_stand_ins[l] = o
	if not l.has_meta(&"_shadow"):
		l.set_meta(&"_shadow", l.shadow_enabled)
	l.shadow_enabled = l.shadow_enabled and not fast

func _apply_shadows() -> void:
	if not _built:
		return
	for l in _lights:
		if is_instance_valid(l):
			l.shadow_enabled = bool(l.get_meta(&"_shadow")) and not fast

## [viewport, notifier, modo pedido por su dueno, ultimo modo puesto aca]
func _build_screen_gates() -> void:
	for vp: SubViewport in _root.find_children("*", "SubViewport", true, false):
		if not vp.disable_3d:
			continue
		var anchor := vp.get_parent()
		while anchor and not anchor is Node3D:
			anchor = anchor.get_parent()
		if anchor == null or anchor == _root:
			continue
		var inv := (anchor as Node3D).global_transform.affine_inverse()
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in anchor.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = inv * mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		var notifier := VisibleOnScreenNotifier3D.new()
		notifier.aabb = box.grow(0.05)
		anchor.add_child(notifier)
		var mode := vp.render_target_update_mode
		_screens.append([vp, notifier, mode, mode])

func _process(_delta: float) -> void:
	_update_lights()
	_update_proxies()
	_update_screens()

func _update_lights() -> void:
	for i in range(_lights.size() - 1, -1, -1):
		if not is_instance_valid(_lights[i]):
			_lights.remove_at(i)
			continue
		var l: Light3D = _lights[i]
		var vis := l.is_visible_in_tree()
		var on := vis and (l.light_energy > 0.001 or not hide_dark_lights)
		if _stand_ins.has(l):
			var o: OmniLight3D = _stand_ins[l]
			o.global_transform = l.global_transform
			o.light_color = l.light_color
			o.light_energy = l.light_energy * AREA_OMNI_ENERGY
			o.visible = on
			on = false
		var id := l.get_instance_id()
		var st: Array = _light_state.get(id, [true, true])
		if st[0] != vis or st[1] != on:
			_light_state[id] = [vis, on]
			RenderingServer.instance_set_visible(l.get_instance(), on)

func _update_proxies() -> void:
	for i in range(_pairs.size() - 1, -1, -1):
		var pair: Array = _pairs[i]
		var proxy: MeshInstance3D = pair[1]
		if not is_instance_valid(pair[0]):
			proxy.queue_free()
			_by_source.erase(pair[6])
			_pairs.remove_at(i)
			continue
		var src: MeshInstance3D = pair[0]
		var v := src.is_visible_in_tree()
		if proxy.visible != v:
			proxy.visible = v
		if not v or pair[2] == STILL:
			continue
		var t: Transform3D
		if pair[2] == SPIN:
			var spinner: Node3D = pair[3]
			var rest: Transform3D = pair[5]
			rest.origin = spinner.position
			t = spinner.get_parent_node_3d().global_transform * rest * pair[4]
		else:
			t = src.global_transform
		if proxy.global_transform != t:
			proxy.global_transform = t

func _update_screens() -> void:
	_frame += 1
	for i in _screens.size():
		var g: Array = _screens[i]
		var vp: SubViewport = g[0]
		if not is_instance_valid(vp):
			continue
		var cur := vp.render_target_update_mode
		# UPDATE_ONCE vuelve solo a DISABLED despues de dibujar: eso es nuestro.
		var ours: bool = cur == g[3] or (g[3] == SubViewport.UPDATE_ONCE and cur == SubViewport.UPDATE_DISABLED)
		if not ours:
			g[2] = cur
		var want: int = g[2] if (g[1] as VisibleOnScreenNotifier3D).is_on_screen() \
				else SubViewport.UPDATE_DISABLED
		if half_rate_screens and want == SubViewport.UPDATE_ALWAYS:
			want = SubViewport.UPDATE_ONCE if (_frame + i) % 2 == 0 else SubViewport.UPDATE_DISABLED
		if cur != want:
			vp.render_target_update_mode = want
		g[3] = want

var _cheap_shader: Shader

func _apply_cheap() -> void:
	if not _built:
		return
	if _cheap_shader == null:
		_cheap_shader = Shader.new()
		_cheap_shader.code = MERGED_SHADER.code.replace("diffuse_burley, specular_schlick_ggx",
			"diffuse_lambert, specular_disabled")
	var seen := {}
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.get_parent() == self:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or seen.has(m):
				continue
			seen[m] = true
			var sm := m as ShaderMaterial
			if sm and (sm.shader == MERGED_SHADER or sm.shader == _cheap_shader):
				sm.shader = _cheap_shader if cheap_lighting else MERGED_SHADER
				continue
			var b := m as StandardMaterial3D
			if b == null or b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
					or b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if cheap_lighting:
				if not b.has_meta(&"_modes"):
					b.set_meta(&"_modes", [b.diffuse_mode, b.specular_mode])
				b.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				b.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			elif b.has_meta(&"_modes"):
				var modes: Array = b.get_meta(&"_modes")
				b.diffuse_mode = modes[0]
				b.specular_mode = modes[1]
				b.remove_meta(&"_modes")
