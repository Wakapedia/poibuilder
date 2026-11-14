## PBPathArray — distribution math for repeated structures along a route.
## These lock the placement rules that silently look wrong in the viewport:
## closed-loop seams, count vs spacing, margins, orientation and determinism.
extends GutTest

func _line(length: float = 10.0) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(0, 0, length))
	return c

func _square_loop(size: float = 10.0) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(size, 0, 0))
	c.add_point(Vector3(size, 0, size))
	c.add_point(Vector3(0, 0, size))
	c.add_point(Vector3.ZERO)
	return c

func test_spacing_mode_includes_both_endpoints():
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "spacing", "spacing": 2.5})
	assert_eq(t.size(), 5, "0, 2.5, 5, 7.5, 10")
	assert_almost_eq(t[0].origin.z, 0.0, 0.001)
	assert_almost_eq(t[4].origin.z, 10.0, 0.001)

func test_count_mode_distributes_evenly():
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 4})
	assert_eq(t.size(), 4)
	assert_almost_eq(t[0].origin.z, 0.0, 0.001)
	assert_almost_eq(t[1].origin.z, 10.0 / 3.0, 0.01)
	assert_almost_eq(t[3].origin.z, 10.0, 0.001)

func test_margins_inset_the_run():
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 3, "start_margin": 2.0, "end_margin": 2.0})
	assert_eq(t.size(), 3)
	assert_almost_eq(t[0].origin.z, 2.0, 0.001)
	assert_almost_eq(t[1].origin.z, 5.0, 0.01)
	assert_almost_eq(t[2].origin.z, 8.0, 0.001)

func test_closed_loop_does_not_duplicate_the_seam():
	var t := PBPathArray.compute_transforms(_square_loop(10.0), Transform3D.IDENTITY,
			{"mode": "spacing", "spacing": 8.0, "closed": true})
	assert_eq(t.size(), 5, "40 m loop every 8 m: 0, 8, 16, 24, 32 — no copy at 40")
	for i in range(t.size()):
		for j in range(i + 1, t.size()):
			assert_gt(t[i].origin.distance_to(t[j].origin), 1.0, "No two posts on the same spot")

func test_align_to_path_points_minus_z_along_travel():
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 2, "align_to_path": true})
	assert_almost_eq(t[0].basis.z.z, -1.0, 0.01, "-Z faces the travel direction")
	assert_almost_eq(t[0].basis.y.y, 1.0, 0.01, "Up stays up")

func test_side_offset_moves_along_the_local_x_axis():
	var spec := {"mode": "count", "count": 2, "align_to_path": true, "side_offset": 1.0}
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY, spec)
	assert_true(t[0].origin.is_equal_approx(t[0].basis.x),
		"One metre along the copy's local +X is exactly where the copy lands")

func test_surface_snap_places_on_the_hit_and_embeds():
	var flat := func(p: Vector3) -> Dictionary:
		return {"position": Vector3(p.x, 3.0, p.z), "normal": Vector3.UP}
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 2, "surface": flat, "embed": 0.5})
	assert_almost_eq(t[0].origin.y, 2.5, 0.001, "Dropped to the surface, then sunk by embed")

func test_align_to_normal_without_path_alignment():
	var tilted := Vector3(1, 1, 0).normalized()
	var surf := func(p: Vector3) -> Dictionary:
		return {"position": p, "normal": tilted}
	var t := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 1, "align_to_path": false,
			"align_to_normal": true, "surface": surf})
	assert_almost_eq(t[0].basis.y.x, tilted.x, 0.01)
	assert_almost_eq(t[0].basis.y.y, tilted.y, 0.01, "The copy's up follows the surface normal")

func test_jitter_is_deterministic_per_seed():
	var spec := {"mode": "count", "count": 4, "align_to_path": true,
		"jitter_yaw": 20.0, "jitter_scale": 15.0, "seed": 7}
	var a := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY, spec)
	var b := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY, spec)
	for i in range(a.size()):
		assert_true(a[i].is_equal_approx(b[i]), "Same seed, same placement")
	var other := PBPathArray.compute_transforms(_line(10.0), Transform3D.IDENTITY,
			{"mode": "count", "count": 4, "align_to_path": true,
			"jitter_yaw": 20.0, "jitter_scale": 15.0, "seed": 8})
	var differs := false
	for i in range(a.size()):
		if not a[i].is_equal_approx(other[i]):
			differs = true
	assert_true(differs, "A different seed changes the placement")

func test_path_transform_is_applied():
	var xf := Transform3D(Basis(), Vector3(5, 0, 0))
	var t := PBPathArray.compute_transforms(_line(10.0), xf, {"mode": "count", "count": 2})
	assert_almost_eq(t[0].origin.x, 5.0, 0.001)

func test_degenerate_curve_returns_nothing():
	assert_eq(PBPathArray.compute_transforms(null, Transform3D.IDENTITY, {}).size(), 0)
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	assert_eq(PBPathArray.compute_transforms(c, Transform3D.IDENTITY, {}).size(), 0)
