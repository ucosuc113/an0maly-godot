extends RefCounted

# Uso: const PanelIcons = preload("res://scripts/panel_icons.gd")
#
# Simbolos de las palancas (15x9), los mismos que las texturas de las placas,
# para dibujarlos nitidos en la UI. La clave es el nombre de la textura de la
# placa (sin extension): asi el HUD sabe que simbolo lleva cada palanca.

const W := 15
const H := 9

const ICONS := {
	"LateralEnergia": [
		"...............",
		"...............",
		"......###......",
		"#....#...#....#",
		"####.#.#.#.####",
		"#....#...#....#",
		"......###......",
		"...............",
		"...............",
	],
	"DiagonalesEnergia": [
		"##...........##",
		"##...........##",
		"..#...###...#..",
		"...#.#...#.#...",
		".....#.#.#.....",
		"...#.#...#.#...",
		"..#...###...#..",
		"##...........##",
		"##...........##",
	],
	"VentiladoresRefri": [
		".....#####.....",
		"....##..###....",
		"...##..##.##...",
		"...###.#...#...",
		"...#.#####.#...",
		"...#...#.###...",
		"...##.##..##...",
		"....###..##....",
		".....#####.....",
	],
	"LasersRefri": [
		"...#...#...#...",
		"..#..#.#.#..#..",
		".#....###....#.",
		".#.#########.#.",
		".#....###....#.",
		".#...#.#.#...#.",
		".#.....#.....#.",
		"..#.........#..",
		"...#.......#...",
	],
}

## Energia en naranja, refrigeracion en cian.
const COLORS := {
	"LateralEnergia": Color(1.0, 0.52, 0.14),
	"DiagonalesEnergia": Color(1.0, 0.52, 0.14),
	"VentiladoresRefri": Color(0.45, 0.85, 1.0),
	"LasersRefri": Color(0.45, 0.85, 1.0),
}

## Colores de los niveles 1..5 (los de las texturas de las placas).
const LEVEL_COLORS := [
	Color("00cdff"), Color("45ff00"), Color("ffd000"), Color("ff8700"), Color("ff0000"),
]

static func has(icon: String) -> bool:
	return ICONS.has(icon)

## Dibuja el simbolo con la esquina superior izquierda en pos.
static func draw(canvas: CanvasItem, icon: String, pos: Vector2i, color: Color) -> void:
	var rows: Array = ICONS.get(icon, [])
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < row.length():
			if row[x] != "#":
				x += 1
				continue
			# Tramos horizontales en un solo rectangulo.
			var start := x
			while x < row.length() and row[x] == "#":
				x += 1
			canvas.draw_rect(Rect2(pos.x + start, pos.y + y, x - start, 1), color)
