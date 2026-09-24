extends ColorRect

@export_group("Land")
@export var land_sprite_path: NodePath

@export_group("Camera")
@export var camera_path: NodePath

@export_group("Water")
@export var base_tile: float = 5.0

var camera: Camera2D
var land_sprite: Sprite2D
var material_instance: ShaderMaterial

var _last_texture: Texture2D
var _last_zoom: float = -1.0


func _ready() -> void:
	material_instance = material as ShaderMaterial

	if material_instance == null:
		push_warning("ColorRect needs a ShaderMaterial.")
		return


	# --------------------------------------------------------
	# Find Land Sprite2D
	# --------------------------------------------------------

	if land_sprite_path != NodePath():
		land_sprite = get_node_or_null(
			land_sprite_path
		) as Sprite2D

	if land_sprite == null:
		push_warning(
			"Could not find the Land Sprite2D."
		)


	# --------------------------------------------------------
	# Find Camera2D
	# --------------------------------------------------------

	if camera_path != NodePath():
		camera = get_node_or_null(
			camera_path
		) as Camera2D

	if camera == null:
		camera = get_viewport().get_camera_2d()

	if camera == null:
		push_warning(
			"Could not find a Camera2D."
		)


	# --------------------------------------------------------
	# Initial setup
	# --------------------------------------------------------

	_update_land_texture()
	_update_camera()


func _process(_delta: float) -> void:
	if material_instance == null:
		return

	_update_camera()
	_update_land_texture()


# ============================================================
# CAMERA
# ============================================================

func _update_camera() -> void:
	if camera == null:
		return

	var zoom_value: float = camera.zoom.x

	# Don't update the shader unnecessarily.
	if is_equal_approx(
		zoom_value,
		_last_zoom
	):
		return

	_last_zoom = zoom_value

	material_instance.set_shader_parameter(
		"camera_zoom",
		zoom_value
	)


# ============================================================
# LAND TEXTURE
# ============================================================

func _update_land_texture() -> void:
	if land_sprite == null:
		return

	var texture: Texture2D = land_sprite.texture

	if texture == null:
		return

	# Texture hasn't changed.
	if texture == _last_texture:
		return

	_last_texture = texture


	# --------------------------------------------------------
	# Give the shader the Sprite2D's texture.
	# --------------------------------------------------------

	material_instance.set_shader_parameter(
		"land_texture",
		texture
	)


	# --------------------------------------------------------
	# Tell shader the size of one texture pixel in UV space.
	# --------------------------------------------------------

	var size := Vector2(
		texture.get_width(),
		texture.get_height()
	)

	var pixel_size := Vector2(
		1.0 / size.x,
		1.0 / size.y
	)

	material_instance.set_shader_parameter(
		"land_pixel_size",
		pixel_size
	)


	# --------------------------------------------------------
	# Water tiling.
	# --------------------------------------------------------

	material_instance.set_shader_parameter(
		"tile",
		base_tile
	)
