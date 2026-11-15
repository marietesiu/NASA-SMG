class_name GraphPlot
extends Control
## Scientific line plot drawn with Godot's 2D canvas API (Godot ships no graphing widget).
##
## Data model  : series = [{name, xs: PackedFloat64Array, ys: PackedFloat64Array, color, dashed, unit, width}]
## Reference   : ref_lines = [{axis: "x"|"y", value, label, color}]
## Interaction : mouse wheel = zoom (Shift = x only, Ctrl = y only), drag = pan,
##               double-click = reset, hover = crosshair + exact sample values.
## Screen-space polylines are cached and only rebuilt when data, view or size changes.

signal x_view_changed(x_min: float, x_max: float, is_auto: bool)

const M_LEFT: float = 68.0
const M_RIGHT: float = 14.0
const M_TOP: float = 26.0
const M_BOTTOM: float = 42.0
const FS: int = 11

var title: String = ""
var x_label: String = "Time"
var x_unit: String = "s"
var y_label: String = ""
var y_unit: String = ""
var series: Array = []
var ref_lines: Array = []
var interactive: bool = true

var _auto_x: bool = true
var _auto_y: bool = true
var _ax0: float = 0.0
var _ax1: float = 1.0
var _ay0: float = 0.0
var _ay1: float = 1.0
var _vx0: float = 0.0
var _vx1: float = 1.0
var _vy0: float = 0.0
var _vy1: float = 1.0

var _hover: bool = false
var _mouse: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _cache: Array = []
var _dirty: bool = true

