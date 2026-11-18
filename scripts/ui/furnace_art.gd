extends Control
## Decorative animation only. No gameplay RNG or outcome-dependent near misses.

const GOLD := Color("b5a375")
var brewing := false
var elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	AppSettings.reduced_motion_changed.connect(_motion)
	_motion(AppSettings.reduced_motion)


func set_brewing(value: bool) -> void:
	brewing = value
	queue_redraw()


func _motion(reduced: bool) -> void:
	set_process(not reduced)
	if reduced:
		elapsed = 0
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	var scale_value := minf(size.x / 360.0, size.y / 280.0)
	draw_set_transform((size - Vector2(360, 280) * scale_value) / 2.0, 0, Vector2.ONE * scale_value)
	var center := Vector2(180, 130)
	for radius in [106.0, 117.0, 129.0]:
		draw_arc(center, radius, 0, TAU, 96, Color(0.54, 0.61, 0.45, 0.16), 1, true)
	for i in range(32):
		var angle := TAU * i / 32
		draw_line(center + Vector2.from_angle(angle) * 117, center + Vector2.from_angle(angle) * (124 if i % 4 == 0 else 121), Color(0.65, 0.65, 0.44, 0.3), 1, true)
	var glow := 0.05 + (0.03 * sin(elapsed * 2) if brewing else 0.0)
	for i in range(5):
		draw_circle(Vector2(180, 235), 52.0 - 8 * i, Color(0.86, 0.52, 0.20, glow))
	_poly([Vector2(127, 198), Vector2(118, 247), Vector2(130, 250), Vector2(147, 209)], Color("476858"))
	_poly([Vector2(213, 209), Vector2(230, 250), Vector2(242, 247), Vector2(233, 198)], Color("476858"))
	draw_arc(Vector2(110, 151), 24, 0.8, 5.3, 40, GOLD.darkened(0.1), 6, true)
	draw_arc(Vector2(250, 151), 24, -2.2, 2.3, 40, GOLD.darkened(0.1), 6, true)
	var body := PackedVector2Array([Vector2(110, 130), Vector2(250, 130), Vector2(243, 187), Vector2(222, 212), Vector2(198, 224), Vector2(162, 224), Vector2(138, 212), Vector2(117, 187), Vector2(110, 130)])
	draw_colored_polygon(body, Color("365d4e"))
	draw_polyline(body, GOLD.darkened(0.2), 1.5, true)
	_poly([Vector2(118, 134), Vector2(137, 134), Vector2(143, 184), Vector2(156, 212), Vector2(139, 201)], Color(0.49, 0.65, 0.46, 0.23))
	_poly([Vector2(107, 120), Vector2(253, 120), Vector2(253, 130), Vector2(107, 130)], GOLD)
	_poly([Vector2(119, 114), Vector2(241, 114), Vector2(222, 102), Vector2(138, 102)], Color("618166"))
	draw_line(Vector2(119, 115), Vector2(241, 115), GOLD, 2, true)
	draw_circle(Vector2(180, 98), 8, GOLD)
	draw_arc(Vector2(180, 175), 21, 0, TAU, 48, GOLD, 1, true)
	_poly([Vector2(180, 162), Vector2(190, 175), Vector2(180, 188), Vector2(170, 175)], GOLD)
	draw_line(Vector2(141, 205), Vector2(219, 205), GOLD.darkened(0.3), 1, true)
	for ribbon in range(3):
		var smoke := PackedVector2Array()
		for step in range(24):
			var phase := elapsed * (1.1 if brewing else 0.35)
			smoke.append(Vector2(166 + ribbon * 14 + sin(step * 0.23 + phase + ribbon) * 6, 86 - step * 2.8))
		draw_polyline(smoke, Color(0.67, 0.79, 0.61, 0.26 if brewing else 0.13), 1.5, true)


func _poly(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
