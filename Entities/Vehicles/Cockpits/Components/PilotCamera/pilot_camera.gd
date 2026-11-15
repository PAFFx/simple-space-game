class_name PilotCamera
extends Camera3D

## The pilot's eye. With physics interpolation on, the suit is drawn between
## physics ticks, but a camera steered by the mouse must update every frame.
## So the camera is top-level, not interpolated itself, and each frame follows
## its parent's *interpolated* transform plus the look rotation. That keeps the
## view smooth at any refresh rate without lagging the mouse.
##
## The hull's inner parts (chest cavity, hatch flaps) are only drawn while the hatch
## is unsealed. Sealed, the pilot sees the panoramic screen, and the cockpit gimbal
## turns inside the hull, so the cavity walls would cut through the screen.

## The eye rides on a body: looking round turns the head on the neck, and far to the side
## or down the pilot twists and leans in the seat, so the eye moves (it can look past the
## seat back and over its own lap) instead of turning on the spot.
@export_group("Body lean")
@export var lean_enabled: bool = false
## The eye from the neck's pivot and that pivot from the hips, looking straight ahead, m.
@export var eye_from_neck := Vector3(0.0, 0.10, -0.09)
@export var neck_from_hip := Vector3(0.0, 0.43, 0.03)
## Share of the look's yaw the torso takes by twisting, and its limit, deg.
@export_range(0.0, 1.0) var twist_share: float = 0.3
@export var max_twist_deg: float = 45.0
## Lean toward the side looked at: full at the far end of this yaw window, deg.
@export var side_lean_deg: float = 30.0
@export var side_lean_window := Vector2(40.0, 125.0)
## Lean forward when looking down (over this pitch window, deg) and a little when
## looking behind.
@export var forward_lean_deg: float = 18.0
@export var forward_lean_window := Vector2(45.0, 75.0)
@export var behind_forward_lean_deg: float = 6.0
## Looking up or down, the eyes turn first: the head only tips for the pitch beyond this,
## deg, and then by this share of it (so the eye doesn't dip into the chest).
@export var eyes_only_pitch_deg: float = 25.0
@export_range(0.0, 1.0) var head_pitch_share: float = 0.6
@export_group("")

var look_rotation := Basis.IDENTITY
## How the torso is turned for the current look (identity looking ahead), in the seat's
## frame, about the hips. The seated pilot's body follows it.
var torso := Basis.IDENTITY
## The body's lean against the suit's G (SeatedPilot.lean: x = right, y = forward, deg).
## The eye goes with it, or the leaning body would pass through the eye.
var body_sway := Vector2.ZERO

var _mount: Node3D
var _hatch: CockpitHatch


func _ready() -> void:
	_mount = get_parent() as Node3D
	look_rotation = basis
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Before the sensor head and HUD read the camera this frame.
	process_priority = -10
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	_update_hull_layer()
	_follow()


## Called by MouseLookController instead of setting the rotation directly.
func set_look_rotation(value: Basis) -> void:
	look_rotation = value
	_follow()


func _process(_delta: float) -> void:
	_update_hull_layer()
	_follow()


func _update_hull_layer() -> void:
	if _hatch != null:
		set_cull_mask_value(3, _hatch.is_unsealed())  # Layers.VEHICLE_FP (bit 2)


func _follow() -> void:
	if _mount != null:
		global_transform = _mount.get_global_transform_interpolated() * Transform3D(look_rotation, _eye_offset())


## Where the eye goes for the current look, from where it is looking straight ahead.
func _eye_offset() -> Vector3:
	if not lean_enabled:
		torso = Basis.IDENTITY
		return Vector3.ZERO
	var e := look_rotation.get_euler(EULER_ORDER_YXZ)
	var yaw_deg := rad_to_deg(e.y)
	var side := smoothstep(side_lean_window.x, side_lean_window.y, absf(yaw_deg))
	var twist := clampf(yaw_deg * twist_share, -max_twist_deg, max_twist_deg)
	var down := smoothstep(forward_lean_window.x, forward_lean_window.y, -rad_to_deg(e.x))
	# + about Z tips the head left, − about X tips it forward.
	var roll := side_lean_deg * side * signf(yaw_deg)
	var forward := forward_lean_deg * down + behind_forward_lean_deg * side
	torso = Basis(Vector3.BACK, deg_to_rad(roll)) * Basis(Vector3.RIGHT, deg_to_rad(-forward)) \
			* Basis(Vector3.UP, deg_to_rad(twist))
	var pitch_deg := rad_to_deg(e.x)
	var head_pitch := signf(pitch_deg) * maxf(absf(pitch_deg) - eyes_only_pitch_deg, 0.0) * head_pitch_share
	var head := Basis(Vector3.UP, e.y) * Basis(Vector3.RIGHT, deg_to_rad(head_pitch))
	var sway := Basis(Vector3.BACK, deg_to_rad(-body_sway.x)) * Basis(Vector3.RIGHT, deg_to_rad(-body_sway.y))
	return sway * torso * neck_from_hip - neck_from_hip + sway * head * eye_from_neck - eye_from_neck
