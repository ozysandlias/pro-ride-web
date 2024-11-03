extends CharacterBody3D

#TODO -- fix check for landing flat -- add stalling and glide physics based on speed -- move things to their own functions for readability
# -- Create more interesting level -- maybe add loops, definitely rings to fly through,


@export var top_speed: float = 10
@export var accel: float = 20
@export var turn_speed: int = 2
@export var  JUMP_VELOCITY: float = 4.5
@export var camera_speed: float = 4
@export var tumble_speed = 5
@export var default_gravity = 13


# Get the gravity from the project settings to be synced with RigidBody nodes.
@onready var gravity = default_gravity
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var model = $lowPolyPerson
@onready var raycast: RayCast3D = $RayCast3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var aft_raycast: RayCast3D = $RayCast3D2
@onready var speed: float = 0
@onready var glide: bool = false
@onready var camera_follow: bool = true
@onready var glide_speed = 0
@onready var default_raycast_position = raycast.target_position

func _ready():
	spring_arm.top_level = true
	floor_snap_length = 3
	floor_constant_speed = false

func _physics_process(delta):

	#get player input	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var xinput = input_dir.x * delta
	var yinput = input_dir.y * delta

	# Get the input direction and handle the movement/deceleration.
	speed = lerp(speed, -top_speed, 0.1)
	var quat = quaternion.normalized()
	var speed_vect = quat * Vector3(0, 0, speed)



	#gliding
	if Input.is_action_just_pressed("jump") and !raycast.is_colliding():
		if !glide:
			glide = true
			velocity.y = 0
			glide_speed = speed_vect.y/3
		else:
			glide = false

	if glide: # -- make a way to lose glide over time and add stalling
		var xform = align_with_y(transform, Vector3.UP)
		if abs(basis.x.normalized().angle_to(Vector3.UP) - deg_to_rad(90)) > deg_to_rad(5):
			transform = transform.interpolate_with(xform, 0.01)
		camera_follow = true
		velocity.x = speed_vect.x
		velocity.z = speed_vect.z
		glide_speed = move_toward(glide_speed, 0, .5)
		#infinite glide for testing
		velocity.y = speed_vect.y	
		#lose glide over time -- needs work
		#velocity.y += speed_vect.y*delta*glide_speed
		var x_quat = Quaternion(basis.x, yinput * turn_speed).normalized()
		var y_quat = Quaternion(Vector3.UP, -xinput * turn_speed).normalized()
		var new_quat = x_quat * y_quat
		quaternion = quaternion.slerp(new_quat * quaternion.normalized(), 0.5)
		spring_arm.rotation.x = lerp_angle(spring_arm.rotation.x, rotation.x, 0.1)
			
	elif !raycast.is_colliding():
		camera_follow = false
		var xform = align_with_z(spring_arm.global_transform, Vector3.UP)
		spring_arm.global_transform = spring_arm.global_transform.interpolate_with(xform, 0.005)
		spring_arm.spring_length = lerp(spring_arm.spring_length, 5.0, 0.3)
		rotate(basis.y, (deg_to_rad(-input_dir.x * tumble_speed)))
		rotate_object_local(Vector3.RIGHT, (deg_to_rad(input_dir.y * tumble_speed/2)))

	raycast.force_raycast_update()
	
	if raycast.is_colliding() and aft_raycast.is_colliding() and raycast.get_collision_normal().angle_to(basis.y) < deg_to_rad(50):

		#set up camera, clear glide, and enable ground steering mode
		#spring_arm.rotation.x = lerp(spring_arm.rotation.x, 0.0, 0.2)
		camera_follow = true
		
		# -- maybe make different functions for steering modes for clarity
		rotate_y(deg_to_rad(-input_dir.x * turn_speed))
		var n = (raycast.get_collision_normal() + aft_raycast.get_collision_normal()) / 2
		n = n.normalized()
			
		#move velocity and up direction to raycast normal
		var xform = align_with_y(transform, n)
		transform = transform.interpolate_with(xform, 0.1)
		up_direction = basis.y
		velocity.x = speed_vect.x
		velocity.z = speed_vect.z
		velocity = velocity.slide(n)
		velocity = velocity.clamp(Vector3(-top_speed, -top_speed, -top_speed), Vector3(top_speed, top_speed, top_speed))
		var effective_gravity = abs(Vector3.UP.dot(-basis.z) * gravity)
		velocity.y -= effective_gravity * delta
		apply_floor_snap()

		
	print(velocity)

	if is_on_floor():
		spring_arm.spring_length = lerp(spring_arm.spring_length, 3.0, 0.01)
		if spring_arm.basis.z.angle_to(Vector3.UP) > deg_to_rad(10):
			var xform = align_with_y(spring_arm.transform, Vector3.UP)
			spring_arm.transform = spring_arm.transform.interpolate_with(xform, 0.01)
		glide = false
		#bail if you land at the wrong angle --maybe move this to a collision check. needs work
		if basis.y.angle_to(get_floor_normal()) > TAU/8:
			var xform = align_with_y(transform, Vector3.UP)
			transform = transform.interpolate_with(xform, 0.3)
			velocity.y = 0
		else:
			raycast.target_position = default_raycast_position #raycast.target_position.lerp(default_raycast_position, 0.1)
		# Handle jump.
		if Input.is_action_just_released("jump"):
			velocity.y = JUMP_VELOCITY
			camera_follow = false
			raycast.target_position = Vector3(0, 0, 0)
		
	else:
		raycast.target_position = raycast.target_position.lerp(Vector3(0, 0, 0), 1)
		velocity.y -= gravity * delta
		up_direction = Vector3.UP


			
	
	#make the camera follow the character with a little lag
	if camera_follow:
		spring_arm.rotation.y = lerp_angle(spring_arm.rotation.y, rotation.y, 0.2)
	move_and_slide()


	#spring_arm.position = position
	transform = transform.orthonormalized()



func align_with_y(xform, new_y):
	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

func align_with_z(xform, new_z):
	xform.basis.z = new_z
	xform.basis.y = -xform.basis.x.cross(new_z)
	xform.basis = xform.basis.orthonormalized()
	return xform
