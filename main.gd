extends Node3D

# Builds the world in code instead of hand-placing nodes in a scene file.
# Once you're comfortable in the Godot editor, feel free to drag these into
# the scene tree yourself instead - this is just the fastest way to get a
# first playable version in front of you.

const PLAYER_SCENE := preload("res://player.tscn")

const GROUND_SIZE := 200.0
const NUM_ROCKS := 15
const NUM_TREES := 15
const SPAWN_CLEAR_RADIUS := 8.0

func _ready() -> void:
	_add_light()
	_add_sky()
	_add_ground()
	_scatter_landmarks()
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
	box_mesh.size = Vector3(GROUND_SIZE, 1, GROUND_SIZE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.3)
	mesh_instance.material_override = mat
	ground.add_child(mesh_instance)

	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(GROUND_SIZE, 1, GROUND_SIZE)
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = box_shape
	ground.add_child(collision_shape)

	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

func _scatter_landmarks() -> void:
	for i in range(NUM_ROCKS):
		_add_rock(_random_ground_position())
	for i in range(NUM_TREES):
		_add_tree(_random_ground_position())

func _random_ground_position() -> Vector3:
	var half := GROUND_SIZE / 2.0 - 2.0
	var pos := Vector3.ZERO
	while pos.length() < SPAWN_CLEAR_RADIUS:
		pos = Vector3(randf_range(-half, half), 0, randf_range(-half, half))
	return pos

func _add_rock(pos: Vector3) -> void:
	var rock := StaticBody3D.new()
	var radius := randf_range(0.4, 0.9)

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mesh_instance.material_override = mat
	rock.add_child(mesh_instance)

	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = sphere_shape
	rock.add_child(collision_shape)

	rock.position = pos + Vector3(0, radius, 0)
	add_child(rock)

func _add_tree(pos: Vector3) -> void:
	var tree := StaticBody3D.new()

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 2.5
	var trunk_instance := MeshInstance3D.new()
	trunk_instance.mesh = trunk_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk_instance.material_override = trunk_mat
	trunk_instance.position = Vector3(0, 1.25, 0)
	tree.add_child(trunk_instance)

	var leaves_mesh := SphereMesh.new()
	leaves_mesh.radius = 1.1
	leaves_mesh.height = 2.2
	var leaves_instance := MeshInstance3D.new()
	leaves_instance.mesh = leaves_mesh
	var leaves_mat := StandardMaterial3D.new()
	leaves_mat.albedo_color = Color(0.15, 0.5, 0.2)
	leaves_instance.material_override = leaves_mat
	leaves_instance.position = Vector3(0, 3.0, 0)
	tree.add_child(leaves_instance)

	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.3
	trunk_shape.height = 2.5
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = trunk_shape
	collision_shape.position = Vector3(0, 1.25, 0)
	tree.add_child(collision_shape)

	tree.position = pos
	add_child(tree)

func _add_player() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 1, 0)
	add_child(player)
