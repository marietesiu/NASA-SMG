class_name UIStyle
extends RefCounted
## Dark aerospace-workstation look: palette, fonts and a project-wide Theme built in code.

const BG := Color("0a0e13")
const PANEL := Color("0f151d")
const PANEL_ALT := Color("151e29")
const PLOT_BG := Color("0b1017")
const BORDER := Color("243040")
const TEXT := Color("d5dde8")
const TEXT_DIM := Color("7f8da1")
const ACCENT := Color("4cc2ff")
const AMBER := Color("ffc247")
const GRID := Color("1a2431")
const GRID_MAJOR := Color("2c3a4d")
const AXIS := Color("55667c")
const OK := Color("6fdc8c")
const BAD := Color("ff6b6b")

static var _mono: SystemFont = null
static var _sans: SystemFont = null


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "JetBrains Mono", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
	return _mono


static func sans() -> SystemFont:
	if _sans == null:
		_sans = SystemFont.new()
		_sans.font_names = PackedStringArray(["Segoe UI", "Inter", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
	return _sans


## Distinct, colour-blind-friendly series colours by id.
static func color_by_id(id: String) -> Color:
	match id:
		"alt": return Color("4cc2ff")
		"vel": return Color("5fe3a1")
		"acc": return Color("ffc247")
		"fuel": return Color("b48cff")
		"mass": return Color("8fa3bf")
		"thr": return Color("ff7a59")
		"drag": return Color("ff5fa8")
	return TEXT


static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 0, margin: float = 6.0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


static func _dot(color: Color, d: int = 14) -> ImageTexture:
	var img: Image = Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c: float = (d - 1) * 0.5
	var r: float = d * 0.5 - 0.5
	for y in range(d):
		for x in range(d):
			var dist: float = Vector2(x - c, y - c).length()
			var a: float = clampf(r - dist + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)


static func make_theme() -> Theme:
	var th: Theme = Theme.new()
	th.default_font = sans()
	th.default_font_size = 14

	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)

	th.set_stylebox("panel", "PanelContainer", flat(PANEL, BORDER, 1, 4, 8.0))
	th.set_stylebox("panel", "Panel", flat(PANEL, BORDER, 1, 4))

	# Buttons / OptionButton
	for tn in ["Button", "OptionButton"]:
		th.set_stylebox("normal", tn, flat(PANEL_ALT, BORDER, 1, 3, 10.0))
		th.set_stylebox("hover", tn, flat(Color("1c2938"), ACCENT, 1, 3, 10.0))
		th.set_stylebox("pressed", tn, flat(Color("22364b"), ACCENT, 1, 3, 10.0))
		th.set_stylebox("disabled", tn, flat(PANEL, BORDER, 1, 3, 10.0))
		th.set_stylebox("focus", tn, flat(Color(0, 0, 0, 0), ACCENT, 1, 3, 10.0))
		th.set_color("font_color", tn, TEXT)
		th.set_color("font_hover_color", tn, Color.WHITE)
		th.set_color("font_pressed_color", tn, Color.WHITE)
		th.set_color("font_disabled_color", tn, TEXT_DIM)
		th.set_color("font_focus_color", tn, TEXT)

	th.set_stylebox("panel", "PopupMenu", flat(PANEL_ALT, ACCENT, 1, 3, 6.0))
	th.set_stylebox("hover", "PopupMenu", flat(Color("22364b"), Color(0, 0, 0, 0), 0, 2, 6.0))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# Text entry (also used inside SpinBox)
	th.set_stylebox("normal", "LineEdit", flat(Color("0b1017"), BORDER, 1, 3, 6.0))
	th.set_stylebox("focus", "LineEdit", flat(Color("0b1017"), ACCENT, 1, 3, 6.0))
	th.set_stylebox("read_only", "LineEdit", flat(Color("0b1017"), BORDER, 1, 3, 6.0))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_selected_color", "LineEdit", Color.WHITE)
	th.set_color("selection_color", "LineEdit", Color(0.30, 0.76, 1.0, 0.35))
	th.set_color("caret_color", "LineEdit", ACCENT)
	th.set_font("font", "LineEdit", mono())

	# Sliders
	var track: StyleBoxFlat = flat(Color("1d2a3a"), Color(0, 0, 0, 0), 0, 2, 0.0)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	var fill: StyleBoxFlat = flat(Color("2f87b8"), Color(0, 0, 0, 0), 0, 2, 0.0)
	fill.content_margin_top = 2.0
	fill.content_margin_bottom = 2.0
	var fill_hi: StyleBoxFlat = flat(ACCENT, Color(0, 0, 0, 0), 0, 2, 0.0)
	fill_hi.content_margin_top = 2.0
	fill_hi.content_margin_bottom = 2.0
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	th.set_icon("grabber", "HSlider", _dot(ACCENT))
	th.set_icon("grabber_highlight", "HSlider", _dot(Color.WHITE))
	th.set_icon("grabber_disabled", "HSlider", _dot(TEXT_DIM))

	# Tabs
	th.set_stylebox("tab_selected", "TabContainer", flat(PANEL, ACCENT, 1, 0, 14.0))
	th.set_stylebox("tab_unselected", "TabContainer", flat(BG, BORDER, 1, 0, 14.0))
	th.set_stylebox("tab_hovered", "TabContainer", flat(PANEL_ALT, BORDER, 1, 0, 14.0))
	th.set_stylebox("panel", "TabContainer", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0.0))
	th.set_color("font_selected_color", "TabContainer", Color.WHITE)
	th.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	th.set_color("font_hovered_color", "TabContainer", TEXT)

	# Scrollbars
	th.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 3.0))
	th.set_stylebox("grabber", "VScrollBar", flat(Color("2c3a4d"), Color(0, 0, 0, 0), 0, 3, 3.0))
	th.set_stylebox("grabber_highlight", "VScrollBar", flat(Color("3a4d66"), Color(0, 0, 0, 0), 0, 3, 3.0))
	th.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT, Color(0, 0, 0, 0), 0, 3, 3.0))

	# Tooltips
	th.set_stylebox("panel", "TooltipPanel", flat(Color("0a0e13"), ACCENT, 1, 3, 8.0))
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font_size("font_size", "TooltipLabel", 12)
	return th
