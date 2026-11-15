class_name LaunchSimulation
extends RefCounted
## 1-D vertical launch integrated with RK4.
##
## State   y = [h, v, m]      (altitude, velocity, total mass)
## ODEs    dh/dt = v
##         dv/dt = (F - D)/m - g(h)          F = thrust while propellant remains, else 0
##         dm/dt = -F / (Isp g0)  while thrusting, else 0
##
## Engine cut-off (propellant exhausted) is a discontinuity in the right-hand side, so the step
## that would cross it is shortened to land exactly on t_burn. That keeps RK4 fourth-order accurate
## instead of smearing the thrust step across one time step.
##
## Launch pad: while h <= 0 and the net force points down the rocket simply sits on the pad
## (a = 0) -- propellant keeps burning, so a rocket with TWR < 1 may lift off later once lighter.

var _p: RocketParams
var _thrusting: bool = false
var _m_dry: float = 0.0
var _area: float = 0.0
var _mdot: float = 0.0


func run(params: RocketParams) -> SimResult:
	_p = params.clone()
	_m_dry = _p.initial_mass - _p.fuel_mass
	_area = RocketPhysics.area(_p.diameter)
	_mdot = RocketPhysics.mass_flow(_p.thrust, _p.isp)
	_thrusting = _p.fuel_mass > 0.0

	var res: SimResult = SimResult.new()
	res.params = _p

	var t: float = 0.0
	var y: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, _p.initial_mass])
	var airborne: bool = false
	var deriv: Callable = Callable(self, "_deriv")
	_sample(res, t, y)

	while t < _p.t_max:
		var dt: float = _p.dt_burn if _thrusting else _p.dt_coast
		var burnout_now: bool = false
		if _thrusting:
			var remaining: float = (y[2] - _m_dry) / _mdot
			if remaining <= dt * (1.0 + 1.0e-12):
				dt = remaining
				burnout_now = true

		var prev_t: float = t
		var prev_y: PackedFloat64Array = y
		y = RK4.step(deriv, t, y, dt)
		t += dt
		if burnout_now:
			y[2] = _m_dry
		if not airborne and y[0] > 1.0:
			airborne = true

		# Ground impact: interpolate to h = 0 and stop.
		if airborne and y[0] <= 0.0:
			var frac: float = prev_y[0] / (prev_y[0] - y[0])
			t = prev_t + frac * dt
			y = PackedFloat64Array([0.0, lerpf(prev_y[1], y[1], frac), lerpf(prev_y[2], y[2], frac)])
			_sample(res, t, y)
			res.landed = true
			break

		_sample(res, t, y)
		if burnout_now:
			res.i_burnout = res.t.size() - 1   # last sample with thrust on
			res.t_burnout = t
			_thrusting = false
			_sample(res, t, y)                  # same instant, thrust off (shows the step cleanly)

		if _p.stop_at_apogee and airborne and y[1] < 0.0:
			break

	SimAnalysis.analyse(res)
	return res


func _deriv(_t: float, y: PackedFloat64Array) -> PackedFloat64Array:
	var dm: float = -_mdot if _thrusting else 0.0
	return PackedFloat64Array([y[1], _accel(y[0], y[1], y[2]), dm])


func _accel(h: float, v: float, m: float) -> float:
	var f: float = _p.thrust if _thrusting else 0.0
	var d: float = 0.0
	if _p.drag_enabled:
		d = RocketPhysics.drag(Atmosphere.density(h), v, _p.cd, _area)
	var g: float = 0.0
	if _p.gravity_enabled:
		g = RocketPhysics.gravity(h, _p.variable_gravity)
	var a: float = RocketPhysics.acceleration(f, d, m, g)
	if h <= 0.0 and v <= 0.0 and a < 0.0:
		return 0.0   # supported by the launch pad
	return a


func _sample(res: SimResult, t: float, y: PackedFloat64Array) -> void:
	var h: float = y[0]
	var v: float = y[1]
	var m: float = y[2]
	var rho: float = Atmosphere.density(h)
	var d: float = 0.0
	if _p.drag_enabled:
		d = RocketPhysics.drag(rho, v, _p.cd, _area)
	var g: float = 0.0
	if _p.gravity_enabled:
		g = RocketPhysics.gravity(h, _p.variable_gravity)
	res.t.append(t)
	res.h.append(h)
	res.v.append(v)
	res.a.append(_accel(h, v, m))
	res.m.append(m)
	res.fuel.append(maxf(m - _m_dry, 0.0))
	res.thrust.append(_p.thrust if _thrusting else 0.0)
	res.drag.append(d)
	res.q.append(RocketPhysics.dynamic_pressure(rho, v))
	res.rho.append(rho)
	res.gravity.append(g)
