extends CharacterBody3D

var SPLERP = 9
var FOVIEW = {"NORMAL": 80, "SPEED": 90}
var speed
var normal_speed = 5.0
var sprint_speed = 10.0
const accel_normal = 10.0
const accel_in_air = 1.0
@onready var accel = accel_normal
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var jump_velocity
var normal_height = 2.0
var crouch_height = 1.0
var crouch_speed = 10.0
var mouse_sense = 0.15
var is_forward_moving = false
var direction = Vector3()
@onready var head := $Head
@onready var camera3d := $Head/Camera3D
@onready var player_capsule := $CollisionShape3D
@onready var head_check := $Head_check
@onready var ray = $Head/Camera3D/OBJ_PICKER/RayCast3D
@onready var sound_timer = $sound/Timer
@onready var walk_audio = $sound/WALK
@onready var jumped_audio = $sound/JUMPED
@onready var landed_audio = $sound/LANDED

@onready var held_object_position := $Head/Camera3D/HeldObjectPosition
var picked_obj
var pick_clone
var original_scale = Vector3.ONE
var grab_distance = 1.5
var max_grab_distance = 30.0
var min_grab_distance = 1.0
var grab_speed = 0.1

func _ready():
	PlayerAutoload.player = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		head_rot(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and picked_obj != null:
		grab_distance = max(grab_distance - grab_speed, min_grab_distance)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and picked_obj != null:
		grab_distance = min(grab_distance + grab_speed, max_grab_distance)

func head_rot(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sense))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sense))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90.0), deg_to_rad(90.0))

func scale_down_object():
	var coll = ray.get_collider()
	
	if coll != null and coll.is_in_group("INT"):
		print("Scaling down object:", coll.name)
		
		# Calculate the distance between camera and object
		var distance_to_object = camera3d.global_transform.origin.distance_to(coll.global_transform.origin)
		var max_distance = 30.0  # Define the maximum distance for scaling effect
		var min_scale = 0.5  # Minimum scale factor when far away
		var max_scale = 1.0  # Maximum scale factor when close
		var min_distance = 0.2  # Minimum distance for scaling effect (adjust as needed)
		var scale_factor = inverse_lerp(min_scale, max_scale, distance_to_object / max_distance)
		print("Scaling factor:", scale_factor)
		original_scale = coll.scale
		#coll.scale = original_scale * scale_factor  # Scale down the object
		print("New scale:", coll.scale)

		# Pick up the object
		pick_object(coll, scale_factor)

func pick_object(object_to_pick, scale_factor):
	if picked_obj == null:
		picked_obj = object_to_pick
		
		pick_clone = picked_obj.duplicate()  # Create a clone
		#pick_clone.scale = original_scale * scale_factor  # Scale down the clone
		
		var mesh_instance = pick_clone.get_node("MeshInstance3D")
		if mesh_instance != null:
			mesh_instance.scale = original_scale * scale_factor
			print("Clone mesh instance scale:", mesh_instance.scale)
		
		# Scale down the collision shape of the clone
		var collision_shape = pick_clone.get_node("CollisionShape3D")
		if collision_shape != null:
			collision_shape.scale = original_scale * scale_factor
			print("Clone collision shape scale:", collision_shape.scale)
	  
		add_child(pick_clone)
		pick_clone.global_transform.origin = held_object_position.global_transform.origin
		picked_obj.visible = false  # Hide the original object

func drop_obj():
	if picked_obj != null:
		picked_obj.global_transform.origin = held_object_position.global_transform.origin + (camera3d.global_transform.basis.z * grab_distance)  # Place object in front of the player
		picked_obj.visible = true  # Show the original object
		remove_child(pick_clone)
		pick_clone.queue_free()  # Remove the clone
		picked_obj = null
		pick_clone = null

func _process(delta):
	if Input.is_action_just_pressed("E"):
		if picked_obj == null:
			scale_down_object()  
		else:
			drop_obj()
	if picked_obj != null:
		var target_position = held_object_position.global_transform.origin + camera3d.global_transform.basis.z * grab_distance
		pick_clone.global_transform.origin = target_position

	CROUCH(delta)
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	direction = Vector3.ZERO
	speed = normal_speed
	var input_direction = Input.get_vector("MOVE_LEFT", "MOVE_RIGHT", "MOVE_FORWARD", "MOVE_BACKWARD")
	is_forward_moving = input_direction.y < 0.0
	direction = (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	
	if Input.is_action_pressed("sprint") and is_forward_moving:
		speed = sprint_speed
		camera3d.fov = lerpf(camera3d.fov, FOVIEW["SPEED"], SPLERP * delta)
	else:
		camera3d.fov = lerpf(camera3d.fov, FOVIEW["NORMAL"], SPLERP * delta)
	
	if Input.is_action_pressed("crouch") and Input.is_action_pressed("sprint"):
		speed = normal_speed
	
	if picked_obj == null:  
		if !is_on_floor():
			landed_audio.play_sfx()
			accel = accel_in_air
			velocity.y -= gravity * delta
		else:
			accel = accel_normal
			velocity.y -= jump_velocity
	
		if Input.is_action_just_pressed("ui_accept") && is_on_floor() && !Input.is_action_pressed("crouch"):
			velocity.y = jump_velocity
			jumped_audio.play_sfx()
	
	velocity = velocity.lerp(direction * speed, accel * delta)
	move_and_slide()
	
	if direction != Vector3() && is_on_floor():
		if sound_timer.time_left <= 0:
			walk_audio.pitch_scale = randf_range(1.2, 1)
			walk_audio.play_sfx()
			sound_timer.start(0.4)

func CROUCH(delta):
	var colliding = head_check.is_colliding()
	if Input.is_action_pressed("crouch"):
		sprint_speed = normal_speed
		jump_velocity = 0.0
		player_capsule.shape.height -= crouch_speed * delta
	elif !colliding:
		sprint_speed = sprint_speed
		jump_velocity = 8.0
		player_capsule.shape.height += crouch_speed * delta
	player_capsule.shape.height = clamp(player_capsule.shape.height, crouch_height, normal_height)
