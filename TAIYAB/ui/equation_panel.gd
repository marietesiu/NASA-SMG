class_name EquationPanel
extends VBoxContainer
## Governing equations with live numbers substituted from the current SimResult.
## Hover any variable chip for its meaning and units.

var _bodies: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_add_card("twr", "THRUST-TO-WEIGHT RATIO", "TWR = F / (m · g)", [
		["F", "thrust", "Engine thrust in newtons (N)."],
		["m", "mass", "Instantaneous total mass of the rocket (kg)."],
		["g", "gravity", "Local gravitational acceleration (m/s²)."],
	])
	_add_card("accel", "ACCELERATION", "a = (F − D) / m − g", [
		["F", "thrust", "Engine thrust (N); zero after engine cut-off."],
		["D", "drag", "Aerodynamic drag force (N), opposing the velocity."],
		["m", "mass", "Instantaneous total mass (kg); it falls as fuel burns."],
		["g", "gravity", "Local gravitational acceleration, g(h) (m/s²)."],
	])
	_add_card("drag", "ATMOSPHERIC DRAG", "D = ½ · ρ · v² · Cd · A", [
		["ρ", "air density", "Air density (kg/m³) from the ISA atmosphere model; falls roughly exponentially with altitude."],
		["v", "velocity", "Speed relative to the air (m/s)."],
		["Cd", "drag coeff.", "Dimensionless drag coefficient: shape-dependent aerodynamic resistance."],
		["A", "ref. area", "Frontal reference area A = π(d/2)² (m²)."],
		["q", "dyn. pressure", "q = ½ρv² (Pa). Its ascent maximum is called max-Q: peak aerodynamic loading."],
	])
	_add_card("fuel", "FUEL CONSUMPTION", "dm/dt = − F / (Isp · g0)", [
		["Isp", "specific impulse", "Engine efficiency in seconds: seconds one kilogram of propellant can produce one kilogram-force of thrust."],
		["g0", "std. gravity", "9.80665 m/s², the conventional constant in the definition of Isp."],
		["tburn", "burn time", "tburn = m_fuel / (dm/dt): time until the propellant is exhausted (engine cut-off, MECO)."],
	])
	_add_card("tsiol", "IDEAL VELOCITY BUDGET (TSIOLKOVSKY)", "Δv = Isp · g0 · ln(m0 / mf)", [
		["m0", "initial mass", "Mass at ignition (kg)."],
		["mf", "final mass", "Dry mass after the propellant is used (kg)."],
		["losses", "Δv losses", "Gravity loss ∫g dt and drag loss ∫D/m dt reduce the velocity actually achieved at burnout."],
	])
	_add_card("env", "ENVIRONMENT MODEL", "g(h) = g0 · (R / (R + h))²", [
		["R", "Earth radius", "6,371 km mean radius."],
		["h", "altitude", "Height above the launch site (m)."],
		["ISA", "atmosphere", "International Standard Atmosphere 1976 layers up to 84.9 km, exponential tail above."],
	])


func _add_card(id: String, card_title: String, formula: String, legend: Array) -> void:
	var card: PanelContainer = PanelContainer.new()
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	var t: Label = Label.new()
	t.text = card_title
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_color_override("font_color", UIStyle.ACCENT)
	vb.add_child(t)

	var f: Label = Label.new()
	f.text = formula
	f.add_theme_font_override("font", UIStyle.mono())
	f.add_theme_font_size_override("font_size", 18)
	f.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(f)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", UIStyle.mono())
	body.add_theme_font_size_override("normal_font_size", 12)
	vb.add_child(body)

	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	vb.add_child(flow)
	for item in legend:
		var chip: Label = Label.new()
		chip.text = "%s · %s" % [item[0], item[1]]
		chip.tooltip_text = "%s — %s" % [item[0], item[2]]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		chip.add_theme_stylebox_override("normal", UIStyle.flat(UIStyle.PANEL_ALT, UIStyle.BORDER, 1, 3, 6.0))
		flow.add_child(chip)

	_bodies[id] = body
	add_child(card)


static func _v(s: String) -> String:
	return "[color=#%s]%s[/color]" % [UIStyle.AMBER.to_html(false), s]


static func _d(s: String) -> String:
	return "[color=#%s]%s[/color]" % [UIStyle.TEXT_DIM.to_html(false), s]


