class_name Const
extends RefCounted
## Physical constants shared by every module (SI units).

const G0: float = 9.80665          ## standard gravity [m/s^2]; also the g0 inside the Isp definition
const R_EARTH: float = 6371000.0   ## mean Earth radius [m]
const R_GAS: float = 287.05287     ## specific gas constant of dry air [J/(kg*K)]
const P_SL: float = 101325.0       ## ISA sea-level pressure [Pa]
const T_SL: float = 288.15         ## ISA sea-level temperature [K]
