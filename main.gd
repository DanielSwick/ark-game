extends Node3D

# Builds the world in code instead of hand-placing nodes in a scene file.
# Once you're comfortable in the Godot editor, feel free to drag these into
# the scene tree yourself instead - this is just the fastest way to get a
# first playable version in front of you.

const PLAYER_SCENE := preload("res://player.tscn")

const GROUND_SIZE := 200.0
const TERRAIN_RESOLUTION := 64
const CELL_SIZE := GROUND_SIZE / TERRAIN_RESOLUTION
const HALF_SIZE := GROUND_SIZE / 2.0
const HEIGHT_SCALE := 6.0
const NOISE_FREQUENCY := 0.015

const NUM_ROCKS := 15
const NUM_TREES := 15
const SPAWN_CLEAR_RADIUS := 8.0

var noise := FastNoiseLite.new()

func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = NOISE_FREQUENCY
	noise.seed = randi()

	_add_light()
	_add_sky()
	_add_ground()
	_scatter_landmarks()
	_add_player()

# The single source of truth for terrain height at any world (x, z).
# Used both to build the ground mesh and to place everything that stands
# on it (rocks, trees, the player), so nothing floats or sinks.
func _height_at(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * HEIGHT_SCALE

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

# Always computed from (i, j) alone - never derived by adding CELL_SIZE to
# a neighboring vertex's position - so the same grid point comes out
# bit-for-bit identical no matter which triangle asks for it. That's what
# lets SurfaceTool.index() below weld the terrain into one smooth surface
# instead of leaving cracks between triangles.
func _grid_vertex(i: int, j: int) -> Vector3:
	var x := -HALF_SIZE + i * CELL_SIZE
	var z := -HALF_SIZE + j * CELL_SIZE
	return Vector3(x, _height_at(x, z), z)

func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for j in range(TERRAIN_RESOLUTION):
		for i in range(TERRAIN_RESOLUTION):
			var p00 := _grid_vertex(i, j)
			var p10 := _grid_vertex(i + 1, j)
			var p01 := _grid_vertex(i, j + 1)
			var p11 := _grid_vertex(i + 1, j + 1)

			surface_tool.add_vertex(p00)
			surface_tool.add_vertex(p01)
			surface_tool.add_vertex(p10)

			surface_tool.add_vertex(p10)
			surface_tool.add_vertex(p01)
			surface_tool.add_vertex(p11)

	surface_tool.index()
	surface_tool.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.3)
	surface_tool.set_material(mat)

	var mesh := surface_tool.commit()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	ground.add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = mesh.create_trimesh_shape()
	ground.add_child(collision_shape)

	add_child(ground)

func _scatter_landmarks() -> void:
	for i in range(NUM_ROCKS):
		_add_rock(_random_ground_position())
	for i in range(NUM_TREES):
		_add_tree(_random_ground_position())

func _random_ground_position() -> Vector3:
	var half := HALF_SIZE - 2.0
	var flat := Vector2.ZERO
	while flat.length() < SPAWN_CLEAR_RADIUS:
		flat = Vector2(randf_range(-half, half), randf_range(-half, half))
	return Vector3(flat.x, _height_at(flat.x, flat.y), flat.y)

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
	player.position = Vector3(0, _height_at(0, 0) + 1, 0)
	add_child(player)