func update(res: SimResult) -> void:
	var p: RocketParams = res.params
	var e: Dictionary = res.events
	var g0: float = Const.G0
	var area: float = e["area"]
	var burnt: bool = e["burnout"]

	# --- TWR ---------------------------------------------------------------------------------
	var s: String = _d("at liftoff (h = 0):") + "\n"
	s += "TWR = %s N / (%s kg × %s m/s²) = %s" % [Fmt.sig(p.thrust), Fmt.sig(p.initial_mass), Fmt.sig(g0), _v(Fmt.sig(e["twr0"], 4))]
	if burnt:
		var gb: float = RocketPhysics.gravity(e["h_burnout"])
		var twr_b: float = RocketPhysics.twr(p.thrust, p.dry_mass(), gb)
		s += "\n\n" + _d("at engine cut-off (propellant gone):") + "\n"
		s += "TWR = %s N / (%s kg × %s m/s²) = %s" % [Fmt.sig(p.thrust), Fmt.sig(p.dry_mass()), Fmt.sig(gb), _v(Fmt.sig(twr_b, 4))]
	s += "\n\n" + (_d("TWR > 1: net upward force, the rocket can lift off.") if float(e["twr0"]) > 1.0 else _v("TWR < 1: the rocket cannot lift off at full mass."))
	_set("twr", s)

	# --- acceleration ------------------------------------------------------------------------
	var a0_raw: float = p.thrust / p.initial_mass - g0
	s = _d("at liftoff (v = 0 so D = 0):") + "\n"
	s += "a = (%s − 0) / %s − %s = %s m/s²  (%s g)" % [Fmt.sig(p.thrust), Fmt.sig(p.initial_mass), Fmt.sig(g0), _v(Fmt.sig(a0_raw, 4)), Fmt.sig(a0_raw / g0, 3)]
	if a0_raw < 0.0:
		s += "\n" + _v("negative → held by the launch pad (a = 0)")
	var ia: int = e["i_a_max"]
	s += "\n\n" + _d("peak (t = %s s):" % Fmt.sig(e["t_a_max"], 4)) + "\n"
	s += "a = (%s − %s) / %s − %s = %s m/s²  (%s g)" % [Fmt.sig(res.thrust[ia]), Fmt.sig(res.drag[ia]), Fmt.sig(res.m[ia]), Fmt.sig(res.gravity[ia]), _v(Fmt.sig(e["a_max"], 4)), Fmt.sig(float(e["a_max"]) / g0, 3)]
	_set("accel", s)

	# --- drag at max-Q -----------------------------------------------------------------------
	var iq: int = e["i_q_max"]
	s = _d("A = π (d/2)² = π × (%s m / 2)² =" % Fmt.sig(p.diameter)) + " " + _v(Fmt.sig(area, 4) + " m²") + "\n\n"
	s += _d("at max-Q (t = %s s, h = %s km):" % [Fmt.sig(res.t[iq], 4), Fmt.sig(res.h[iq] / 1000.0, 4)]) + "\n"
	s += "ρ = %s kg/m³,  v = %s m/s,  Cd = %s\n" % [Fmt.sig(res.rho[iq], 4), Fmt.sig(res.v[iq], 4), Fmt.sig(p.cd, 3)]
	s += "D = ½ × %s × (%s)² × %s × %s = %s N\n" % [Fmt.sig(res.rho[iq], 4), Fmt.sig(res.v[iq], 4), Fmt.sig(p.cd, 3), Fmt.sig(area, 4), _v(Fmt.sig(res.drag[iq], 4))]
	s += "q = ½ρv² = " + _v("%s kPa" % Fmt.sig(float(e["q_max"]) / 1000.0, 4))
	if float(e["t_drag_significant"]) >= 0.0:
		s += "\n" + _d("drag first exceeds 1 %% of weight at t = %s s" % Fmt.sig(e["t_drag_significant"], 4))
	_set("drag", s)

	# --- fuel consumption ----------------------------------------------------------------------
	s = "dm/dt = −%s N / (%s s × %s m/s²) = " % [Fmt.sig(p.thrust), Fmt.sig(p.isp), Fmt.sig(g0)] + _v("−%s kg/s" % Fmt.sig(e["mdot"], 4)) + "\n"
	s += "tburn = %s kg / %s kg/s = %s" % [Fmt.sig(p.fuel_mass), Fmt.sig(e["mdot"], 4), _v(Fmt.sig(e["burn_time_ideal"], 5) + " s")]
	s += "\n" + _d("ve = Isp·g0 = %s m/s" % Fmt.sig(RocketPhysics.exhaust_velocity(p.isp), 4))
	_set("fuel", s)

	# --- Tsiolkovsky + losses ------------------------------------------------------------------
	var dv: float = e["dv_ideal"]
	s = "Δv = %s × %s × ln(%s / %s) = %s m/s\n" % [Fmt.sig(p.isp), Fmt.sig(g0), Fmt.sig(p.initial_mass), Fmt.sig(p.dry_mass()), _v(Fmt.sig(dv, 5))]
	if burnt:
		s += "gravity loss ∫g dt = %s m/s\n" % Fmt.sig(e["gravity_loss"], 4)
		s += "drag loss ∫D/m dt = %s m/s\n" % Fmt.sig(e["drag_loss"], 4)
		s += "v at cut-off = %s m/s  " % _v(Fmt.sig(e["v_burnout"], 5))
		s += _d("(= Δv − losses, a built-in check on the integrator)")
	else:
		s += _d("no engine cut-off within the simulated time")
	_set("tsiol", s)

	# --- environment ------------------------------------------------------------------------------
	var hs: PackedFloat64Array = PackedFloat64Array([0.0, 5000.0, 11000.0, 30000.0, 80000.0])
	s = ""
	for hh in hs:
		s += "h = %5s km:  g = %s m/s²,  ρ = %s kg/m³\n" % [Fmt.sig(hh / 1000.0, 3), Fmt.sig(RocketPhysics.gravity(hh), 5), Fmt.sig(Atmosphere.density(hh), 4)]
	s += _d("apogee %s km:  g = %s m/s²" % [Fmt.sig(float(e["apogee"]) / 1000.0, 4), Fmt.sig(RocketPhysics.gravity(e["apogee"]), 5)])
	_set("env", s)


func _set(id: String, bbcode: String) -> void:
	var body: RichTextLabel = _bodies[id]
	body.text = bbcode
