# Música de AN∅MALY: leitmotivs, síntesis y progresión del OST

Este documento define la identidad musical propia del juego. El tema
principal, `assets/Musica/Anomaly_Tema.ogg`, dura 60 s y está hecho
**100 % por síntesis de sonido**: no usa samples ni grabaciones. Su código
fuente está en `music/`.

```
python3 music/generar_tema.py                     # assets/Musica/Anomaly_Tema.ogg
python3 music/generar_tema.py --stems music/capas # + las tres capas por separado
python3 music/figuras.py                          # figuras de docs/musica/
```

Requiere `numpy`, `numba` y `ffmpeg` (más `matplotlib` y `soundfile` solo para
las figuras). La semilla es fija, así que el mismo código siempre genera el
mismo archivo. La carpeta `music/` tiene un `.gdignore` y Godot no la importa.

---

## 1. Punto de partida

### La música actual del menú

`assets/MenuMusic.ogg` es de *Portal Reloaded*. Analizada por espectro y
croma, tiene estas características:

| Rasgo | Medición |
|---|---|
| Tonalidad | La menor, con G# muy presente |
| Tempo | ~100 BPM |
| Bajo | pedal casi constante en A1 |
| Arriba | arpegios con apoyaturas cromáticas |
| Espectro | 90 % de la energía entre 250 Hz y 4 kHz, casi nada sobre 4 kHz |

### Qué es "Portal 2" (Mike Morasky) y qué evitamos

La primera versión del tema usaba una armonía funcional (Am–F–Dm–E7), un
bajo de lamento cromático y un cierre que volvía a la tónica. Eso suena a
música de película *épica/emotiva*: cuando crece se vuelve alegre y cuando
baja cae en el cliché de "cerrar el bucle". Portal 2 trabaja de otra forma:

| Portal 2 | Lo que **no** hace |
|---|---|
| **Células** de 3 a 5 notas repetidas como ostinato, no melodías largas | frases cantables de 8 compases |
| **Compases impares** (7/8, 5/4) y polimetría (capas que se desfasan) | 4/4 cuadrado |
| **Procesos aditivos**: el patrón se arma nota por nota | entradas "de golpe" |
| Armonía **estática o simétrica** (pedales, tritonos, terceras menores, escala octatónica) | cadencias IV–V–I, progresiones pop |
| Secuenciadores **bitcrushed**, compuertas rítmicas, sidechain, tartamudeos | sonido limpio y sostenido |
| Finales por **falla**: freno de cinta, corte, apagado | resolución en la tónica |

Ese es el lenguaje del tema nuevo.

---

## 2. El acorde ANOMALÍA y los dos leitmotivs

> Revisado con los skills `mc-workflow`, `mc-development` y `mc-melody`.
> La hoja de especificación completa (intent, forma, material, arreglo,
> mezcla y las 20 verificaciones) está en
> [`musica/ARR-SPEC_anomaly_tema.yaml`](musica/ARR-SPEC_anomaly_tema.yaml).

![leitmotivs](musica/leitmotivs.png)

La armonía de todo el OST gira alrededor de cuatro notas:

```
ANOMALÍA = { A, E, A#, D# }   = dos tritonos entrelazados  (A–D#)  (E–A#)
```

No es un acorde mayor ni menor y no admite cadencia. Los dos leitmotivs usan
esas cuatro notas como **esqueleto**, pero ya **no son el acorde arpegiado**.
La versión anterior (`A4 E5 A#5 D#6`) eran tres saltos seguidos en la misma
dirección que sumaban una octava y un tritono. `mc-melody` §3.1 lo marca como
antinatural e imposible de recordar: era un acorde, no una melodía.

### I. LA INSTALACIÓN

```
A4  E5  D#5  E5  A#4  A4        intervalos  +7  -1  +1  -6  -1
2   2   1    1   3    5         semicorcheas = un compás de 7/8
└a1┘    └─a2─┘   └──a3──┘
```

| Parte | Qué es | Qué representa |
|---|---|---|
| **a1** A4→E5 | quinta ascendente | orden, estructura |
| **a2** D#5–E5 | bordado de semitono (D# es el tritono de A) | el **temblor** de la máquina |
| **a3** E5→A#4→A4 | cae un tritono y amortigua medio tono | la máquina **se corrige sola** y aterriza en casa |

- **Octava central A4–A5.** Cada salto tiene rebote (a1 → a2) o amortiguación
  (a3), como pide `mc-melody` §3.3. Nunca hay dos saltos seguidos.
- **Timbre:** dos pulsos estrechos desafinados con bitcrush de 6 a 7 bits,
  sin vibrato.

**I? (la pregunta):** `A4 E5 D#5 E5 A5 A#5`. Cambia el final: la cola sube
y se queda en **A#5**, sin resolver (§2.1: un final ascendente es una
pregunta). Se **responde en el clímax**: A#5 → A5 (§8.3: una distorsión
tiene que recibir respuesta).

