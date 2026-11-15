class_name SimAnalysis
extends RefCounted
## Extracts flight events and figures of merit from a SimResult (the "MATLAB-style analysis" step).

## Drag is called "significant" once it exceeds this fraction of the rocket's current weight.
const DRAG_SIGNIFICANT_FRACTION: float = 0.01


static func analyse(res: SimResult) -> void:
	var e: Dictionary = {}
	var p: RocketParams = res.params
	var n: int = res.t.size()

	# ---- closed-form quantities --------------------------------------------------------
	e["area"] = RocketPhysics.area(p.diameter)
	e["mdot"] = RocketPhysics.mass_flow(p.thrust, p.isp)
	e["burn_time_ideal"] = RocketPhysics.burn_time(p.fuel_mass, p.thrust, p.isp)
	e["twr0"] = RocketPhysics.twr(p.thrust, p.initial_mass, Const.G0)
	e["dv_ideal"] = 0.0
	if p.fuel_mass > 0.0:
		e["dv_ideal"] = RocketPhysics.ideal_delta_v(p.isp, p.initial_mass, p.dry_mass())

	# ---- extrema -----------------------------------------------------------------------
	var i_v: int = 0
	var i_a: int = 0
	var i_q: int = 0
	var i_d: int = 0
	for i in range(n):
		if res.v[i] > res.v[i_v]:
			i_v = i
		if res.a[i] > res.a[i_a]:
			i_a = i
		if res.v[i] >= 0.0 and res.q[i] > res.q[i_q]:   # max-Q is an ascent quantity
			i_q = i
		if res.drag[i] > res.drag[i_d]:
			i_d = i
	e["v_max"] = res.v[i_v]
	e["t_v_max"] = res.t[i_v]
	e["a_max"] = res.a[i_a]
	e["t_a_max"] = res.t[i_a]
	e["i_a_max"] = i_a
	e["q_max"] = res.q[i_q]
	e["t_q_max"] = res.t[i_q]
	e["h_q_max"] = res.h[i_q]
	e["i_q_max"] = i_q
	e["d_max"] = res.drag[i_d]
	e["t_d_max"] = res.t[i_d]

	# ---- apogee: v crosses zero; refine with the local kinematics -------------------------
	var apogee: float = 0.0
	var t_apogee: float = 0.0
	var reached: bool = false
	for i in range(1, n):
		var v0: float = res.v[i - 1]
		var v1: float = res.v[i]
		if v0 > 0.0 and v1 <= 0.0:
			var tau: float = (res.t[i] - res.t[i - 1]) * v0 / (v0 - v1)
			apogee = res.h[i - 1] + v0 * tau + 0.5 * res.a[i - 1] * tau * tau
			t_apogee = res.t[i - 1] + tau
			reached = true
			break
	if not reached:
		var i_h: int = 0
		for i in range(n):
			if res.h[i] > res.h[i_h]:
				i_h = i
		apogee = res.h[i_h]
		t_apogee = res.t[i_h]
	e["apogee"] = apogee
	e["t_apogee"] = t_apogee
	e["apogee_reached"] = reached

	# ---- liftoff & drag significance -----------------------------------------------------
	e["t_liftoff"] = -1.0
	for i in range(1, n):
		if res.h[i] > 0.5:
			var f: float = (0.5 - res.h[i - 1]) / (res.h[i] - res.h[i - 1])
			e["t_liftoff"] = res.t[i - 1] + f * (res.t[i] - res.t[i - 1])
			break
	e["t_drag_significant"] = -1.0
	for i in range(1, n):
		var weight: float = res.m[i] * res.gravity[i]
		if weight > 0.0 and res.drag[i] >= DRAG_SIGNIFICANT_FRACTION * weight:
			e["t_drag_significant"] = res.t[i]
			break

	# ---- burnout state and velocity losses --------------------------------------------------
	var ib: int = res.i_burnout
	e["burnout"] = ib >= 0
	e["t_burnout"] = res.t_burnout if ib >= 0 else 0.0
	e["h_burnout"] = res.h[ib] if ib >= 0 else 0.0
	e["v_burnout"] = res.v[ib] if ib >= 0 else 0.0
	e["m_burnout"] = res.m[ib] if ib >= 0 else p.initial_mass
	var g_loss: float = 0.0
	var d_loss: float = 0.0
	if ib > 0:
		for i in range(1, ib + 1):
			var dt: float = res.t[i] - res.t[i - 1]
			g_loss += 0.5 * (res.gravity[i] + res.gravity[i - 1]) * dt
			d_loss += 0.5 * (res.drag[i] / res.m[i] + res.drag[i - 1] / res.m[i - 1]) * dt
	e["gravity_loss"] = g_loss
	e["drag_loss"] = d_loss

	# ---- end of flight ------------------------------------------------------------------------
	e["t_flight"] = res.t[n - 1]
	e["v_impact"] = res.v[n - 1] if res.landed else 0.0
	e["landed"] = res.landed
	e["fuel_efficiency"] = apogee / p.fuel_mass if p.fuel_mass > 0.0 else 0.0   # metres of apogee per kg propellant

	res.events = e
