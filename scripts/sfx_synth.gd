extends RefCounted

# Efectos de sonido sintetizados por codigo: no hay archivos de audio en el
# repo. build_all() genera cada sonido una vez como AudioStreamWAV (PCM 16 bits
# mono) listo para un AudioStreamPlayer en el bus SFX.
#
# Familias con caracter distinto:
#   crt_*     terminal vieja: ondas casi cuadradas, clics de rele, estatica.
#   menu_*    menu flotando en la oscuridad: senos suaves con eco, sin aspereza.
#   lights_*  la sala: golpes industriales grandes con reverb de nave.
#
# Todo usa semillas fijas: el mismo codigo suena igual en cada ejecucion.

const SR := 44100

## Todo junto (para herramientas). En el juego, sfx.gd usa los dos grupos.
static func build_all() -> Dictionary:
	var out := build_ui()
	out.merge(build_room())
	return out

## Sonidos del CRT y del menu: rapidos, se generan al iniciar.
## crt_type es un Array con variantes (se elige una al azar en cada tecla
## para que no suene a metralleta).
static func build_ui() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7157
	var out := {
		"crt_click": _wav(crt_click(rng), 0.55),
		"crt_hover": _wav(crt_hover(), 0.18),
		"crt_ok": _wav(crt_ok(), 0.22),
		"crt_power_on": _wav(crt_power_on(rng), 0.7),
		"crt_power_off": _wav(crt_power_off(rng), 0.65),
		"menu_click": _wav(menu_click(rng), 0.45),
		"menu_hover": _wav(menu_hover(), 0.14),
		"menu_appear": _wav(menu_appear(rng), 0.3),
	}
	var types: Array[AudioStreamWAV] = []
	for i in 5:
		types.append(_wav(crt_type(rng), rng.randf_range(0.2, 0.28)))
	out["crt_type"] = types
	return out

## Sonidos de la sala: pesados (reverb larga), sfx.gd los genera en un hilo.
static func build_room() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9203
	return {
		"lights_on": _wav(lights_on(rng), 0.7),
		"lights_boom": _wav(lights_boom(rng), 0.8),
		"fluoro_hum": _wav(fluoro_hum(rng), 0.25, true),
	}

# --- CRT ------------------------------------------------------------------

## Clic de rele seco + bip casi cuadrado corto.
static func crt_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(0.11)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp := _OnePole.new(1500.0)
	var lp := _OnePole.new(5000.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var relay := hp.hp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.0015) * 0.9
		var body := sin(TAU * 2300.0 * t) * exp(-t / 0.006) * 0.4
		var bt := t - 0.004
		var beep := 0.0
		if bt >= 0.0:
			ph += TAU * 1175.0 / SR
			beep = _soft_square(ph, 3.0) * _ad(bt, 0.002, 0.035) * 0.5
		s[i] = relay + body + lp.lp(beep)
	return s

