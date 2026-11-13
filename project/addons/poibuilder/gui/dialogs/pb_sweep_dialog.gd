## PBSweepDialog — options for sweeping a profile along the selected Path3D.
##
## The plugin owns the geometry (PBSweep); this dialog only collects the
## profile preset, its dimensions, sampling and the two placement toggles.
## Settings persist for the session because the plugin keeps one instance.
@tool
class_name PBSweepDialog
extends ConfirmationDialog

var _opt_profile: OptionButton
var _spin_width: SpinBox
var _spin_thickness: SpinBox
var _spin_height: SpinBox
var _spin_radius: SpinBox
var _spin_segments: SpinBox
var _spin_spacing: SpinBox
var _spin_uv: SpinBox
var _chk_closed: CheckBox
var _chk_caps: CheckBox
var _chk_drop: CheckBox
var _rows: Dictionary = {}

func _init() -> void:
	title = "Sweep Along Path"
	ok_button_text = "Sweep"
	min_size = Vector2(380, 0)
	_build_ui()

func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var lbl_info := Label.new()
	lbl_info.text = "Select a Path3D, draw its Curve3D, then Sweep."
	lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_info)
	vb.add_child(HSeparator.new())

	_opt_profile = OptionButton.new()
	for kind in [PBSweep.ProfileKind.ROAD, PBSweep.ProfileKind.BARRIER,
			PBSweep.ProfileKind.PIPE, PBSweep.ProfileKind.RIBBON]:
		_opt_profile.add_item(PBSweep.profile_label(kind), kind)
	_opt_profile.select(0)
	_opt_profile.item_selected.connect(func(_i: int) -> void: _update_rows())
	vb.add_child(_row("Profile", _opt_profile))

	_spin_width = _spin(0.05, 100.0, 0.05, 3.0)
	_rows["width"] = _row("Width", _spin_width)
	vb.add_child(_rows["width"])
	_spin_thickness = _spin(0.01, 20.0, 0.01, 0.2)
	_rows["thickness"] = _row("Thickness", _spin_thickness)
	vb.add_child(_rows["thickness"])
	_spin_height = _spin(0.02, 100.0, 0.05, 1.0)
	_rows["height"] = _row("Height", _spin_height)
	vb.add_child(_rows["height"])
	_spin_radius = _spin(0.02, 50.0, 0.01, 0.25)
	_rows["radius"] = _row("Radius", _spin_radius)
	vb.add_child(_rows["radius"])
	_spin_segments = _spin(3.0, 64.0, 1.0, 12.0)
	_spin_segments.suffix = ""
	_rows["segments"] = _row("Sides", _spin_segments)
	vb.add_child(_rows["segments"])

	vb.add_child(HSeparator.new())
	_spin_spacing = _spin(0.1, 20.0, 0.1, 1.0)
	_spin_spacing.tooltip_text = "Distance between swept sections along the path (metres). Smaller follows curves more closely."
	vb.add_child(_row("Sample every", _spin_spacing))
	_spin_uv = _spin(0.1, 100.0, 0.1, 1.0)
	_spin_uv.tooltip_text = "Metres of world length per texture repeat."
	vb.add_child(_row("UV repeat", _spin_uv))

	_chk_closed = CheckBox.new()
	_chk_closed.text = "Closed loop"
	_chk_closed.tooltip_text = "Wrap the last path section back to the first (no end caps)."
	vb.add_child(_chk_closed)
	_chk_caps = CheckBox.new()
	_chk_caps.text = "End caps"
	_chk_caps.button_pressed = true
	vb.add_child(_chk_caps)
	_chk_drop = CheckBox.new()
	_chk_drop.text = "Drop to surface"
	_chk_drop.tooltip_text = "Raycast every sample down onto the scene geometry (terrain, floors) before sweeping."
	vb.add_child(_chk_drop)

	_update_rows()

func _spin(min_v: float, max_v: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = " m"
	s.custom_minimum_size = Vector2(120, 0)
	if s.step >= 1.0:
		s.allow_greater = false
		s.rounded = true
	return s

func _row(label_text: String, control: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	hb.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	return hb

func _update_rows() -> void:
	var kind: int = _opt_profile.get_selected_id()
	(_rows["width"] as Control).visible = kind == PBSweep.ProfileKind.ROAD \
			or kind == PBSweep.ProfileKind.RIBBON
	(_rows["thickness"] as Control).visible = kind == PBSweep.ProfileKind.ROAD \
			or kind == PBSweep.ProfileKind.BARRIER
	(_rows["height"] as Control).visible = kind == PBSweep.ProfileKind.BARRIER
	(_rows["radius"] as Control).visible = kind == PBSweep.ProfileKind.PIPE
	(_rows["segments"] as Control).visible = kind == PBSweep.ProfileKind.PIPE

## Everything the plugin needs to build the sweep.
func get_spec() -> Dictionary:
	return {
		"kind": _opt_profile.get_selected_id(),
		"width": _spin_width.value,
		"thickness": _spin_thickness.value,
		"height": _spin_height.value,
		"radius": _spin_radius.value,
		"segments": int(_spin_segments.value),
		"spacing": _spin_spacing.value,
		"uv_repeat": _spin_uv.value,
		"closed": _chk_closed.button_pressed,
		"caps": _chk_caps.button_pressed,
		"drop_to_surface": _chk_drop.button_pressed,
	}
