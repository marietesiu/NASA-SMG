class_name Fmt
extends RefCounted
## Number formatting helpers (scientific notation, significant digits, tick labels).


static func fixed(v: float, decimals: int) -> String:
	return "%.*f" % [decimals, v]


## Scientific notation, e.g. 1.50e+06
static func sci(v: float, digits: int = 2) -> String:
	if is_nan(v):
		return "NaN"
	if v == 0.0:
		return "0"
	var e: int = int(floor(log(absf(v)) / log(10.0)))
	var m: float = v / pow(10.0, e)
	var ms: String = "%.*f" % [digits, m]
	if absf(ms.to_float()) >= 10.0:
		e += 1
		m = v / pow(10.0, e)
		ms = "%.*f" % [digits, m]
	return "%se%s%02d" % [ms, "+" if e >= 0 else "-", absi(e)]


## `digits` significant digits; switches to scientific notation for very large/small values.
static func sig(v: float, digits: int = 4) -> String:
	if is_nan(v):
		return "NaN"
	if v == 0.0:
		return "0"
	var mag: int = int(floor(log(absf(v)) / log(10.0)))
	if mag >= 6 or mag < -3:
		return sci(v, digits - 1)
	var decimals: int = maxi(0, digits - 1 - mag)
	return "%.*f" % [decimals, v]


static func thousands(v: float) -> String:
	var neg: bool = v < 0.0
	var s: String = str(int(round(absf(v))))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + out


## Axis tick label given the tick spacing (so decimals match the grid).
static func tick(v: float, step: float) -> String:
	if absf(v) < step * 1.0e-6:
		return "0"
	if absf(v) >= 1.0e6 or step < 1.0e-3:
		return sci(v, 1)
	var decimals: int = clampi(int(ceil(-log(step) / log(10.0) - 1.0e-9)), 0, 6)
	return "%.*f" % [decimals, v]
