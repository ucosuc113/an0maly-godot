extends Node3D

# Optimizaciones de render que no cambian la imagen (salvo el modo FAST):
# - mallas con material animado (TIME) invalidan cada frame las sombras que
#   tocan: proyecta por ellas una copia estatica.
# - luces con energia 0 van sin sombra.
# - las pantallas 2D (SubViewport) solo se redibujan si la camara las ve.

## Modo FAST: ninguna luz proyecta sombra.
var fast: bool = false

var _pairs: Array = []
var _lights: Array[Light3D] = []
var _screens: Array = []

func _ready() -> void:
	top_level = true
	_build.call_deferred()

func _build() -> void:
	var root := get_parent()
	for l: Light3D in root.find_children("*", "Light3D", true, false):
		if l.shadow_enabled:
			_lights.append(l)
	_build_proxies(root)
	_build_screen_gates(root)

func _build_proxies(root: Node) -> void:
	var cache := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
				or mi.mesh == null or mi.skin != null:
			continue
		if not _uses_animated(mi):
			continue
		var double := mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		var proxy := MeshInstance3D.new()
		proxy.mesh = mi.mesh
		proxy.layers = mi.layers
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var ok := true
		if mi.material_override:
			proxy.material_override = _static(mi.material_override, double, cache)
			ok = proxy.material_override != null
		else:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m == null:
					continue
				var st := _static(m, double, cache)
				if st == null:
					ok = false
					break
				proxy.set_surface_override_material(s, st)
		if not ok:
			proxy.free()
			continue
		add_child(proxy)
		proxy.global_transform = mi.global_transform
		proxy.visible = mi.is_visible_in_tree()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pairs.append([mi, proxy])

## [viewport, notifier, modo pedido por su dueno, ultimo modo puesto aca]
func _build_screen_gates(root: Node) -> void:
	for vp: SubViewport in root.find_children("*", "SubViewport", true, false):
		if not vp.disable_3d:
			continue
		var anchor := vp.get_parent()
		while anchor and not anchor is Node3D:
			anchor = anchor.get_parent()
		if anchor == null or anchor == root:
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
	for l in _lights:
		if is_instance_valid(l):
			var on := l.light_energy > 0.001 and not fast
			if l.shadow_enabled != on:
				l.shadow_enabled = on
	for i in range(_pairs.size() - 1, -1, -1):
		var src: MeshInstance3D = _pairs[i][0]
		var proxy: MeshInstance3D = _pairs[i][1]
		if not is_instance_valid(src):
			proxy.queue_free()
			_pairs.remove_at(i)
			continue
		var v := src.is_visible_in_tree()
		if proxy.visible != v:
			proxy.visible = v
		if v:
			var t := src.global_transform
			if proxy.global_transform != t:
				proxy.global_transform = t
	for g in _screens:
		var vp: SubViewport = g[0]
		if not is_instance_valid(vp):
			continue
		var cur := vp.render_target_update_mode
		if cur != g[3]:
			g[2] = cur
		var want: int = g[2] if (g[1] as VisibleOnScreenNotifier3D).is_on_screen() \
				else SubViewport.UPDATE_DISABLED
		if cur != want:
			vp.render_target_update_mode = want
		g[3] = want

func _uses_animated(mi: MeshInstance3D) -> bool:
	if _animated(mi.material_override) or _animated(mi.material_overlay):
		return true
	for s in mi.mesh.get_surface_count():
		if _animated(mi.get_active_material(s)):
			return true
	return false

func _animated(m: Material) -> bool:
	while m:
		var sm := m as ShaderMaterial
		if sm and sm.shader and "TIME" in sm.shader.code:
			return true
		m = m.next_pass
	return false

## null si el shader deforma o recorta (la silueta no seria la misma).
func _static(m: Material, double: bool, cache: Dictionary) -> Material:
	var key := [m, double]
	if cache.has(key):
		return cache[key]
	var out: Material = null
	if m is BaseMaterial3D:
		var d := m.duplicate() as BaseMaterial3D
		d.next_pass = null
		if double:
			d.cull_mode = BaseMaterial3D.CULL_DISABLED
		out = d
	elif m is ShaderMaterial:
		var code: String = (m as ShaderMaterial).shader.code if (m as ShaderMaterial).shader else ""
		var bad := ["discard", "ALPHA", "POSITION", "VERTEX =", "VERTEX +=", "VERTEX *=", "VERTEX -="]
		if not bad.any(func(b: String) -> bool: return b in code):
			var d := StandardMaterial3D.new()
			if double or "cull_disabled" in code:
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
			elif "cull_front" in code:
				d.cull_mode = BaseMaterial3D.CULL_FRONT
			out = d
	cache[key] = out
	return out