# current transform (refreshed at the start of every draw / interaction)
var _rect: Rect2 = Rect2()
var _x0: float = 0.0
var _x1: float = 1.0
var _y0: float = 0.0
var _y1: float = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(280, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	clip_contents = true
	resized.connect(_on_resized)


# ------------------------------------------------------------------------------------------
# public API
# ------------------------------------------------------------------------------------------
func set_data(new_series: Array, new_refs: Array = []) -> void:
	series = new_series
	ref_lines = new_refs
	_recompute_auto()
	_dirty = true
	queue_redraw()


func set_x_range(a: float, b: float, is_auto: bool) -> void:
	if is_auto:
		_auto_x = true
	else:
		_auto_x = false
		_vx0 = a
		_vx1 = b
	_dirty = true
	queue_redraw()


func reset_view() -> void:
	_auto_x = true
	_auto_y = true
	_dirty = true
	queue_redraw()
	x_view_changed.emit(_ax0, _ax1, true)


# ------------------------------------------------------------------------------------------
# scaling helpers
# ------------------------------------------------------------------------------------------
static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var e: float = floor(log(raw) / log(10.0))
	var base: float = pow(10.0, e)
	var f: float = raw / base
	var nf: float = 10.0
	if f <= 1.0:
		nf = 1.0
	elif f <= 2.0:
		nf = 2.0
	elif f <= 5.0:
		nf = 5.0
	return nf * base


## Returns [PackedFloat64Array ticks, float step].
static func _ticks(lo: float, hi: float, target: int) -> Array:
	var step: float = _nice_step((hi - lo) / float(maxi(target, 2)))
	var first: float = ceil(lo / step - 1.0e-9)
	var out: PackedFloat64Array = PackedFloat64Array()
	var k: int = 0
	while k < 200:
		var v: float = (first + k) * step
		if v > hi + step * 1.0e-6:
			break
		out.append(v)
		k += 1
	return [out, step]


func _recompute_auto() -> void:
	var xmax: float = 0.0
	var ymin: float = INF
	var ymax: float = -INF
	for s in series:
		var xs: PackedFloat64Array = s["xs"]
		var ys: PackedFloat64Array = s["ys"]
		if xs.size() > 0:
			xmax = maxf(xmax, xs[xs.size() - 1])
		for i in range(ys.size()):
			ymin = minf(ymin, ys[i])
			ymax = maxf(ymax, ys[i])
	for r in ref_lines:
		if r["axis"] == "y":
			ymin = minf(ymin, float(r["value"]))
			ymax = maxf(ymax, float(r["value"]))
	if ymin == INF:
		ymin = 0.0
		ymax = 1.0
	if xmax <= 0.0:
		xmax = 1.0
	if ymin > 0.0:
		ymin = 0.0
	if ymax < 0.0:
		ymax = 0.0
	if ymax - ymin < 1.0e-12:
		ymax = ymin + 1.0
	ymax += (ymax - ymin) * 0.05
	var step: float = _nice_step((ymax - ymin) / 5.0)
	_ax0 = 0.0
	_ax1 = xmax
	_ay0 = floor(ymin / step) * step
	_ay1 = ceil(ymax / step) * step


func _begin_transform() -> void:
	_rect = Rect2(M_LEFT, M_TOP, maxf(size.x - M_LEFT - M_RIGHT, 10.0), maxf(size.y - M_TOP - M_BOTTOM, 10.0))
	_x0 = _ax0 if _auto_x else _vx0
	_x1 = _ax1 if _auto_x else _vx1
	_y0 = _ay0 if _auto_y else _vy0
	_y1 = _ay1 if _auto_y else _vy1
	if _x1 - _x0 < 1.0e-12:
		_x1 = _x0 + 1.0
	if _y1 - _y0 < 1.0e-12:
		_y1 = _y0 + 1.0


func _to_px(x: float, y: float) -> Vector2:
	return Vector2(
		_rect.position.x + (x - _x0) / (_x1 - _x0) * _rect.size.x,
		_rect.end.y - (y - _y0) / (_y1 - _y0) * _rect.size.y)


# ------------------------------------------------------------------------------------------
# polyline cache (decimate + clip to the plot rectangle + optional dashing)
# ------------------------------------------------------------------------------------------
static func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	var p: Array = [-d.x, d.x, -d.y, d.y]
	var q: Array = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in range(4):
		var pi_: float = p[i]
		var qi: float = q[i]
		if absf(pi_) < 1.0e-12:
			if qi < 0.0:
				return []
		else:
			var tt: float = qi / pi_
			if pi_ < 0.0:
				if tt > t1:
					return []
				t0 = maxf(t0, tt)
			else:
				if tt < t0:
					return []
				t1 = minf(t1, tt)
	return [a + d * t0, a + d * t1]


func _build_runs(xs: PackedFloat64Array, ys: PackedFloat64Array) -> Array:
	var runs: Array = []
	var cur: PackedVector2Array = PackedVector2Array()
	var prev_pt: Vector2 = Vector2.ZERO
	var has_prev: bool = false
	var n: int = mini(xs.size(), ys.size())
	for i in range(n):
		var pt: Vector2 = _to_px(xs[i], ys[i])
		if has_prev and i < n - 1 and absf(pt.x - prev_pt.x) < 0.4 and absf(pt.y - prev_pt.y) < 0.4:
			continue
		if has_prev:
			var seg: Array = _clip_segment(prev_pt, pt, _rect)
			if seg.size() == 2:
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[1]
				if cur.is_empty() or cur[cur.size() - 1].distance_to(a) > 0.01:
					if cur.size() > 1:
						runs.append(cur)
					cur = PackedVector2Array([a])
				cur.append(b)
			else:
				if cur.size() > 1:
					runs.append(cur)
				cur = PackedVector2Array()
		prev_pt = pt
		has_prev = true
	if cur.size() > 1:
		runs.append(cur)
	return runs


static func _dash_polyline(poly: PackedVector2Array, on_len: float, off_len: float) -> Array:
	var out: Array = []
	if poly.size() < 2:
		return out
	var cur: PackedVector2Array = PackedVector2Array([poly[0]])
	var drawing: bool = true
	var remain: float = on_len
	for i in range(1, poly.size()):
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		var seg: float = a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir: Vector2 = (b - a) / seg
		var pos: float = 0.0
		while seg - pos > remain:
			pos += remain
			var pt: Vector2 = a + dir * pos
			if drawing:
				cur.append(pt)
				out.append(cur)
				cur = PackedVector2Array()
				drawing = false
				remain = off_len
			else:
				cur = PackedVector2Array([pt])
				drawing = true
				remain = on_len
		remain -= (seg - pos)
		if drawing:
			cur.append(b)
	if drawing and cur.size() >= 2:
		out.append(cur)
	return out


func _rebuild_cache() -> void:
	_cache.clear()
	for s in series:
		var xs: PackedFloat64Array = s["xs"]
		var ys: PackedFloat64Array = s["ys"]
		var runs: Array = _build_runs(xs, ys)
		if s.get("dashed", false):
			var dashes: Array = []
			for run in runs:
				dashes.append_array(_dash_polyline(run, 7.0, 5.0))
			runs = dashes
		_cache.append({"runs": runs, "color": s["color"], "width": s.get("width", 1.8)})


# ------------------------------------------------------------------------------------------
# drawing
# ------------------------------------------------------------------------------------------
func _on_resized() -> void:
	_dirty = true
	queue_redraw()


func _draw() -> void:
	_begin_transform()
	if _dirty:
		_rebuild_cache()
		_dirty = false
	var font: Font = UIStyle.mono()
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.PANEL)
	draw_rect(_rect, UIStyle.PLOT_BG)
	draw_string(font, Vector2(M_LEFT, 17.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, UIStyle.TEXT)
	_draw_grid(font)
	_draw_refs(font)
	for c in _cache:
		var col: Color = c["color"]
		var w: float = c["width"]
		for run in c["runs"]:
			draw_polyline(run, col, w, true)
	draw_rect(_rect, UIStyle.AXIS, false, 1.0)
	_draw_axis_titles(font)
	_draw_legend(font)
	if _hover and interactive and _rect.has_point(_mouse):
		_draw_hover(font)


func _draw_grid(font: Font) -> void:
	var tx: Array = _ticks(_x0, _x1, int(_rect.size.x / 85.0))
	var xt: PackedFloat64Array = tx[0]
	var xstep: float = tx[1]
	for v in xt:
		var px: float = _to_px(v, 0.0).x
		draw_line(Vector2(px, _rect.position.y), Vector2(px, _rect.end.y), UIStyle.GRID, 1.0)
		var s: String = Fmt.tick(v, xstep)
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		draw_string(font, Vector2(px - w * 0.5, _rect.end.y + 14.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, UIStyle.TEXT_DIM)

	var ty: Array = _ticks(_y0, _y1, int(_rect.size.y / 38.0))
	var yt: PackedFloat64Array = ty[0]
	var ystep: float = ty[1]
	for v in yt:
		var py: float = _to_px(0.0, v).y
		var zero: bool = absf(v) < ystep * 1.0e-6
		draw_line(Vector2(_rect.position.x, py), Vector2(_rect.end.x, py), UIStyle.GRID_MAJOR if zero else UIStyle.GRID, 1.0)
		var s2: String = Fmt.tick(v, ystep)
		var w2: float = font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		draw_string(font, Vector2(_rect.position.x - 6.0 - w2, py + 4.0), s2, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, UIStyle.TEXT_DIM)


func _draw_refs(font: Font) -> void:
	for r in ref_lines:
		var c: Color = r.get("color", UIStyle.AMBER)
		var label: String = r.get("label", "")
		if r["axis"] == "x":
			var px: float = _to_px(float(r["value"]), 0.0).x
			if px >= _rect.position.x and px <= _rect.end.x:
				draw_dashed_line(Vector2(px, _rect.position.y), Vector2(px, _rect.end.y), c, 1.0, 5.0)
				draw_string(font, Vector2(px + 4.0, _rect.position.y + 12.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, c)
		else:
			var py: float = _to_px(0.0, float(r["value"])).y
			if py >= _rect.position.y and py <= _rect.end.y:
				draw_dashed_line(Vector2(_rect.position.x, py), Vector2(_rect.end.x, py), c, 1.5, 6.0)
				draw_string(font, Vector2(_rect.position.x + 6.0, py - 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, c)


func _draw_axis_titles(font: Font) -> void:
	var xt: String = "%s (%s)" % [x_label, x_unit]
	var xw: float = font.get_string_size(xt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	draw_string(font, Vector2(_rect.position.x + (_rect.size.x - xw) * 0.5, size.y - 6.0), xt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, UIStyle.TEXT)
	var yt: String = "%s (%s)" % [y_label, y_unit]
	var yw: float = font.get_string_size(yt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	draw_set_transform(Vector2(13.0, _rect.position.y + (_rect.size.y + yw) * 0.5), -PI * 0.5, Vector2.ONE)
	draw_string(font, Vector2.ZERO, yt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, UIStyle.TEXT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_legend(font: Font) -> void:
	if series.size() < 2:
		return
	var maxw: float = 0.0
	for s in series:
		maxw = maxf(maxw, font.get_string_size(s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
	var x: float = _rect.end.x - maxw - 34.0
	var y: float = _rect.position.y + 8.0
	draw_rect(Rect2(x - 7.0, y - 5.0, maxw + 42.0, series.size() * 15.0 + 4.0), Color(0.04, 0.06, 0.09, 0.8))
	for s in series:
		var c: Color = s["color"]
		if s.get("dashed", false):
			draw_dashed_line(Vector2(x, y + 5.0), Vector2(x + 18.0, y + 5.0), c, 2.0, 4.0)
		else:
			draw_line(Vector2(x, y + 5.0), Vector2(x + 18.0, y + 5.0), c, 2.0)
		draw_string(font, Vector2(x + 24.0, y + 9.0), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, UIStyle.TEXT)
		y += 15.0


static func _nearest(arr: PackedFloat64Array, x: float) -> int:
	var n: int = arr.size()
	var i: int = arr.bsearch(x)
	if i <= 0:
		return 0
	if i >= n:
		return n - 1
	return i if (arr[i] - x) < (x - arr[i - 1]) else i - 1


func _draw_hover(font: Font) -> void:
	if series.is_empty():
		return
	var first: Dictionary = series[0]
	var fxs: PackedFloat64Array = first["xs"]
	if fxs.is_empty():
		return
	var xv: float = _x0 + (_mouse.x - _rect.position.x) / _rect.size.x * (_x1 - _x0)
	var x_snap: float = fxs[_nearest(fxs, xv)]
	var px: float = _to_px(x_snap, 0.0).x
	draw_line(Vector2(px, _rect.position.y), Vector2(px, _rect.end.y), UIStyle.TEXT_DIM, 1.0)

	var lines: Array = []
	lines.append(["%s = %s %s" % [x_label, Fmt.sig(x_snap, 5), x_unit], UIStyle.TEXT])
	for s in series:
		var xs: PackedFloat64Array = s["xs"]
		var ys: PackedFloat64Array = s["ys"]
		if xs.is_empty():
			continue
		var idx: int = _nearest(xs, x_snap)
		var yv: float = ys[idx]
		var pt: Vector2 = _to_px(xs[idx], yv)
		var c: Color = s["color"]
		if _rect.has_point(pt):
			draw_circle(pt, 4.0, UIStyle.PLOT_BG)
			draw_arc(pt, 4.0, 0.0, TAU, 20, c, 2.0, true)
		lines.append(["%s: %s %s" % [s["name"], Fmt.sig(yv, 5), s.get("unit", "")], c])

	var tw: float = 0.0
	for l in lines:
		tw = maxf(tw, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
	var box: Vector2 = Vector2(tw + 16.0, lines.size() * 15.0 + 8.0)
	var pos: Vector2 = _mouse + Vector2(14.0, 14.0)
	if pos.x + box.x > size.x:
		pos.x = _mouse.x - box.x - 14.0
	if pos.y + box.y > size.y:
		pos.y = _mouse.y - box.y - 14.0
	draw_rect(Rect2(pos, box), Color(0.03, 0.05, 0.08, 0.95))
	draw_rect(Rect2(pos, box), UIStyle.AXIS, false, 1.0)
	var ty: float = pos.y + 17.0
	for l in lines:
		draw_string(font, Vector2(pos.x + 8.0, ty), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS, l[1])
		ty += 15.0


# ------------------------------------------------------------------------------------------
# input
# ------------------------------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		_dragging = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_mouse = mm.position
		_hover = true
		if _dragging:
			_pan(mm.relative)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(mb.position, 0.85, mb.shift_pressed, mb.ctrl_pressed)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(mb.position, 1.0 / 0.85, mb.shift_pressed, mb.ctrl_pressed)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				reset_view()
			else:
				_begin_transform()
				_dragging = mb.pressed and _rect.has_point(mb.position)


func _zoom(pos: Vector2, factor: float, x_only: bool, y_only: bool) -> void:
	_begin_transform()
	if not _rect.has_point(pos):
		return
	var fx: float = (pos.x - _rect.position.x) / _rect.size.x
	var fy: float = 1.0 - (pos.y - _rect.position.y) / _rect.size.y
	if not y_only:
		var cx: float = lerpf(_x0, _x1, fx)
		_vx0 = cx - (cx - _x0) * factor
		_vx1 = cx + (_x1 - cx) * factor
		_auto_x = false
	if not x_only:
		var cy: float = lerpf(_y0, _y1, fy)
		_vy0 = cy - (cy - _y0) * factor
		_vy1 = cy + (_y1 - cy) * factor
		_auto_y = false
	_dirty = true
	queue_redraw()
	if not y_only:
		x_view_changed.emit(_vx0, _vx1, false)


func _pan(rel: Vector2) -> void:
	_begin_transform()
	var dx: float = -rel.x / _rect.size.x * (_x1 - _x0)
	var dy: float = rel.y / _rect.size.y * (_y1 - _y0)
	_vx0 = _x0 + dx
	_vx1 = _x1 + dx
	_vy0 = _y0 + dy
	_vy1 = _y1 + dy
	_auto_x = false
	_auto_y = false
	_dirty = true
	queue_redraw()
	x_view_changed.emit(_vx0, _vx1, false)
