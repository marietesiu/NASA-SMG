class_name RocketPhysics
extends RefCounted
## Closed-form equations of the simplified launch model. Pure functions, SI units,
## no state: the equation panel, the simulator and the tests all call these.


static func area(diameter: float) -> float:
	## Cross-sectional (reference) area  A = pi (d/2)^2
	var r: float = diameter * 0.5
	return PI * r * r


static func gravity(altitude: float, variable: bool = true) -> float:
	## g(h) = g0 (R / (R + h))^2   (or constant g0)
	if not variable:
		return Const.G0
	var k: float = Const.R_EARTH / (Const.R_EARTH + maxf(altitude, 0.0))
	return Const.G0 * k * k


static func dynamic_pressure(rho: float, v: float) -> float:
	## q = 1/2 rho v^2
	return 0.5 * rho * v * v


static func drag(rho: float, v: float, cd: float, a_ref: float) -> float:
	## D = 1/2 rho v |v| Cd A  (signed so that it always opposes the velocity)
	return 0.5 * rho * v * absf(v) * cd * a_ref


static func mass_flow(thrust: float, isp: float) -> float:
	## mdot = F / (Isp g0)
	return thrust / (isp * Const.G0)


static func exhaust_velocity(isp: float) -> float:
	return isp * Const.G0


static func twr(thrust: float, mass: float, g: float) -> float:
	## TWR = F / (m g)
	return thrust / (mass * g)


static func acceleration(thrust: float, drag_force: float, mass: float, g: float) -> float:
	## a = (F - D) / m - g
	return (thrust - drag_force) / mass - g


static func burn_time(fuel: float, thrust: float, isp: float) -> float:
	## t_burn = m_fuel / mdot
	return fuel / mass_flow(thrust, isp)


static func ideal_delta_v(isp: float, m0: float, mf: float) -> float:
	## Tsiolkovsky: dv = Isp g0 ln(m0 / mf)
	return isp * Const.G0 * log(m0 / mf)
