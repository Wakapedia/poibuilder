## PBSweep — road / barrier / pipe / ribbon sweeps along straight, curved and
## closed paths. Locks the two things a profile sweep gets wrong silently:
## the profile winding (outward normals — inside-out roads render black) and
## the end caps (missing caps leak light and break watertightness).
extends GutTest

const ROAD := PBSweep.ProfileKind.ROAD
const PIPE := PBSweep.ProfileKind.PIPE
const RIBBON := PBSweep.ProfileKind.RIBBON

func _straight(length: float = 10.0) -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, length)])

func _square_loop(size: float = 10.0) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3.ZERO, Vector3(size, 0, 0), Vector3(size, 0, size), Vector3(0, 0, size),
	])

func _face_normal(data: PBMeshData, face_index: int) -> Vector3:
	var face: PBFace = data.faces[face_index]
	var idx := face.get_indexes()
	if idx.size() < 3:
		return Vector3.ZERO
	var p0: Vector3 = data.positions[idx[0]]
	var p1: Vector3 = data.positions[idx[1]]
	var p2: Vector3 = data.positions[idx[2]]
	return (p1 - p0).cross(p2 - p0).normalized()

func _count_faces_facing(data: PBMeshData, dir: Vector3) -> int:
	var n := 0
	for i in range(data.face_count()):
		if _face_normal(data, i).dot(dir) > 0.99:
			n += 1
	return n

func _faces_facing(data: PBMeshData, dir: Vector3) -> Array[int]:
	var out: Array[int] = []
	for i in range(data.face_count()):
		if _face_normal(data, i).dot(dir) > 0.99:
			out.append(i)
	return out

func _uv_u_span(data: PBMeshData, face_index: int) -> float:
	var idx := data.faces[face_index].get_indexes()
	var lo := INF
	var hi := -INF
	for k in idx:
		lo = minf(lo, data.textures0[k].x)
		hi = maxf(hi, data.textures0[k].x)
	return hi - lo

func _perimeter_edge_total(data: PBMeshData) -> int:
	var total := 0
	for face in data.faces:
		if face != null:
			total += face.get_edges().size()
	return total

# ==============================================================================
# Profiles
# ==============================================================================

func test_road_profile_is_a_sized_slab():
	var pts := PBSweep.profile_points(ROAD, {"width": 4.0, "thickness": 0.25})
	assert_eq(pts.size(), 4, "A road is a closed 4-point slab profile")
	assert_almost_eq(pts[0].y, -0.25, 0.0001, "The slab bottom sits a thickness below the path")
	assert_almost_eq(pts[1].x, 2.0, 0.0001, "Profile is centred on the path")
	assert_true(PBSweep.is_closed_profile(ROAD))
	assert_false(PBSweep.is_closed_profile(RIBBON))

func test_pipe_profile_is_a_closed_ring():
	var pts := PBSweep.profile_points(PIPE, {"radius": 0.5, "segments": 8})
	assert_eq(pts.size(), 8)
	for p in pts:
		assert_almost_eq(p.length(), 0.5, 0.0001, "Every ring point sits on the radius")

# ==============================================================================
# Straight sweeps
# ==============================================================================

func test_straight_road_builds_slab_with_outward_normals_and_caps():
	var data := PBSweep.build(_straight(10.0), ROAD, {"width": 4.0, "thickness": 0.2})
	assert_not_null(data)
	# 4 side quads + 2 end caps.
	assert_eq(data.face_count(), 6, "4 side faces and 2 caps")
	assert_eq(data.positions.size(), 24, "4 corners per side face + 4 per cap")
	var lo := INF
	var hi := -INF
	for p in data.positions:
		assert_false(is_nan(p.x) or is_nan(p.y) or is_nan(p.z), "No NaN positions")
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	assert_almost_eq(lo, -0.2, 0.0001, "Slab bottom")
	assert_almost_eq(hi, 0.0, 0.0001, "Slab top sits on the path")
	assert_eq(_count_faces_facing(data, Vector3.UP), 1, "One top face, outward UP")
	assert_eq(_count_faces_facing(data, Vector3.DOWN), 1, "One bottom face, outward DOWN")
	assert_eq(_count_faces_facing(data, Vector3.RIGHT), 1)
	assert_eq(_count_faces_facing(data, Vector3.LEFT), 1)
	assert_eq(_count_faces_facing(data, Vector3.BACK), 1, "End cap faces +Z")
	assert_eq(_count_faces_facing(data, Vector3.FORWARD), 1, "Start cap faces -Z")
	assert_eq(_perimeter_edge_total(data), data.get_common_edges().size() * 2,
		"Capped road is watertight: every perimeter edge is used twice")

