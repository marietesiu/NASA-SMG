class_name Atmosphere
extends RefCounted
## International Standard Atmosphere (ISA 1976) air density.
##
## Piecewise temperature layers up to 84.852 km geopotential altitude, using the
## hydrostatic equation  dP/dH = -P*g0/(R*T)  with either a constant lapse rate L
## (T = Tb + L*(H-Hb)) or an isothermal layer (L = 0). Above 84.852 km density is
## continued with an exponential tail (scale height R*T/g0). Density = P / (R*T).

const _HB: Array[float] = [0.0, 11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 84852.0]
const _LAPSE: Array[float] = [-0.0065, 0.0, 0.001, 0.0028, 0.0, -0.0028, -0.002]

static var _tb: PackedFloat64Array = PackedFloat64Array()
static var _pb: PackedFloat64Array = PackedFloat64Array()


static func _build() -> void:
	_tb.resize(8)
	_pb.resize(8)
	_tb[0] = Const.T_SL
	_pb[0] = Const.P_SL
	for i in range(7):
		var dh: float = _HB[i + 1] - _HB[i]
		var lapse: float = _LAPSE[i]
		_tb[i + 1] = _tb[i] + lapse * dh
		if absf(lapse) < 1.0e-12:
			_pb[i + 1] = _pb[i] * exp(-Const.G0 * dh / (Const.R_GAS * _tb[i]))
		else:
			_pb[i + 1] = _pb[i] * pow(_tb[i + 1] / _tb[i], -Const.G0 / (Const.R_GAS * lapse))


## Density [kg/m^3] at GEOMETRIC altitude [m].
static func density(altitude_m: float) -> float:
	var h: float = maxf(altitude_m, 0.0)
	var hg: float = Const.R_EARTH * h / (Const.R_EARTH + h)  # geometric -> geopotential
	return density_geopotential(hg)


## Density [kg/m^3] at GEOPOTENTIAL altitude [m] (the altitude ISA tables are written in).
static func density_geopotential(hg: float) -> float:
	if _tb.is_empty():
		_build()
	if hg >= _HB[7]:
		var rho_top: float = _pb[7] / (Const.R_GAS * _tb[7])
		var scale_h: float = Const.R_GAS * _tb[7] / Const.G0
		return rho_top * exp(-(hg - _HB[7]) / scale_h)
	var i: int = 0
	while i < 6 and hg >= _HB[i + 1]:
		i += 1
	var lapse: float = _LAPSE[i]
	var t: float = _tb[i] + lapse * (hg - _HB[i])
	var p: float = 0.0
	if absf(lapse) < 1.0e-12:
		p = _pb[i] * exp(-Const.G0 * (hg - _HB[i]) / (Const.R_GAS * _tb[i]))
	else:
		p = _pb[i] * pow(t / _tb[i], -Const.G0 / (Const.R_GAS * lapse))
	return p / (Const.R_GAS * t)
