## PBSweep — sweeps a cross-section profile along a 3D path.
##
## Environment presets for the same geometry machinery Trim Walls uses
## ([method PBShapeTrim.extrude_profile_along_path]): mitered frames, metre
## tiled UVs, shared-vertex welds and optional end caps. This class adds the
## road / barrier / pipe / ribbon profiles, Curve3D sampling and the UV repeat
## control.
##
## Winding: the presets are ordered CCW in the profile plane (x = side,
## y = up), which the sweep turns into OUTWARD normals — PoiBuilder's
## CCW-from-outside convention. The flat ribbon is the one OPEN profile and
## runs right-to-left so its single face points UP.
@tool
class_name PBSweep
extends RefCounted

enum ProfileKind {
	ROAD,
	BARRIER,
	PIPE,
	RIBBON,
}

## Minimum distance between two path points (metres). Closer points are the
## same node: the sweep would frame a zero-length segment and produce a
## degenerate ring.
const MIN_POINT_SPACING := 0.0005

# ==============================================================================
# Profiles
# ==============================================================================

static func profile_label(kind: int) -> String:
	match kind:
		ProfileKind.ROAD:
			return "Road (slab)"
		ProfileKind.BARRIER:
			return "Barrier / wall"
		ProfileKind.PIPE:
			return "Pipe"
		ProfileKind.RIBBON:
			return "Flat ribbon"
	return "Road (slab)"

static func is_closed_profile(kind: int) -> bool:
	return kind != ProfileKind.RIBBON

## The cross-section for `kind`, in metres. See the file header for the
## winding contract.
static func profile_points(kind: int, p: Dictionary = {}) -> PackedVector2Array:
	match kind:
		ProfileKind.ROAD:
			var w: float = maxf(0.05, float(p.get("width", 3.0)))
			var t: float = maxf(0.01, float(p.get("thickness", 0.2)))
			return PackedVector2Array([
				Vector2(-w * 0.5, -t), Vector2(w * 0.5, -t),
				Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, 0.0),
			])
		ProfileKind.BARRIER:
			var thick: float = maxf(0.02, float(p.get("thickness", 0.25)))
			var h: float = maxf(0.02, float(p.get("height", 1.0)))
			return PackedVector2Array([
				Vector2(-thick * 0.5, 0.0), Vector2(thick * 0.5, 0.0),
				Vector2(thick * 0.5, h), Vector2(-thick * 0.5, h),
			])
		ProfileKind.PIPE:
			var r: float = maxf(0.02, float(p.get("radius", 0.25)))
			var segs: int = maxi(3, int(p.get("segments", 12)))
			var pts := PackedVector2Array()
			for i in range(segs):
				var a: float = TAU * float(i) / float(segs)
				pts.append(Vector2(cos(a), sin(a)) * r)
			return pts
		ProfileKind.RIBBON:
			var rw: float = maxf(0.05, float(p.get("width", 3.0)))
			# Right-to-left: the sweep's face normal then points UP.
			return PackedVector2Array([Vector2(rw * 0.5, 0.0), Vector2(-rw * 0.5, 0.0)])
	return PackedVector2Array()

# ==============================================================================
# Path sampling
# ==============================================================================

## Arc-length samples of `curve` every `spacing` metres. The bake interval of
## a COPY is lowered so short curves are not sampled from a 5 m default bake;
## the caller's curve resource is never mutated.
static func sample_curve(curve: Curve3D, spacing: float = 1.0, closed: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null:
		return out
	var step: float = maxf(0.05, spacing)
	var tmp: Curve3D = curve.duplicate() as Curve3D
	if tmp == null:
		return out
	tmp.bake_interval = minf(tmp.bake_interval, step * 0.5)
	var length: float = tmp.get_baked_length()
	if length < 0.01:
		return out
	var segments: int = maxi(1, int(ceil(length / step)))
	for i in range(segments + 1):
		var d: float = minf(length, float(i) * length / float(segments))
		out.append(tmp.sample_baked(d, true))
	if closed and out.size() > 3 and out[out.size() - 1].distance_to(out[0]) < MIN_POINT_SPACING * 2.0:
		out.remove_at(out.size() - 1)
	return out

## World-space samples of a Path3D (falls back to the local transform when
## the node is not in a tree, matching PBTrimWallsTool.face_world_polygon).
static func sample_path_node(path_node: Path3D, spacing: float = 1.0, closed: bool = false) -> PackedVector3Array:
	if path_node == null or path_node.curve == null:
		return PackedVector3Array()
	var xf: Transform3D = path_node.global_transform if path_node.is_inside_tree() else path_node.transform
	var local := sample_curve(path_node.curve, spacing, closed)
	var out := PackedVector3Array()
	for p in local:
		out.append(xf * p)
	return out

# ==============================================================================
# Build
# ==============================================================================

## Sweeps `kind`'s profile along `points`.
##
## `p` keys: width, thickness, height, radius, segments, uv_repeat (metres
## per texture repeat; 1.0 = the plugin's 1 m convention), caps (bool).
static func build(points: PackedVector3Array, kind: int, p: Dictionary = {},
		closed_path: bool = false) -> PBMeshData:
	var path := _dedupe(points)
	var profile := profile_points(kind, p)
	if path.size() < 2 or profile.size() < 2:
		return null
	var closed: bool = closed_path and path.size() >= 3
	# A vertical run (a road down a cliff, a pipe riser) makes the sweep's
	# global UP frame parallel to the tangent and collapses it; a horizontal
	# reference keeps the frames valid for those runs.
	var up := Vector3.UP
	for i in range(1, path.size()):
		var d: Vector3 = (path[i] - path[i - 1]).normalized()
		if absf(d.dot(Vector3.UP)) > 0.98:
			up = Vector3.BACK
			break
	var md := PBShapeTrim.extrude_profile_along_path(
			profile, path, up, closed, is_closed_profile(kind),
			PackedInt32Array(), bool(p.get("caps", true)))
	if md == null:
		return null
	var repeat: float = float(p.get("uv_repeat", 1.0))
	if repeat > 0.0 and not is_equal_approx(repeat, 1.0) \
			and md.textures0.size() == md.positions.size():
		var scale: float = 1.0 / repeat
		for i in range(md.textures0.size()):
			md.textures0[i] = md.textures0[i] * scale
	if md.materials.is_empty():
		var def := PBMeshData.get_default_material()
		if def != null:
			md.materials.append(def)
	md.get_texture_anchor()
	return md

## Convenience: sample the selected Path3D and sweep it.
static func build_from_path(path_node: Path3D, kind: int, p: Dictionary = {}) -> PBMeshData:
	var closed: bool = bool(p.get("closed", false))
	var spacing: float = float(p.get("spacing", 1.0))
	return build(sample_path_node(path_node, spacing, closed), kind, p, closed)

## Drops consecutive points closer than MIN_POINT_SPACING (the Curve3D end
## duplicate and hand-drawn coincident nodes).
static func _dedupe(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > MIN_POINT_SPACING:
			out.append(p)
	return out
