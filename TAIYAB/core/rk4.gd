class_name RK4
extends RefCounted
## Classical 4th-order Runge-Kutta step for any ODE system  dy/dt = f(t, y).
## Generic on purpose so later modules (orbits, landing...) can reuse it.


## `f` is a Callable (t: float, y: PackedFloat64Array) -> PackedFloat64Array.
static func step(f: Callable, t: float, y: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var n: int = y.size()
	var tmp: PackedFloat64Array = PackedFloat64Array()
	tmp.resize(n)

	var k1: PackedFloat64Array = f.call(t, y)
	for i in range(n):
		tmp[i] = y[i] + 0.5 * dt * k1[i]
	var k2: PackedFloat64Array = f.call(t + 0.5 * dt, tmp)
	for i in range(n):
		tmp[i] = y[i] + 0.5 * dt * k2[i]
	var k3: PackedFloat64Array = f.call(t + 0.5 * dt, tmp)
	for i in range(n):
		tmp[i] = y[i] + dt * k3[i]
	var k4: PackedFloat64Array = f.call(t + dt, tmp)

	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(n)
	for i in range(n):
		out[i] = y[i] + dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return out
