class_name MsDrawMotion
extends Resource

## How a hand-held MsEquipment is stowed on the suit and drawn from there (rifle on the
## rear skirt). The path is a list of placements of the equipment (body frame, skeleton at
## rest): the hand's pose at each comes from ArmReachSolver, so the equipment is exactly in
## the hand at every key. MsLoadout plays it; EquipmentDrawModifier poses the bones.
##
##   reach:  live pose → reach_keys … → the grab
##   draw:   the grab → draw_keys … → live pose (held, its pose layer)
##
## With a stow arm (present_keys) the equipment isn't taken off the stow point by the hand:
## the stow arm, a manipulator on the stow bone, carries it from stow_transform through
## present_keys to where the hand takes it (the last key), the hand only reaching there; once
## the hand has it the empty stow arm folds back. Stowing runs it all backwards.
## The arm's path runs through every key (a spline through the bones' rotations).

## Bone the equipment rides while stowed, and where (body frame at rest).
@export var stow_bone: StringName = &""
@export var stow_transform := Transform3D.IDENTITY
## Stow arm: placements the equipment is carried through from its stow (body frame), the
## last where the hand takes it. Empty: the hand takes it off the stow point itself.
@export var present_keys: Array[Transform3D] = []
## The stow arm (StowArm) lives in a bay behind a hatch in the armour of the stow bone: its
## centre, the plate's outward normal, the hinge along its top edge, size (along the hinge,
## down the plate) (body frame). Its first link (arm_link m) swings from arm_in_dir
## (folded in) to arm_out_dir; a telescoping boom runs on to the gripper.
@export var hatch_centre := Vector3.ZERO
@export var hatch_normal := Vector3.BACK
@export var hatch_hinge := Vector3.RIGHT
@export var hatch_size := Vector2(0.9, 0.9)
## The hatch door: a bone of the model, hinged at its head (EquipmentDrawModifier swings
## it open, bottom out, by hatch_open_deg).
@export var hatch_bone: StringName = &""
@export var hatch_open_deg: float = 100.0
@export var arm_link: float = 0.8
@export var arm_in_dir := Vector3.FORWARD
@export var arm_out_dir := Vector3.BACK
## Where the gripper holds the equipment (its own frame as it sits in the hand at rest), and
## its axes there: x out of the gripped edge, y across it (the fingers close arm_grip_span
## apart).
@export var arm_clamp := Vector3.ZERO
@export var arm_clamp_basis := Basis.IDENTITY
@export var arm_grip_span: float = 1.5
## Share of the progress the hatch takes to open (before the arm comes out) or shut.
@export var hatch_share: float = 0.1
## Share of the stow arm's progress spent swinging its first link out through the hatch
## before it starts to carry (and, stowing, back in after it has put it back).
@export var deploy_share: float = 0.15
## Share of the reach (progress 0..1) by which the stow arm has presented it; the share over
## which the hand moves to the grab (it can be there first: the stow arm then feeds it into
## the hand); share of the draw (1..2) the empty stow arm takes to fold.
@export var present_share: float = 1.0
@export var hand_start: float = 0.0
@export var hand_end: float = 1.0
@export var fold_share: float = 0.7
## Placements the empty hand passes on its way to the grab: where the equipment would be
## if it were in the hand.
@export var reach_keys: Array[Transform3D] = []
## Placements after the grab, toward the held pose.
@export var draw_keys: Array[Transform3D] = []
## Arm chain, shoulder to hand.
@export var upper_arm_bone: StringName = &""
@export var forearm_bone: StringName = &""
@export var hand_bone: StringName = &""
## Body lean for reaching behind: bone → skeleton-space rotations [[axis, deg], …] at full
## lean (waist twist and side bend, collarbone down and back: the arm alone can't get there).
@export var lean := {}
## Share of the lean at each key: reach_keys, then the stow, then draw_keys.
@export var lean_weights := PackedFloat32Array()
## Where the elbow should point at each key (body frame; the reach picks the elbow swing
## nearest it that keeps the wrist straight), in the same order as lean_weights.
@export var elbow_hints := PackedVector3Array()
## The equipment's bulk the arm must keep out of: capsules [end a, end b, radius] in its
## own frame (body frame, where it sits in the hand at rest). The hand holding it is
## exempt. For keys before the grab it is where it is stowed.
@export var clearance: Array = []
## Upper arm and forearm as capsules round their bones, m.
@export var upper_arm_radius: float = 1.0
@export var forearm_radius: float = 1.1
## How much forearm twist the reach may use, deg; the rest is the wrist's roll.
@export var twist_limit_deg: float = 100.0
## Seconds for the reach to the grab, and from the grab to the held pose.
@export var reach_time: float = 0.8
@export var draw_time: float = 1.2
## Seconds the equipment takes to slide into its exact place in the hand (or on the stow)
## after changing hands: the live pose never matches the keys exactly.
@export var settle_time: float = 0.25
## Armour followers held at rest while it moves (LimbFollowers.hold_bone): the skirt it is
## stowed on, so it is where the hand expects it.
@export var held_followers: Array[StringName] = []
## While it is on its stow point, legs that would swing into it are kept off: AMBAC
## coupled limits [thigh bone, thigh axis, knee bone, knee axis, twist bone, twist axis,
## min thigh + knee deg, deg more per deg of inward twist] (AmbacController.add_coupled_limit).
@export var stowed_leg_limits: Array = []
## The same while it is being drawn or stowed (the legs stay free, short of where they would
## swing into it or into the armour held still).
@export var drawing_leg_limits: Array = []
## Thrusters whose (one-plane) swing is narrowed while it is drawn or stowed: name → Vector2
## (min, max) deg. Their guard plates swing with them (the calf plates into its path).
@export var drawing_thruster_swing := {}
## AMBAC groups held still while it moves (the lean drives the waist).
@export var held_groups: Array[StringName] = []


