extends Node3D

# Builds the world in code instead of hand-placing nodes in a scene file.
# Once you're comfortable in the Godot editor, feel free to drag these into
# the scene tree yourself instead - this is just the fastest way to get a
# first playable version in front of you.

const PLAYER_SCENE := preload("res://player.tscn")

func _ready() -> void:
	_add_light()
	_add_sky()
	_add_ground()
	_add_player()

func _add_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)

func _add_sky() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(50, 1, 50)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.3)
	mesh_instance.material_override = mat
	ground.add_child(mesh_instance)

	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(50, 1, 50)
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = box_shape
	ground.add_child(collision_shape)

	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

func _add_player() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 1, 0)
	add_child(player)