## Tic minimo para el hover sobre la terminal.
static func crt_hover() -> PackedFloat32Array:
	var n := _len(0.035)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := _OnePole.new(4000.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		ph += TAU * 1568.0 / SR
		s[i] = lp.lp(_soft_square(ph, 2.5) * _ad(t, 0.001, 0.008))
	return s

## Tecla/impresora: rafaga de ruido en banda con un clic. Cada llamada sale
## distinta (tono de la banda y clic al azar).
static func crt_type(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	var bp := _Biquad.bandpass(rng.randf_range(2500.0, 4200.0), 1.2)
	var click_f := rng.randf_range(1500.0, 2100.0)
	for i in n:
		var t := float(i) / SR
		var noise := bp.process(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.003) * 1.6
		var click := sin(TAU * click_f * t) * exp(-t / 0.002) * 0.5
		s[i] = noise + click
	return s

## "OK": dos bips cortos ascendentes.
static func crt_ok() -> PackedFloat32Array:
	var n := _len(0.09)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := _OnePole.new(5000.0)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / SR
		ph1 += TAU * 1760.0 / SR
		ph2 += TAU * 2349.0 / SR
		var a := _soft_square(ph1, 2.5) * _ad(t, 0.001, 0.015)
		var b := 0.0
		if t >= 0.032:
			b = _soft_square(ph2, 2.5) * _ad(t - 0.032, 0.001, 0.02)
		s[i] = lp.lp(a + b)
	return s

## Encendido: golpe grave del tubo, chisporroteo de estatica, zumbido de red
## que sube y el pitido agudo del flyback (15.7 kHz) muy bajo.
static func crt_power_on(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(1.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var crackle_hp := _OnePole.new(2000.0)
	var hiss_bp := _Biquad.bandpass(5000.0, 0.7)
	var thunk_ph := 0.0
	for i in n:
		var t := float(i) / SR
		# Golpe: seno que cae de 70 a 38 Hz, saturado suave.
		thunk_ph += TAU * lerpf(70.0, 38.0, minf(t / 0.2, 1.0)) / SR
		var thunk := tanh(1.5 * sin(thunk_ph)) * _ad(t, 0.003, 0.09) * 0.9
		# Chisporroteo: impulsos sueltos, cada vez mas raros.
		var p := 0.05 * exp(-t / 0.12)
		var imp := rng.randf_range(-1.0, 1.0) if rng.randf() < p else 0.0
		var crackle := crackle_hp.hp(imp) * 0.35 * exp(-t / 0.35)
		# Zumbido de red: sube en 0.3 s y queda bajo.
		var hum_env := smoothstep(0.0, 0.3, t) * lerpf(1.0, 0.15, smoothstep(0.3, 1.4, t))
		var hum := (sin(TAU * 60.0 * t) + 0.5 * sin(TAU * 120.0 * t)) * hum_env * 0.12
		# Siseo de carga estatica.
		var hiss_env := smoothstep(0.0, 0.15, t) * exp(-maxf(t - 0.15, 0.0) / 0.5)
		var hiss := hiss_bp.process(rng.randf_range(-1.0, 1.0)) * hiss_env * 0.15
		# Flyback.
		var whine := sin(TAU * 15734.0 * t) * smoothstep(0.1, 0.3, t) * 0.02
		s[i] = thunk + crackle + hum + hiss + whine
	return s

## Apagado: chasquido electrico y barrido descendente (la imagen colapsando
## a un punto), con cola de estatica.
static func crt_power_off(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var sweep_lp := _OnePole.new(3000.0)
	var tail_lp := _OnePole.new(3000.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var snap := rng.randf_range(-1.0, 1.0) * exp(-t / 0.002) \
			+ sin(TAU * 180.0 * t) * exp(-t / 0.02)
		# 900 -> 60 Hz exponencial en 0.35 s.
		var f := 900.0 * pow(60.0 / 900.0, minf(t / 0.35, 1.0))
		ph += TAU * f / SR
		var sweep := sweep_lp.lp(_soft_square(ph, 2.0)) * exp(-t / 0.18) * 0.35
		var tail := tail_lp.lp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.12) * 0.12
		var whine := sin(TAU * 15734.0 * t) * exp(-t / 0.03) * 0.02
		s[i] = snap * 0.8 + sweep + tail + whine
	return s

# --- Menu flotante --------------------------------------------------------

## Clic suave y "espacial": seno con armonicos que cae un poco de tono, y eco
## que se oscurece en cada repeticion.
static func menu_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := _OnePole.new(2000.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 587.0 * (1.0 - 0.06 * (1.0 - exp(-t / 0.05)))
		ph += TAU * f / SR
		var tone := sin(ph) + 0.35 * sin(ph * 1.5) + 0.15 * sin(ph * 2.0)
		var transient := lp.lp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.004) * 0.15
		s[i] = tone * _ad(t, 0.004, 0.18) + transient
	return _echo(s, 0.11, 0.38, 0.9)

## Hover del menu: un roce muy suave hacia arriba.
static func menu_hover() -> PackedFloat32Array:
	var n := _len(0.15)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := lerpf(880.0, 932.0, minf(t / 0.04, 1.0))
		ph += TAU * f / SR
		s[i] = (sin(ph) + 0.2 * sin(ph * 2.0)) * _ad(t, 0.003, 0.035)
	return _echo(s, 0.09, 0.3, 0.35)

## Aparicion del menu: acorde que se abre con destellos, acompanando al logo
## que se materializa (~1.4 s).
static func menu_appear(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs := [220.0, 330.0, 440.0, 554.37, 659.25, 880.0]
	var rates := []
	var offs := []
	for f in freqs:
		rates.append(rng.randf_range(2.0, 5.0))
		offs.append(rng.randf() * TAU)
	var bp := _Biquad.bandpass(800.0, 1.5)
	for i in n:
		var t := float(i) / SR
		var chord := 0.0
		for k in freqs.size():
			# Cada nota con su propio temblor lento: brillo que "respira".
			var trem: float = 0.6 + 0.4 * sin(TAU * rates[k] * t + offs[k])
			chord += sin(TAU * freqs[k] * t) * trem / (1.0 + k * 0.4)
		var env := smoothstep(0.0, 0.8, t) * exp(-maxf(t - 0.8, 0.0) / 0.6)
		# Ruido en banda que barre de 800 a 3000 Hz (el "polvo" del dithering).
		if i % 64 == 0:
			bp.set_bandpass(lerpf(800.0, 3000.0, minf(t / 1.4, 1.0)), 1.5)
		var air := bp.process(rng.randf_range(-1.0, 1.0)) * smoothstep(0.0, 0.5, t) \
			* exp(-maxf(t - 0.5, 0.0) / 0.5) * 0.5
		s[i] = chord * env * 0.35 + air
	return s

# --- Sala -----------------------------------------------------------------

## Encendido de luces industriales: golpe de interruptor grande con arco
## electrico, "tinks" de los balastos mientras los tubos pelean por prender
## (sincronizados con el parpadeo de game_intro.gd: 0.40 y 0.47 s) y el
## zumbido de red que arranca temblando y se asienta.
static func lights_on(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var click_hp := _OnePole.new(3000.0)
	var arc_lp := _OnePole.new(1200.0)
	var tink_bp := _Biquad.bandpass(4500.0, 8.0)
	var buzz_lp := _OnePole.new(1800.0)
	var thump_ph := 0.0
	for i in n:
		var t := float(i) / SR
		# Interruptor: golpe grave + clic metalico + resonancias de la caja.
		thump_ph += TAU * lerpf(90.0, 45.0, minf(t / 0.12, 1.0)) / SR
		var thump := tanh(2.0 * sin(thump_ph)) * _ad(t, 0.002, 0.08)
		var click := click_hp.hp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.003)
		var ring := (sin(TAU * 1800.0 * t) + 0.7 * sin(TAU * 2650.0 * t)) * exp(-t / 0.05) * 0.25
		# Arco: rafaga de ruido grave, el "bang".
		var arc := arc_lp.lp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.12) * 2.2
		# Balastos: dos tinks agudos.
		var tink_in := 0.0
		for at in [0.40, 0.47]:
			if t >= at and t < at + 0.002:
				tink_in += rng.randf_range(-1.0, 1.0) * 6.0
		var tink := tink_bp.process(tink_in)
		# Zumbido: 120 Hz con armonicos, entra en 0.40 s temblando (el
		# parpadeo) y baja a un nivel de fondo.
		var buzz := 0.0
		if t >= 0.40:
			var bt := t - 0.40
			var raw := tanh(3.0 * sin(TAU * 120.0 * t)) + 0.3 * sin(TAU * 240.0 * t)
			var flutter := 1.0 if bt > 0.2 else (0.4 + 0.6 * float(int(bt * 40.0) % 2))
			var env := smoothstep(0.0, 0.03, bt) * lerpf(1.0, 0.35, smoothstep(0.2, 1.2, bt))
			buzz = buzz_lp.lp(raw) * flutter * env * 0.3
		s[i] = thump * 0.9 + click * 0.5 + ring + arc * 0.6 + tink + buzz
	return s

## El PUUMMM: el golpe de un banco de luces industriales encendiendose en una
## nave. Sub-grave que cae, golpe de cuerpo, resonancia metalica del contactor
## y una reverb larga de espacio grande. Suena junto con lights_on (que aporta
## el clic, los tinks y el zumbido).
static func lights_boom(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var hit_lp := _OnePole.new(800.0)
	# Parciales inarmonicos de una pieza grande de metal: suena a maquinaria,
	# no a nota musical.
	var metal := [[173.0, 0.9], [419.0, 0.55], [697.0, 0.35], [1033.0, 0.2]]
	var sub_ph := 0.0
	var body_ph := 0.0
	for i in n:
		var t := float(i) / SR
		# Sub: 60 -> 32 Hz, caida larga, saturado para que se oiga en
		# parlantes chicos (los armonicos llevan el grave).
		sub_ph += TAU * lerpf(60.0, 32.0, smoothstep(0.0, 0.6, t)) / SR
		var sub := tanh(2.5 * sin(sub_ph)) * _ad(t, 0.003, 0.7)
		# Cuerpo: el "PUM" del frente, 110 -> 55 Hz.
		body_ph += TAU * lerpf(110.0, 55.0, minf(t / 0.15, 1.0)) / SR
		var body := sin(body_ph) * _ad(t, 0.002, 0.15)
		# Impacto: ruido grave muy corto.
		var hit := hit_lp.lp(rng.randf_range(-1.0, 1.0)) * exp(-t / 0.03) * 3.0
		var clang := 0.0
		for m in metal:
			clang += sin(TAU * m[0] * t) * exp(-t / m[1]) * 0.12
		clang *= _ad(t, 0.004, 10.0)
		s[i] = sub * 0.85 + body * 0.6 + hit * 0.5 + clang
	# Nave industrial: cola larga y oscura.
	return _reverb(s, 0.45, 1.35, 0.86, 0.35, 2.2)

## Zumbido de fluorescentes en bucle (2 s exactos: 240 ciclos de 120 Hz, el
## bucle no tiene costura). Pensado para sonar bajito de fondo en la sala.
static func fluoro_hum(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _len(2.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := _OnePole.new(1500.0)
	var hiss := _OnePole.new(6000.0)
	# Se sintetiza el doble y se guarda la segunda mitad: los filtros ya estan
	# en regimen, asi el ultimo sample empalma con el primero (sin clic).
	for i in n * 2:
		var t := float(i) / SR
		var raw := tanh(2.5 * sin(TAU * 120.0 * t)) + 0.25 * sin(TAU * 240.0 * t) \
			+ 0.1 * sin(TAU * 360.0 * t)
		# Vaiven lento (1 Hz = 2 ciclos en el bucle) para que no suene muerto.
		var sway := 0.85 + 0.15 * sin(TAU * 1.0 * t)
		var v := lp.lp(raw) * sway + hiss.lp(rng.randf_range(-1.0, 1.0)) * 0.05
		if i >= n:
			s[i - n] = v
	return s

# --- Utilidades -----------------------------------------------------------

static func _len(seconds: float) -> int:
	return int(seconds * SR)

## Envolvente ataque lineal + caida exponencial.
static func _ad(t: float, attack: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)

## Onda casi cuadrada: tanh de un seno. k alto = mas cuadrada y aspera.
static func _soft_square(phase: float, k: float) -> float:
	return tanh(k * sin(phase)) / tanh(k)

## Eco con realimentacion; la cola se agrega al final del buffer.
static func _echo(dry: PackedFloat32Array, delay_s: float, feedback: float,
		tail_s: float) -> PackedFloat32Array:
	var d := int(delay_s * SR)
	var out := dry.duplicate()
	out.resize(dry.size() + int(tail_s * SR))
	var lp := _OnePole.new(2500.0)
	for i in range(d, out.size()):
		out[i] += lp.lp(out[i - d]) * feedback
	return out

## Reverb tipo Schroeder/Freeverb (4 peines con amortiguacion + 2 pasa-todo).
## room_scale alarga los retardos (espacio mas grande), feedback alarga la
## cola, damp la oscurece. La cola se agrega al final del buffer.
static func _reverb(dry: PackedFloat32Array, wet: float, room_scale: float,
		feedback: float, damp: float, tail_s: float) -> PackedFloat32Array:
	# Buffers en variables locales, no en un Array/Dictionary: un Packed*Array
	# guardado dentro de un contenedor se copia entero en cada escritura.
	var n := dry.size() + int(tail_s * SR)
	var input := dry.duplicate()
	input.resize(n)
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	var a0 := PackedFloat32Array()
	var a1 := PackedFloat32Array()
	c0.resize(int(1557 * room_scale))
	c1.resize(int(1617 * room_scale))
	c2.resize(int(1491 * room_scale))
	c3.resize(int(1422 * room_scale))
	a0.resize(int(556 * room_scale))
	a1.resize(int(441 * room_scale))
	var l0 := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var l3 := 0.0
	var inv := 1.0 - damp
	var out := PackedFloat32Array()
	out.resize(n)
	for k in n:
		var x := input[k] * 0.25
		var y0 := c0[k % c0.size()]
		var y1 := c1[k % c1.size()]
		var y2 := c2[k % c2.size()]
		var y3 := c3[k % c3.size()]
		l0 = y0 * inv + l0 * damp
		l1 = y1 * inv + l1 * damp
		l2 = y2 * inv + l2 * damp
		l3 = y3 * inv + l3 * damp
		c0[k % c0.size()] = x + l0 * feedback
		c1[k % c1.size()] = x + l1 * feedback
		c2[k % c2.size()] = x + l2 * feedback
		c3[k % c3.size()] = x + l3 * feedback
		var acc := y0 + y1 + y2 + y3
		var b0 := a0[k % a0.size()]
		a0[k % a0.size()] = acc + b0 * 0.5
		acc = b0 - acc
		var b1 := a1[k % a1.size()]
		a1[k % a1.size()] = acc + b1 * 0.5
		acc = b1 - acc
		out[k] = input[k] + acc * wet
	return out

## Normaliza al pico pedido, suaviza bordes (sin clics) y empaqueta en 16 bits.
## loop: sin fundidos en los bordes y con bucle activado.
static func _wav(samples: PackedFloat32Array, peak: float, loop: bool = false) -> AudioStreamWAV:
	var n := samples.size()
	# Bordes primero: entrada de 8 muestras (0.2 ms, no se come el transiente
	# de los clics) y salida de 5 ms. Despues se normaliza lo que queda.
	if not loop:
		var fade := mini(int(0.005 * SR), n / 4)
		for i in mini(8, n):
			samples[i] *= float(i) / 8.0
		for i in range(n - fade, n):
			samples[i] *= float(n - 1 - i) / fade
	var m := 0.0
	for v in samples:
		m = maxf(m, absf(v))
	var gain := peak / maxf(m, 0.000001)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

## Filtro de un polo: lp() pasa bajos, hp() pasa altos.
class _OnePole:
	var a: float
	var y: float = 0.0

	func _init(cutoff: float) -> void:
		a = 1.0 - exp(-TAU * cutoff / SR)

	func lp(x: float) -> float:
		y += a * (x - y)
		return y

	func hp(x: float) -> float:
		return x - lp(x)

## Biquad (RBJ). Solo pasa banda, que es lo que se usa.
class _Biquad:
	var b0: float
	var b2: float
	var a1: float
	var a2: float
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0

	static func bandpass(freq: float, q: float) -> _Biquad:
		var f := _Biquad.new()
		f.set_bandpass(freq, q)
		return f

	func set_bandpass(freq: float, q: float) -> void:
		var w0 := TAU * freq / SR
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y