func test_pipe_sweep_normals_point_away_from_the_axis():
	var data := PBSweep.build(_straight(6.0), PIPE, {"radius": 0.3, "segments": 8})
	assert_not_null(data)
	assert_eq(data.face_count(), 10, "8 side quads + 2 caps")
	for i in range(data.face_count()):
		var n := _face_normal(data, i)
		if absf(n.z) > 0.9:
			continue  # end cap
		var seen := {}
		var center := Vector3.ZERO
		for k in data.faces[i].get_indexes():
			seen[k] = true
		for k in seen:
			center += data.positions[k]
		center /= float(seen.size())
		var radial := Vector3(center.x, center.y, 0.0)
		assert_gt(n.dot(radial.normalized()), 0.9, "Pipe side normal points radially outward")

func test_ribbon_is_open_profile_with_no_caps():
	var data := PBSweep.build(_straight(10.0), RIBBON, {"width": 4.0})
	assert_not_null(data)
	assert_eq(data.face_count(), 1, "A ribbon is one quad per path segment, no caps")
	assert_eq(_count_faces_facing(data, Vector3.UP), 1, "Ribbon faces UP")

func test_vertical_run_does_not_collapse_the_frame():
	var data := PBSweep.build(PackedVector3Array([Vector3.ZERO, Vector3(0, 10, 0)]), ROAD,
			{"width": 2.0, "thickness": 0.2})
	assert_not_null(data, "A vertical run still builds")
	assert_eq(data.face_count(), 6)
	for p in data.positions:
		assert_false(is_nan(p.x) or is_nan(p.y) or is_nan(p.z), "No NaN positions on a riser")
	assert_eq(_count_faces_facing(data, Vector3.UP), 1, "One end cap faces up")
	assert_eq(_count_faces_facing(data, Vector3.DOWN), 1, "One end cap faces down")

# ==============================================================================
# Closed paths, UVs, sampling
# ==============================================================================

func test_closed_loop_has_no_caps_and_is_watertight():
	var data := PBSweep.build(_square_loop(10.0), ROAD,
			{"width": 2.0, "thickness": 0.2}, true)
	assert_not_null(data)
	assert_eq(data.face_count(), 16, "4 path segments x 4 profile segments, no caps")
	assert_eq(_perimeter_edge_total(data), data.get_common_edges().size() * 2,
		"Closed road loop is watertight")

func test_uv_repeat_scales_the_metre_tiling():
	var one := PBSweep.build(_straight(10.0), ROAD, {"width": 2.0, "thickness": 0.2})
	var two := PBSweep.build(_straight(10.0), ROAD,
			{"width": 2.0, "thickness": 0.2, "uv_repeat": 2.0})
	var top_one := _faces_facing(one, Vector3.UP)[0]
	var top_two := _faces_facing(two, Vector3.UP)[0]
	assert_almost_eq(_uv_u_span(one, top_one), 10.0, 0.001,
		"The default tiling repeats every metre along a 10 m run")
	assert_almost_eq(_uv_u_span(two, top_two), 5.0, 0.001,
		"uv_repeat 2 stretches each repeat over 2 m")

func test_curve_sampling_follows_arc_length():
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 10))
	curve.add_point(Vector3(10, 0, 10))
	var pts := PBSweep.sample_curve(curve, 1.0, false)
	assert_gt(pts.size(), 18, "A ~20 m curve sampled every metre")
	for i in range(1, pts.size()):
		assert_almost_eq(pts[i - 1].distance_to(pts[i]), 1.0, 0.15,
			"Sampled points are one metre apart along the curve")

func test_coincident_points_are_dropped_before_sweeping():
	var doubled := PackedVector3Array([
		Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 10), Vector3(0, 0, 10),
	])
	var data := PBSweep.build(doubled, ROAD, {"width": 2.0, "thickness": 0.2})
	assert_not_null(data)
	assert_eq(data.face_count(), 6, "Coincident nodes must not add zero-length segments")

func test_degenerate_input_returns_null():
	assert_null(PBSweep.build(PackedVector3Array(), ROAD))
	assert_null(PBSweep.build(PackedVector3Array([Vector3.ZERO]), ROAD))
	assert_null(PBSweep.build(PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), ROAD))

func test_build_from_path_applies_the_node_transform():
	var path_node := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 5))
	path_node.curve = curve
	path_node.position = Vector3(10, 0, 0)
	var data := PBSweep.build_from_path(path_node, ROAD,
			{"width": 2.0, "thickness": 0.2, "spacing": 1.0})
	assert_not_null(data)
	for p in data.positions:
		assert_almost_eq(p.x, 10.0, 1.01, "The node's transform is applied to the samples")
	path_node.free()