### II. EL AGUJERO NEGRO

```
E5  A#4  A4  D#4  D4            intervalos  -6  -1  -6  -1
6   4    8   6    18            semicorcheas = tres compases
└──a3──┘ └──a3 una quinta abajo──┘
```

- Es **a3, la cola de I, en aumentación y secuenciada una quinta abajo**
  (`mc-development`: fragment + sequence + augment). La caída con la que la
  instalación se corrige se repite sin encontrar fondo: cada amortiguación
  es el comienzo de la caída siguiente.
- **Termina en D4, fuera del acorde ANOMALÍA**: la gravedad la sacó del
  sistema.
- Las caídas largas empiezan en notas largas y aterrizan por semitono
  (§3.2: así se escribe un salto descendente amplio).
- **Timbre:** sierras con portamento. Va 40 ms **detrás del pulso** (la
  gravedad la retiene) y la última nota se corre al rojo.

**La relación entre los dos:** II no es "otro tema"; es el gesto con el que I
se corrige (a3), pero sin final. Quien escuchó I reconoce II.

### Transformaciones (`music/sintesis/leitmotivs.py`, clase `Motif`)

| Transformación | Uso dramático |
|---|---|
| `INSTALACION_Q` (cambio de final) | la pregunta que queda abierta |
| `TEMBLOR` (a2) recortado y secuenciado | la escalada: la máquina tiembla cada vez más rápido y más agudo |
| `rhythm([1,1,1,1,1,1])` (disminución) | pánico en el COLAPSO |
| a3 aumentado y secuenciado | II |
| `transpose(-1)` sobre II | la espiral: cada vuelta cae un semitono más |
| `head(4).augment(2)` | el reinicio fallido: no llega a la caída |

---

## 3. El tema principal: forma y armonía

Negra = 120. Compás de **7/8 (2+2+3)** de 1.75 s. Son 32 compases (56 s) más
4 s de reinicio y cola.

**Armonía:** solo triadas menores sobre **A, C, D#, F#** (las cuatro
rotaciones de la escala octatónica) y el acorde ANOMALÍA. Se mueve por
terceras menores y tritonos y no hay ninguna cadencia.

![forma](musica/forma.png)

