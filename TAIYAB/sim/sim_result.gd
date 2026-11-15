class_name SimResult
extends RefCounted
## Output of one simulation run: time series (one row per integration step) + derived events.
## All values SI. Every graph and every equation read-out is derived from this single object,
## which is what keeps them mutually consistent.

var params: RocketParams

var t: PackedFloat64Array = PackedFloat64Array()        ## time [s]
var h: PackedFloat64Array = PackedFloat64Array()        ## altitude [m]
var v: PackedFloat64Array = PackedFloat64Array()        ## vertical velocity [m/s]
var a: PackedFloat64Array = PackedFloat64Array()        ## acceleration [m/s^2]
var m: PackedFloat64Array = PackedFloat64Array()        ## total mass [kg]
var fuel: PackedFloat64Array = PackedFloat64Array()     ## propellant remaining [kg]
var thrust: PackedFloat64Array = PackedFloat64Array()   ## thrust [N]
var drag: PackedFloat64Array = PackedFloat64Array()     ## signed drag force [N] (+ve opposes ascent)
var q: PackedFloat64Array = PackedFloat64Array()        ## dynamic pressure [Pa]
var rho: PackedFloat64Array = PackedFloat64Array()      ## air density [kg/m^3]
var gravity: PackedFloat64Array = PackedFloat64Array()  ## local g [m/s^2]

var i_burnout: int = -1       ## index of the last sample with the engine still firing
var t_burnout: float = 0.0
var landed: bool = false
var events: Dictionary = {}


func size() -> int:
	return t.size()


func column(col_name: String) -> PackedFloat64Array:
	match col_name:
		"t": return t
		"h": return h
		"v": return v
		"a": return a
		"m": return m
		"fuel": return fuel
		"thrust": return thrust
		"drag": return drag
		"q": return q
		"rho": return rho
		"gravity": return gravity
	return PackedFloat64Array()


## Linear interpolation of a column at an arbitrary time.
func value_at(col_name: String, time: float) -> float:
	var col: PackedFloat64Array = column(col_name)
	var n: int = t.size()
	if n == 0:
		return 0.0
	if time <= t[0]:
		return col[0]
	if time >= t[n - 1]:
		return col[n - 1]
	var i: int = t.bsearch(time)
	var i0: int = i - 1
	var span: float = t[i] - t[i0]
	if span <= 0.0:
		return col[i]
	return lerpf(col[i0], col[i], (time - t[i0]) / span)
