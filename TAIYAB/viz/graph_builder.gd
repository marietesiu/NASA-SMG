class_name GraphBuilder
extends RefCounted
## Graph-generation layer: turns a SimResult into plottable series (with unit conversion).
## It knows nothing about drawing (GraphPlot) or the UI layout.

const SPECS: Array[Dictionary] = [
	{"id": "altitude", "title": "Altitude vs Time", "y_label": "Altitude h", "y_unit": "km", "scale": 0.001,
		"series": [{"col": "h", "name": "Altitude", "color": "alt"}]},
	{"id": "velocity", "title": "Velocity vs Time", "y_label": "Velocity v", "y_unit": "m/s", "scale": 1.0,
		"series": [{"col": "v", "name": "Velocity", "color": "vel"}]},
	{"id": "accel", "title": "Acceleration vs Time", "y_label": "Acceleration a", "y_unit": "m/s²", "scale": 1.0,
		"series": [{"col": "a", "name": "Acceleration", "color": "acc"}]},
	{"id": "fuel", "title": "Fuel & Total Mass vs Time", "y_label": "Mass", "y_unit": "kg", "scale": 1.0,
		"series": [{"col": "fuel", "name": "Fuel mass", "color": "fuel"}, {"col": "m", "name": "Total mass", "color": "mass"}]},
	{"id": "thrust", "title": "Thrust vs Time", "y_label": "Thrust F", "y_unit": "kN", "scale": 0.001,
		"series": [{"col": "thrust", "name": "Thrust", "color": "thr"}]},
	{"id": "drag", "title": "Atmospheric Drag vs Time  (+ve opposes ascent)", "y_label": "Drag D", "y_unit": "kN", "scale": 0.001,
		"series": [{"col": "drag", "name": "Drag", "color": "drag"}]},
]


static func make_series(res: SimResult, col: String, scale: float, series_name: String, color: Color, dashed: bool, unit: String) -> Dictionary:
	var src: PackedFloat64Array = res.column(col)
	var ys: PackedFloat64Array = PackedFloat64Array()
	ys.resize(src.size())
	for i in range(src.size()):
		ys[i] = src[i] * scale
	return {"name": series_name, "xs": res.t, "ys": ys, "color": color, "dashed": dashed, "unit": unit, "width": 1.9}


## Series for one graph; if a baseline run is supplied it is overlaid dashed for comparison.
static func build(spec: Dictionary, res: SimResult, baseline: SimResult) -> Array:
	var out: Array = []
	var compare: bool = baseline != null
	for s in spec["series"]:
		var nm: String = s["name"] + (" (current)" if compare else "")
		out.append(make_series(res, s["col"], spec["scale"], nm, UIStyle.color_by_id(s["color"]), false, spec["y_unit"]))
	if compare:
		for s in spec["series"]:
			var c: Color = UIStyle.color_by_id(s["color"]).lerp(Color.WHITE, 0.45)
			out.append(make_series(baseline, s["col"], spec["scale"], s["name"] + " (baseline)", c, true, spec["y_unit"]))
	return out


static func ref_lines(res: SimResult) -> Array:
	var out: Array = []
	if res.i_burnout >= 0:
		out.append({"axis": "x", "value": res.t_burnout, "label": "MECO", "color": UIStyle.TEXT_DIM})
	return out