| Compases | Sección | Armonía | Qué pasa |
|---|---|---|---|
| 1-4 | **1 ARRANQUE** | Am (pedal) | **Proceso aditivo**: el secuenciador arma la célula nota por nota (A, después A-E, después A-E-A#, después las cuatro). Zumbido del reactor, ventilación, relés y un servo. |
| 5-12 | **2 PRUEBA** | Am · Cm/A · **D#m/A** | Batería en 2+2+3 con bajo saturado; el colchón pasa por una compuerta rítmica. Melodía: I · (aire) · I? · (aire) · I · traba (el temblor se repite y no aterriza). Entre frases contesta el secuenciador. Tartamudeo al final. |
| 13-20 | **3 ESCALADA** | Am → Cm → D#m → F#m (el bajo **sube por terceras menores**) | El **temblor** a2 se recorta y se secuencia (G5-F#5, después A#5-A5, después A5 repetida en el agudo), apoyado en una nota distinta de cada acorde. No es transporte paralelo, que `mc-melody` §8.1 marca como predecible. Entran pitidos con un periodo de 5 contra el compás de 14. **El compás 20 no tiene melodía.** |
| 21-26 | **4 HORIZONTE** | ANOMALÍA, **curvándose** | **Todo se curva un semitono hacia abajo** (colchón, zumbido, granos, secuenciador, melodía). II en espiral: una vez y otra un semitono más abajo. El secuenciador se **dilata** (cada paso dura 4 % más). Solo un bombo grave cada dos compases. |
| 27-30 | **5 COLAPSO** | Am ↔ D#m/A cada compás | **Clímax en el compás 27 (76 % del tema = 3/4):** A#5 durante un compás entero, la nota más aguda, larga y fuerte, que **responde a la pregunta** bajando a A5. Después, I en disminución contra II una octava abajo. Tartamudeos en cadena. |
| 31-32 | **6 APAGADO** | ANOMALÍA | A E D# y la E5 queda sonando mientras **la cinta frena**. Silencio. **Reinicio** en aumentación: A… E… D#… E… y la caída nunca llega. Un pitido. Fin. |

No vuelve a la tónica ni cierra un bucle: la instalación **falla**. Si se
usa en bucle en el menú, el empalme es un apagado seguido de un arranque,
que tiene sentido narrativo, pero no es un loop invisible.

---

## 4. Síntesis: las capas de abstracción

```
capa 5  mezcla/master    generar_tema.py       reverb por capa, ediciones glitch, glue, limitador
capa 4  composición      sintesis/partitura    forma, armonía, compuertas, tartamudeos, freno
capa 3  instrumentos     sintesis/instrumentos patches con carácter fijo
capa 2  voz              (instrumentos)        oscilador + envolvente + filtro + modulación
capa 1  generadores      (instrumentos)        unísono, FM, aditiva, granular
capa 0  DSP              sintesis/dsp.py       PolyBLEP, SVF TPT, ladder, FDN, beat repeat, tape stop
teoría                   sintesis/leitmotivs   motivos como datos y sus transformaciones
```

### Las tres capas musicales

**Textura** (`music/capas/capa_textura.ogg`):
- *Zumbido del reactor*: síntesis aditiva de 11 parciales de A1 con deriva
  propia. En el horizonte se curva junto con todo lo demás.
- *Ventilación*: ruido rosa por un pasabanda que barre.
- *Nube granular*: granos de una campana FM en las notas de ANOMALÍA. En el
  horizonte caen una octava y se estiran.
- *Relés* (clics FM y ruido), *servos* (pulso barrido con temblor de motor),
  *remolinos invertidos* antes de ESCALADA y COLAPSO, y el barrido del
  horizonte de sucesos.

**Acompañamiento** (`capa_acompanamiento`):
- *Secuenciador*: la célula I como ostinato de 14 pasos (4+4+6), con pulso,
  PWM, golpe de filtro, bitcrush, ratchets y eco ping-pong.
- *Pitidos*: senos con chirp en un polímetro de 5 contra 14.
- *Colchón*: siete sierras por nota con compuerta rítmica y sidechain.
- *Bajo*: cuadrada más sierra saturadas por un ladder de 24 dB.
- *Batería*: bombo de seno con caída, caja de ruido crujiente, hi-hats FM y
  golpes metálicos FM (razón √2).

**Melodía** (`capa_melodia`): el lead *Aperture* (I) y la voz del agujero
negro (II).

Los cortes glitch (*beat repeat* con roll) y el freno de cinta se aplican
igual a las tres capas, así que siguen sincronizadas por separado.

---

## 5. Progresión musical del OST (hoja de ruta)

Todo el OST cuenta la misma historia con las mismas cuatro notas: **I manda
al principio, II lo va invadiendo y el final decide qué queda.** Cada pista
nueva debería respetar el 7/8 (o 7/16) y la armonía octatónica.

| Momento del juego | Pista (actual → propuesta) | Centro | Leitmotivs | Recursos |
|---|---|---|---|---|
| **Menú** | MenuMusic → **Anomaly_Tema** | A | I y II completos; resume el juego | todo |
| **Sala / fondo** | BackgroundMusic | A (pedal) | solo el proceso aditivo de I, muy lento, sin batería | zumbido, relés, servos |
| **Fase 1** | (sin pista) | A | la traba (el temblor D#–E repetido sin aterrizar) como señal de alerta | lead solo |
| **Fase 2: Interfacing** | Interfacing | A → C | I en ostinato y rotaciones (como PRUEBA y ESCALADA) | batería 2+2+3, compuerta |
| **Fase 3: Singularity** | Singularity | D# (tritono) | II domina; la curvatura del HORIZONTE | dilatación, granos al rojo |
| **Meltdown** | KineticEnergy | A ↔ D# | COLAPSO: I en disminución contra II | beat repeat, bitcrush 6 bits |
| **Final: contención** | — | A | I completo y **sin temblor** (A E E A# A): la máquina ya no duda; I? recibe su respuesta en A | lead limpio, sin bitcrush |
| **Final: colapso** | — | — | freno de cinta y silencio, sin reinicio | tape stop |
| **Final: ambiguo** | — | A | el reinicio (A E D# E…) se repite y nunca llega a la caída | reinicio en bucle |

Reglas para escribir pistas nuevas:

1. **Sin cadencias.** Nada de IV–V–I ni de bajos de lamento. Se mueve por
   terceras menores (A–C–D#–F#) y tritonos.
2. **I nunca se desafina** salvo cuando II lo alcanza (HORIZONTE) o cuando la
   cinta frena.
3. **II siempre se desliza**: nada de II sin portamento.
4. **Crecer = escalar por terceras menores, sumar capas y apretar la
   compuerta.** Nunca pasar a mayor.
5. **Bajar = curvar la afinación o dilatar el tiempo.** Nunca usar una línea
   descendente "de cierre".
6. Las pistas terminan por **falla** (tartamudeo, freno, corte), no por
   resolución.

---

## 6. Integración en el juego

El archivo está en `assets/Musica/Anomaly_Tema.ogg`. Para que reemplace la
música actual del menú, hay que cambiar el `ext_resource` `15_menumusic` de
`main.tscn` (o asignar el stream al nodo `Music` desde el editor). El master
queda en unos −16 dBFS RMS con picos de −1 dBFS, unos 2 dB por debajo de
`MenuMusic.ogg`, así que `base_volume_db` en `scripts/music.gd` puede pasar
de −14 a unos −12 dB.
