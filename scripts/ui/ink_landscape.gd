extends Control
## Procedural placeholder art. Deterministic motion never touches gameplay RNG.

const BASE_SIZE := Vector2(1280, 720)
const GOLD := Color("b5a375")
const JADE := Color("527d69")
var elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	AppSettings.reduced_motion_changed.connect(_on_motion_changed)
	_on_motion_changed(AppSettings.reduced_motion)


func _on_motion_changed(enabled: bool) -> void:
	set_process(not enabled)
	if enabled:
		elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / BASE_SIZE)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), Color("0c1919"))
	# Quiet, layered silhouettes in place of a raster background.
	for layer in range(3):
		var points := PackedVector2Array([Vector2(0, 720)])
		for x in range(0, 1301, 20):
			var height := 482.0 + layer * 60.0
			height += sin(x * 0.008 + layer * 1.3) * 58.0
			height += sin(x * 0.019 + layer) * 19.0
			points.append(Vector2(x, height))
		points.append(Vector2(1300, 720))
		draw_colored_polygon(points, Color(0.075 + layer * 0.012, 0.14 + layer * 0.014, 0.135 + layer * 0.01, 1))
	# Fine border and left editorial rule.
	draw_rect(Rect2(24, 24, 1232, 672), Color(0.52, 0.57, 0.43, 0.22), false, 1)
	draw_line(Vector2(598, 138), Vector2(598, 604), Color(0.52, 0.57, 0.43, 0.18), 1)
	var center := Vector2(916, 346)
	for radius in [208.0, 218.0, 245.0]:
		draw_arc(center, radius, 0, TAU, 144, Color(0.55, 0.59, 0.43, 0.12), 1, true)
	for index in range(48):
		var angle := TAU * index / 48.0
		var inner := 218.0 if index % 4 == 0 else 224.0
		draw_line(center + Vector2.from_angle(angle) * inner, center + Vector2.from_angle(angle) * 230, Color(0.63, 0.63, 0.43, 0.3), 1, true)
	# Grounding shadow, ember bowl and the old bronze cauldron.
	draw_set_transform(Vector2(916, 531) * size / BASE_SIZE, 0, Vector2(1.0, 0.17) * size / BASE_SIZE)
	draw_circle(Vector2.ZERO, 145, Color(0.015, 0.035, 0.03, 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, size / BASE_SIZE)
	for index in range(5):
		draw_circle(Vector2(916, 493), 55.0 - index * 8.0, Color(0.7, 0.39, 0.13, 0.025))
	_poly([Vector2(822, 427), Vector2(808, 514), Vector2(827, 520), Vector2(853, 454)], Color("426255"))
	_poly([Vector2(975, 448), Vector2(1005, 520), Vector2(1024, 514), Vector2(1007, 427)], Color("426255"))
	var bowl := PackedVector2Array([Vector2(795, 322), Vector2(1037, 322), Vector2(1024, 411), Vector2(995, 456), Vector2(958, 476), Vector2(875, 476), Vector2(836, 456), Vector2(808, 411)])
	draw_colored_polygon(bowl, Color("31564a"))
	draw_polyline(bowl, GOLD.darkened(0.3), 2, true)
	_poly([Vector2(803, 330), Vector2(823, 409), Vector2(853, 443), Vector2(869, 451), Vector2(850, 404), Vector2(845, 330)], Color(0.39, 0.56, 0.43, 0.3))
	draw_arc(Vector2(785, 360), 39, 1.0, 5.15, 40, GOLD.darkened(0.2), 10, true)
	draw_arc(Vector2(1047, 360), 39, -2.0, 2.1, 40, GOLD.darkened(0.2), 10, true)
	_poly([Vector2(789, 309), Vector2(1043, 309), Vector2(1043, 325), Vector2(789, 325)], Color("a99c70"))
	_poly([Vector2(806, 299), Vector2(1026, 299), Vector2(990, 278), Vector2(842, 278)], Color("4c6c57"))
	draw_line(Vector2(806, 300), Vector2(1026, 300), GOLD, 3, true)
	draw_circle(Vector2(916, 271), 13, GOLD.darkened(0.12))
	# Inlaid seal and bronze bands.
	draw_arc(Vector2(916, 395), 32, 0, TAU, 64, GOLD.darkened(0.1), 1.5, true)
	_poly([Vector2(916, 375), Vector2(932, 395), Vector2(916, 415), Vector2(900, 395)], GOLD)
	draw_line(Vector2(838, 441), Vector2(994, 441), GOLD.darkened(0.35), 2, true)
	# Smoke ribbons and sparks follow fixed paths, even after returning to the menu.
	for ribbon in range(3):
		var smoke := PackedVector2Array()
		for step in range(40):
			var y := 251.0 - step * 3.5
			var x := 895.0 + ribbon * 22.0 + sin(step * 0.17 + elapsed * 0.45 + ribbon) * 11.0
			smoke.append(Vector2(x, y))
		draw_polyline(smoke, Color(0.61, 0.75, 0.59, 0.14 - ribbon * 0.025), 2.0, true)
	for index in range(16):
		var phase := fposmod(index * 0.618 + elapsed * 0.04, 1.0)
		var point := Vector2(785 + fposmod(index * 71.0, 255), 500 - phase * 340)
		draw_circle(point, 1.4, Color(0.81, 0.72, 0.45, sin(phase * PI) * 0.55))


func _poly(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
