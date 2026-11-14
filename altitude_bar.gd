class_name AltitudeBar
extends Control
## Vertical altitude scale with one band per atmosphere layer and a marker for
## the rocket's current altitude.

## Layers from the ground up: name, top altitude in km, colour.
var layers: Array[Dictionary] = []
var altitude_km: float = 0.0:
	set(value):
		altitude_km = value
		queue_redraw()


func _draw() -> void:
	if layers.is_empty():
		return
	var font: Font = get_theme_default_font()
	var top_km: float = layers[layers.size() - 1].top_km
	var bar := Rect2(0.0, 0.0, 26.0, size.y)
	var floor_km: float = 0.0
	for layer in layers:
		var y_top: float = _y_of(layer.top_km, top_km)
		var y_bottom: float = _y_of(floor_km, top_km)
		draw_rect(Rect2(bar.position.x, y_top, bar.size.x, y_bottom - y_top), layer.color)
		draw_line(Vector2(0.0, y_bottom), Vector2(bar.size.x + 6.0, y_bottom), Color.WHITE, 2.0)
		draw_string_outline(font, Vector2(bar.size.x + 12.0, y_bottom - 6.0),
				"%s  (from %d km)" % [layer.name, floor_km], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
		draw_string(font, Vector2(bar.size.x + 12.0, y_bottom - 6.0),
				"%s  (from %d km)" % [layer.name, floor_km], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		floor_km = layer.top_km
	draw_rect(bar, Color.WHITE, false, 2.0)
	# Marker.
	var y: float = _y_of(minf(altitude_km, top_km), top_km)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16.0, y - 9.0), Vector2(-16.0, y + 9.0), Vector2(0.0, y),
	]), Color(1.0, 0.85, 0.2))
	draw_line(Vector2(0.0, y), Vector2(bar.size.x, y), Color(1.0, 0.85, 0.2), 3.0)


func _y_of(km: float, top_km: float) -> float:
	return size.y * (1.0 - km / top_km)
