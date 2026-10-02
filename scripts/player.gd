extends CharacterBody2D

enum State { IDLE, RUN, JUMP, FALL, WALL_SLIDE, DASH }

@export var speed := 500.0
@export var acceleration := 4000.0
@export var friction := 4000.0
@export var jump_velocity := -800.0
@export var min_jump_velocity := -300.0  # cut to this if jump released early
@export var max_jumps := 2
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var step_height := 14.0

@export_group("Wall")
@export var wall_slide_speed := 150.0
@export var wall_jump_velocity := Vector2(400, -700)

@export_group("Dash")
@export var dash_speed := 1200.0
@export var dash_time := 0.15
@export var dash_cooldown := 0.4

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var background_sound: AudioStreamPlayer = $BackgroundSound
@onready var jump_sound: AudioStreamPlayer2D = $JumpSound
@onready var camera: Camera2D = $Camera2D

var state := State.IDLE
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jumps_left := max_jumps
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var can_dash := true
var dash_direction := 0.0
var was_on_floor := true


func _physics_process(delta: float) -> void:
	was_on_floor = is_on_floor()
	var direction := Input.get_axis("left", "right")
	var on_wall := is_on_wall() and not was_on_floor

	_update_timers(delta)

	match state:
		State.DASH:
			_process_dash(delta)
		_:
			_apply_gravity(delta, on_wall)
			_handle_jump_input(on_wall)
			_handle_dash_input(direction)
			_apply_horizontal_movement(delta, direction)
			if was_on_floor and direction != 0.0:
				_try_step_up(direction)

	move_and_slide()
	_update_state(direction, on_wall)
	_update_animation(direction)


func _update_timers(delta: float) -> void:
	if was_on_floor:
		coyote_timer = coyote_time
		jumps_left = max_jumps
		can_dash = true
	else:
		coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta


func _apply_gravity(delta: float, on_wall: bool) -> void:
	if was_on_floor:
		return
	if on_wall and velocity.y > 0:
		velocity.y += get_gravity().y * delta * 0.3  # slower fall on wall
		velocity.y = min(velocity.y, wall_slide_speed)
	else:
		velocity += get_gravity() * delta

	# variable jump height: cut upward velocity if jump released early
	if velocity.y < 0 and Input.is_action_just_released("jump"):
		velocity.y = max(velocity.y, min_jump_velocity)


func _handle_jump_input(on_wall: bool) -> void:
	if jump_buffer_timer <= 0.0:
		return

	if on_wall:
		velocity.x = -sign(get_wall_normal().x) * wall_jump_velocity.x * -1
		velocity.y = wall_jump_velocity.y
		_do_jump_fx()
	elif coyote_timer > 0.0:
		velocity.y = jump_velocity
		coyote_timer = 0.0
		_do_jump_fx()
	elif jumps_left > 0:
		velocity.y = jump_velocity
		jumps_left -= 1
		_do_jump_fx()


func _do_jump_fx() -> void:
	jump_buffer_timer = 0.0
	jump_sound.play()
	_squash_stretch(Vector2(0.8, 1.2))


func _handle_dash_input(direction: float) -> void:
	if Input.is_action_just_pressed("dash") and can_dash and dash_cooldown_timer <= 0.0:
		state = State.DASH
		dash_timer = dash_time
		dash_cooldown_timer = dash_cooldown
		can_dash = false
		dash_direction = direction if direction != 0.0 else (1.0 if not animated_sprite_2d.flip_h else -1.0)
		velocity.y = 0


func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = Vector2(dash_direction * dash_speed, 0)
	if dash_timer <= 0.0:
		state = State.FALL


func _apply_horizontal_movement(delta: float, direction: float) -> void:
	if direction:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)


func _try_step_up(direction: float) -> void:
	var forward_motion := Vector2(direction * 4.0, 0)
	if test_move(global_transform, forward_motion):
		var up_transform := global_transform
		up_transform.origin.y -= step_height
		if not test_move(up_transform, forward_motion):
			global_position.y -= step_height


func _update_state(direction: float, on_wall: bool) -> void:
	if state == State.DASH:
		return
	if not was_on_floor and is_on_floor() and velocity.y >= 0:
		_squash_stretch(Vector2(1.25, 0.75))  # landing squash
		if camera:
			_shake_camera()

	if on_wall and velocity.y > 0:
		state = State.WALL_SLIDE
	elif not is_on_floor():
		state = State.JUMP if velocity.y < 0 else State.FALL
	elif direction != 0.0:
		state = State.RUN
	else:
		state = State.IDLE


func _update_animation(direction: float) -> void:
	match state:
		State.JUMP, State.FALL:
			animated_sprite_2d.play("jumping")
		State.WALL_SLIDE:
			animated_sprite_2d.play("jumping")
		State.RUN:
			animated_sprite_2d.play("running")
		State.DASH:
			animated_sprite_2d.play("running")
		_:
			animated_sprite_2d.play("idle")

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true


func _squash_stretch(target_scale: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(animated_sprite_2d, "scale", target_scale, 0.06)
	tween.tween_property(animated_sprite_2d, "scale", Vector2.ONE, 0.12)


func _shake_camera(strength := 6.0, duration := 0.15) -> void:
	var tween := create_tween()
	var original := camera.offset
	var steps := 6
	for i in steps:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, duration / steps)
	tween.tween_property(camera, "offset", original, duration / steps)
