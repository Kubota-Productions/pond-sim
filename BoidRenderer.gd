extends MultiMeshInstance2D

## Renders every BoidBase in ONE batched draw call instead of each boid
## doing its own individual _draw() call. Once the O(n^2) simulation cost
## was fixed, ~700 separate CanvasItem draw calls (one per boid, reissued
## every single frame) became the next bottleneck — this replaces that with
## a single MultiMesh draw regardless of how many boids exist.
##
## SETUP: add a MultiMeshInstance2D node to your scene and attach this
## script to it. Leave that node's own Transform2D (position/rotation/scale)
## at the default identity — this script reads each boid's GLOBAL
## position/rotation/scale, so it doesn't matter where in the tree the
## renderer node sits relative to the boids themselves, as long as the
## renderer node itself isn't offset, rotated or scaled. Nothing else needs
## configuring: the triangle mesh and the instance buffer are both built
## and sized automatically.
##
## IMPORTANT: BoidBase no longer draws itself (see _compute_draw_color() in
## BoidBase.gd) — this node is now the only thing putting boids on screen.

## Extra instance slots kept allocated beyond the current boid count, so
## population growth from breeding doesn't force a buffer resize on every
## single birth.
@export var capacity_headroom: int = 64


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = _build_boid_mesh()
	multimesh.instance_count = capacity_headroom


func _process(_delta: float) -> void:

	var boids: Array[BoidBase] = BoidBase.all_boids

	_ensure_capacity(boids.size() + capacity_headroom)

	var index: int = 0

	for boid in boids:

		if not is_instance_valid(boid):
			continue

		if boid.is_queued_for_deletion():
			continue

		multimesh.set_instance_transform_2d(
			index,
			Transform2D(
				boid.global_rotation,
				boid.global_scale,
				0.0,
				boid.global_position
			)
		)

		multimesh.set_instance_color(
			index,
			boid.draw_color
		)

		index += 1

	# Slots beyond `index` still hold stale data from a previous frame (or
	# nothing at all), but visible_instance_count keeps them from being
	# drawn, so there's no need to clear them out individually.
	multimesh.visible_instance_count = index


func _ensure_capacity(needed: int) -> void:

	if multimesh.instance_count >= needed:
		return

	# Grow geometrically (double, or exactly what's needed if that's more)
	# rather than by a fixed step, so a long-running simulation with lots of
	# breeding doesn't pay for a buffer resize on every single new boid.
	multimesh.instance_count = max(
		needed,
		multimesh.instance_count * 2
	)


func _build_boid_mesh() -> ArrayMesh:

	# Matches the triangle every boid used to draw individually via
	# draw_colored_polygon() in the old BoidBase._draw().
	var points := PackedVector2Array([
		Vector2(10, 0),
		Vector2(-6, 5),
		Vector2(-6, -5)
	])

	# Plain white vertex colors: MultiMesh multiplies the mesh's vertex
	# color by each instance's set_instance_color(), so white here means
	# the instance color comes through unmodified — same solid-color look
	# as before.
	var colors := PackedColorArray([
		Color.WHITE,
		Color.WHITE,
		Color.WHITE
	])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh
