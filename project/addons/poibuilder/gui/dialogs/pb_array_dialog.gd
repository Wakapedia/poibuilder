## PBArrayDialog — options for repeating a mesh along the selected Path3D.
##
## Placement math lives in PBPathArray; the plugin builds the nodes and their
## colliders. Settings persist for the session because the plugin keeps one
## instance.
@tool
class_name PBArrayDialog
extends ConfirmationDialog

var _opt_mode: OptionButton
var _spin_spacing: SpinBox
var _spin_count: SpinBox
var _spin_start_margin: SpinBox
var _spin_end_margin: SpinBox
var _chk_align_path: CheckBox
var _chk_drop: CheckBox
var _chk_align_normal: CheckBox
var _spin_embed: SpinBox
var _spin_side: SpinBox
var _spin_height: SpinBox
var _opt_collision: OptionButton
var _spin_jitter_yaw: SpinBox
var _spin_jitter_scale: SpinBox
var _spin_seed: SpinBox
var _chk_closed: CheckBox
var _row_spacing: Control
var _row_count: Control

func _init() -> void:
	title = "Array Along Path"
	ok_button_text = "Array"
	min_size = Vector2(400, 0)
	_build_ui()

func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var info := Label.new()
	info.text = "Select the Path3D and the mesh to repeat (one copy per placement)."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	vb.add_child(HSeparator.new())

	_opt_mode = OptionButton.new()
	_opt_mode.add_item("By spacing", 0)
	_opt_mode.add_item("By count", 1)
	_opt_mode.item_selected.connect(func(_i: int) -> void: _update_rows())
	vb.add_child(_row("Distribute", _opt_mode))
	_spin_spacing = _spin(0.05, 100.0, 0.05, 2.5)
	_row_spacing = _row("Spacing", _spin_spacing)
	vb.add_child(_row_spacing)
	_spin_count = _spin(1.0, 500.0, 1.0, 10.0)
	_spin_count.suffix = ""
	_row_count = _row("Copies", _spin_count)
	vb.add_child(_row_count)
	_spin_start_margin = _spin(0.0, 500.0, 0.05, 0.0)
	vb.add_child(_row("Start margin", _spin_start_margin))
	_spin_end_margin = _spin(0.0, 500.0, 0.05, 0.0)
	vb.add_child(_row("End margin", _spin_end_margin))

	vb.add_child(HSeparator.new())
	_chk_align_path = CheckBox.new()
	_chk_align_path.text = "Align to path"
	_chk_align_path.button_pressed = true
	_chk_align_path.tooltip_text = "The copy's -Z axis follows the travel direction (its local +X is the side)."
	vb.add_child(_chk_align_path)
	_chk_drop = CheckBox.new()
	_chk_drop.text = "Drop to surface"
	_chk_drop.tooltip_text = "Raycast each placement onto the scene collision (terrain, floors). Misses keep the path height."
	vb.add_child(_chk_drop)
	_chk_align_normal = CheckBox.new()
	_chk_align_normal.text = "Align to surface normal"
	_chk_align_normal.tooltip_text = "Tilt each copy to the surface it stands on (needs Drop to surface)."
	vb.add_child(_chk_align_normal)
	_spin_embed = _spin(-5.0, 5.0, 0.01, 0.0)
	vb.add_child(_row("Embed depth", _spin_embed))
	_spin_side = _spin(-100.0, 100.0, 0.05, 0.0)
	vb.add_child(_row("Side offset", _spin_side))
	_spin_height = _spin(-100.0, 100.0, 0.05, 0.0)
	vb.add_child(_row("Height offset", _spin_height))

	vb.add_child(HSeparator.new())
	_opt_collision = OptionButton.new()
	_opt_collision.add_item("None", PBPathArray.CollisionMode.NONE)
	_opt_collision.add_item("Box per copy (cheap)", PBPathArray.CollisionMode.BOX)
	_opt_collision.add_item("Trimesh per copy (accurate)", PBPathArray.CollisionMode.TRIMESH)
	_opt_collision.select(1)
	_opt_collision.tooltip_text = "Box is the right pick for fences, posts and pickets; trimesh for walkable/blocking surfaces."
	vb.add_child(_row("Collision", _opt_collision))

	vb.add_child(HSeparator.new())
	_spin_jitter_yaw = _spin(0.0, 180.0, 1.0, 0.0)
	_spin_jitter_yaw.suffix = " deg"
	vb.add_child(_row("Random yaw", _spin_jitter_yaw))
	_spin_jitter_scale = _spin(0.0, 100.0, 1.0, 0.0)
	_spin_jitter_scale.suffix = " %"
	vb.add_child(_row("Random scale", _spin_jitter_scale))
	_spin_seed = _spin(0.0, 1000000.0, 1.0, 0.0)
	_spin_seed.suffix = ""
	vb.add_child(_row("Seed", _spin_seed))
	_chk_closed = CheckBox.new()
	_chk_closed.text = "Closed loop"
	_chk_closed.tooltip_text = "Do not place a copy on top of the first one at the seam."
	vb.add_child(_chk_closed)

	_update_rows()

func _spin(min_v: float, max_v: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = " m"
	s.custom_minimum_size = Vector2(120, 0)
	if step >= 1.0:
		s.rounded = true
	return s

func _row(label_text: String, control: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	hb.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	return hb

func _update_rows() -> void:
	var by_count: bool = _opt_mode.get_selected_id() == 1
	_row_spacing.visible = not by_count
	_row_count.visible = by_count

func get_spec() -> Dictionary:
	return {
		"mode": "count" if _opt_mode.get_selected_id() == 1 else "spacing",
		"spacing": _spin_spacing.value,
		"count": int(_spin_count.value),
		"start_margin": _spin_start_margin.value,
		"end_margin": _spin_end_margin.value,
		"align_to_path": _chk_align_path.button_pressed,
		"align_to_normal": _chk_align_normal.button_pressed,
		"drop_to_surface": _chk_drop.button_pressed,
		"embed": _spin_embed.value,
		"side_offset": _spin_side.value,
		"height_offset": _spin_height.value,
		"collision": _opt_collision.get_selected_id(),
		"jitter_yaw": _spin_jitter_yaw.value,
		"jitter_scale": _spin_jitter_scale.value,
		"seed": int(_spin_seed.value),
		"closed": _chk_closed.button_pressed,
	}
