extends MultiMeshInstance2D

## Renders every BoidBase in ONE batched draw call.
##
## This version keeps the original instance transform exactly the same
## as the triangle renderer. The only change is that the triangle mesh
## has been replaced with a centered textured quad.
##
## SETUP:
## - Add a MultiMeshInstance2D to your scene.
## - Attach this script.
## - Assign your boid texture to `boid_texture`.
## - Leave this node's position/rotation/scale at their defaults.
##
## The boid's GLOBAL position/rotation/scale are still used exactly as
## before, so spawning and movement are unchanged.

@export_group("Texture")

## The image used for every boid.
@export var boid_texture: Texture2D

## Size of the textured boid in world/pixel units.
## This is independent of the source image's native resolution.
@export var texture_size: Vector2 = Vector2(20.0, 20.0)


@export_group("Multimesh")

## Extra instance slots kept allocated beyond the current boid count.
@export var capacity_headroom: int = 64


func _ready() -> void:

	# Give MultiMeshInstance2D the texture directly.
	# This uses its normal CanvasItem texture handling.
	texture = boid_texture

	multimesh = MultiMesh.new()

	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = _build_boid_mesh()
	multimesh.instance_count = capacity_headroom


func _process(_delta: float) -> void:

	var boids: Array[BoidBase] = BoidBase.all_boids

	_ensure_capacity(
		boids.size() + capacity_headroom
	)

	var index: int = 0

	for boid in boids:

		if not is_instance_valid(boid):
			continue

		if boid.is_queued_for_deletion():
			continue

		# -----------------------------------------------------
		# THIS IS YOUR ORIGINAL TRANSFORM.
		# DO NOT CHANGE THIS.
		# -----------------------------------------------------

		multimesh.set_instance_transform_2d(
			index,
			Transform2D(
				boid.global_rotation,
				boid.global_scale,
				0.0,
				boid.global_position
			)
		)

		# Preserve the boid's module-driven colour.
		multimesh.set_instance_color(
			index,
			boid.draw_color
		)

		index += 1

	# Only draw the instances actually occupied this frame.
	multimesh.visible_instance_count = index


func _ensure_capacity(needed: int) -> void:

	if multimesh.instance_count >= needed:
		return

	# Grow geometrically rather than resizing for every birth.
	multimesh.instance_count = max(
		needed,
		multimesh.instance_count * 2
	)


func _build_boid_mesh() -> ArrayMesh:

	# ---------------------------------------------------------
	# CENTERED TEXTURED QUAD
	# ---------------------------------------------------------
	#
	# The old mesh was:
	#
	#     (10, 0)
	#     (-6, 5)
	#     (-6, -5)
	#
	# so its origin was effectively at the boid's center.
	#
	# This quad is also centered around (0, 0), which means the
	# exact same MultiMesh transform places the texture at the
	# exact same boid position.
	#

	var half_size: Vector2 = texture_size * 0.5

	var vertices := PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2( half_size.x, -half_size.y),
		Vector2( half_size.x,  half_size.y),

		Vector2(-half_size.x, -half_size.y),
		Vector2( half_size.x,  half_size.y),
		Vector2(-half_size.x,  half_size.y)
	])


	# Standard 0-1 UV coordinates.
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),

		Vector2(0.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0)
	])


	# White vertex colour means the MultiMesh instance colour
	# comes through unchanged.
	var colors := PackedColorArray([
		Color.WHITE,
		Color.WHITE,
		Color.WHITE,
		Color.WHITE,
		Color.WHITE,
		Color.WHITE
	])


	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors


	var mesh := ArrayMesh.new()

	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	return mesh
