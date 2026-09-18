extends CharacterBody3D

# First-person / third-person character controller.
# Survival mode: normal walking, gravity, jump (Space).
# Creative mode: free flight - Space to rise, Shift to fall, no gravity.
# Mouse to look around. V toggles first-person/third-person camera.
# Press Escape to let go of the mouse; click the game window to grab it again.

const SPEED := 5.0
const FLY_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8

# Render layer 2 is reserved for the player's own body mesh so the
# first-person camera can skip drawing it (nobody wants to see the inside
# of their own head) while the third-person camera still shows it.
const BODY_RENDER_LAYER := 2

@onready var head: Node3D = $Head
@onready var body_mesh: MeshInstance3D = $Body
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var first_person_camera: Camera3D = $Head/FirstPersonCamera
@onready var third_person_camera: Camera3D = $Head/SpringArm3D/ThirdPersonCamera

var first_person: bool = true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Global.player_color
	body_mesh.material_override = body_material

	first_person_camera.cull_mask = first_person_camera.cull_mask & ~BODY_RENDER_LAYER

	# Without this, the spring arm's collision ray immediately hits the
	# player's own capsule and the third-person camera collapses to
	# point-blank range.
	spring_arm.add_excluded_object(get_rid())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * Global.mouse_sensitivity)
		head.rotate_x(-event.relative.y * Global.mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_toggle_camera()

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_camera() -> void:
	first_person = not first_person
	first_person_camera.current = first_person
	third_person_camera.current = not first_person

func _physics_process(delta: float) -> void:
	if Global.mode == Global.Mode.CREATIVE:
		_move_creative()
	else:
		_move_survival(delta)

func _move_survival(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := _movement_direction()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _move_creative() -> void:
	var direction := _movement_direction()
	velocity.x = direction.x * FLY_SPEED
	velocity.z = direction.z * FLY_SPEED

	velocity.y = 0.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y += FLY_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		velocity.y -= FLY_SPEED

	move_and_slide()

func _movement_direction() -> Vector3:
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	return (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