func get_key_count() -> int:
	return reach_keys.size() + 1 + draw_keys.size()


## Equipment placement at key `i` (reach keys, the grab, draw keys).
func get_key(i: int) -> Transform3D:
	if i < reach_keys.size():
		return reach_keys[i]
	if i == reach_keys.size():
		return get_grab()
	return draw_keys[i - reach_keys.size() - 1]


## Where the hand takes it: presented by the stow arm, or on the stow point.
func get_grab() -> Transform3D:
	return present_keys[-1] if not present_keys.is_empty() else stow_transform


## How far the stow arm's first link is out, 0 … 1, for its progress `m`.
func get_deploy(m: float) -> float:
	return smoothstep(0.0, 1.0, clampf(m / maxf(deploy_share, 0.01), 0.0, 1.0))


## The stow arm's placement of the equipment, `m` 0 (stowed) .. 1 (presented): it waits
## while the arm deploys, then turns about its clamp point, which runs along a spline
## through the keys.
func get_presented(m: float) -> Transform3D:
	if present_keys.is_empty():
		return stow_transform
	m = clampf((m - deploy_share) / maxf(1.0 - deploy_share, 0.01), 0.0, 1.0)
	var keys: Array[Transform3D] = [stow_transform]
	keys.append_array(present_keys)
	var n := keys.size() - 1
	var x := clampf(m, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	var u := x - i
	var pre := keys[maxi(i - 1, 0)]
	var a := keys[i]
	var b := keys[i + 1]
	var post := keys[mini(i + 2, n)]
	var at := (a * arm_clamp).cubic_interpolate(b * arm_clamp, pre * arm_clamp, post * arm_clamp, u)
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	var qpre := pre.basis.get_rotation_quaternion()
	var qpost := post.basis.get_rotation_quaternion()
	var rot := Basis(qa.spherical_cubic_interpolate(qb, qpre, qpost, u).normalized())
	return Transform3D(rot, at - rot * arm_clamp)


## The stow arm's progress for draw progress `p` (0 stowed … 1 the grab … 2 held): it comes
## out once the hatch is mostly open, and folds back in before it shuts.
func get_arm_progress(p: float) -> float:
	var lead := hatch_share * 0.7
	if p < 1.0:
		return smoothstep(0.0, 1.0, clampf((p - lead) / maxf(present_share - lead, 0.01), 0.0, 1.0))
	return 1.0 - smoothstep(0.0, 1.0, clampf((p - 1.0) / maxf(fold_share, 0.01), 0.0, 1.0))


## How far the hatch is open, 0 … 1, for draw progress `p`.
func get_hatch_open(p: float) -> float:
	if p < 1.0:
		return smoothstep(0.0, 1.0, clampf(p / maxf(hatch_share, 0.01), 0.0, 1.0))
	return 1.0 - smoothstep(0.0, 1.0, clampf((p - 1.0 - fold_share) / maxf(hatch_share, 0.01), 0.0, 1.0))


func get_lean_weight(i: int) -> float:
	return lean_weights[i] if i < lean_weights.size() else 0.0


func get_elbow_hint(i: int) -> Vector3:
	return elbow_hints[i] if i < elbow_hints.size() else Vector3.ZERO
