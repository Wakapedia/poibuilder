## PBPathArray — distributes copies of a mesh along a Curve3D.
##
## Purely geometric and headless-testable: it produces world-space
## Transforms; the plugin creates the actual nodes. Used for picket fences,
## posts, guard rails, lamp posts, bollards, bridge sections and any other
## REPEATED structure along a route (Sweep handles continuous cross-sections).
##
## Orientation convention: with "align to path" on, each copy's -Z axis points
## along the travel direction (Godot's `Basis.looking_at` convention), so the
## copy's local +X is its left side. "Side offset" moves along that local +X.
##
## `surface` is an optional Callable `func(world_pos) -> Dictionary` returning
## {"position": Vector3, "normal": Vector3} for the terrain/floor under a
## sample (empty on a miss). The plugin supplies a physics raycast; tests
## supply a plane. Sampling order and RNG draws never depend on it, so the
## result is deterministic.
@tool
class_name PBPathArray
extends RefCounted

## Collision strategy for the generated copies (the plugin builds the bodies;
## the core only carries the choice in the spec).
enum CollisionMode {
	NONE,
	BOX,
	TRIMESH,
}

## Minimum distance between samples (metres).
const MIN_STEP := 0.0001

static func compute_transforms(curve: Curve3D, xf: Transform3D, spec: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if curve == null:
		return out
	var mode := String(spec.get("mode", "spacing"))
	var spacing := maxf(0.01, float(spec.get("spacing", 2.0)))
	var count := maxi(1, int(spec.get("count", 5)))
	var start_margin := maxf(0.0, float(spec.get("start_margin", 0.0)))
	var end_margin := maxf(0.0, float(spec.get("end_margin", 0.0)))
	var closed := bool(spec.get("closed", false))

	var tmp := curve.duplicate() as Curve3D
	if tmp == null:
		return out
	tmp.bake_interval = minf(tmp.bake_interval, 0.05)
	var length: float = tmp.get_baked_length()
	if length < 0.01:
		return out
	var usable: float = maxf(0.0, length - start_margin - end_margin)
	if usable <= MIN_STEP:
		return out

	var dists := PackedFloat32Array()
	if mode == "count":
		if count == 1:
			dists.append(start_margin + usable * 0.5)
		else:
			var span: float = usable if not closed else usable
			var denom: float = float(count - 1) if not closed else float(count)
			for i in range(count):
				dists.append(start_margin + span * float(i) / denom)
	else:
		if closed:
			# Exclusive end: a copy at `length` would land on the copy at 0.
			var n: int = maxi(1, int(floor(usable / spacing + 0.00001)))
			for i in range(n):
				dists.append(start_margin + float(i) * spacing)
		else:
			var n: int = int(floor(usable / spacing + 0.00001)) + 1
			for i in range(n):
				dists.append(start_margin + float(i) * spacing)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var jitter_yaw: float = deg_to_rad(maxf(0.0, float(spec.get("jitter_yaw", 0.0))))
	var jitter_scale: float = maxf(0.0, float(spec.get("jitter_scale", 0.0))) / 100.0
	var surface: Callable = spec.get("surface", Callable())
	var align_path: bool = bool(spec.get("align_to_path", true))
	var align_normal: bool = bool(spec.get("align_to_normal", false))
	var embed: float = float(spec.get("embed", 0.0))
	var side_offset: float = float(spec.get("side_offset", 0.0))
	var height_offset: float = float(spec.get("height_offset", 0.0))
	var eps: float = minf(0.05, maxf(0.001, length * 0.01))

	for d in dists:
		var p_world: Vector3 = xf * tmp.sample_baked(d, true)
		var a_local: Vector3 = tmp.sample_baked(clampf(d - eps, 0.0, length), true)
		var b_local: Vector3 = tmp.sample_baked(clampf(d + eps, 0.0, length), true)
		var tangent_world: Vector3 = xf.basis * (b_local - a_local)
		if tangent_world.length_squared() < 0.00000001:
			tangent_world = xf.basis * Vector3.FORWARD
		tangent_world = tangent_world.normalized()

		var pos := p_world
		var up: Vector3 = (xf.basis * Vector3.UP).normalized()
		if surface.is_valid():
			var hit: Dictionary = surface.call(p_world)
			if not hit.is_empty():
				pos = hit.get("position", p_world)
				var n: Vector3 = hit.get("normal", up)
				if n.length_squared() > 0.00000001:
					up = n.normalized()

		var basis := Basis.IDENTITY
		if align_path:
			var up_use: Vector3 = up if align_normal else Vector3.UP
			if absf(tangent_world.dot(up_use)) > 0.99:
				up_use = Vector3.BACK
			basis = Basis.looking_at(tangent_world, up_use)
		elif align_normal:
			basis = Basis(Quaternion(Vector3.UP, up))

		pos += up * (-embed)
		pos += basis.x * side_offset
		pos += Vector3.UP * height_offset

		if jitter_yaw > 0.0:
			basis = basis.rotated(up, rng.randf_range(-jitter_yaw, jitter_yaw))
		else:
			rng.randf()  # keep the RNG stream aligned across jitter settings
		if jitter_scale > 0.0:
			basis = basis.scaled(Vector3.ONE * (1.0 + rng.randf_range(-jitter_scale, jitter_scale)))
		else:
			rng.randf()
		out.append(Transform3D(basis, pos))
	return out
