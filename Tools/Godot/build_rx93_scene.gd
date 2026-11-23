extends SceneTree

## Generates the RX-93 ν Gundam vehicle scene and its animation library from the
## tables below. Run after rebuilding the GLBs (Tools/Blender/build_mobile_suit_nu.py):
##
##   godot-double --headless --path . -s Tools/Godot/build_rx93_scene.gd
##
## Same components as MSP-02 (same bone names). Thrusters sit on the nozzles the
## model actually has; see THRUSTERS.
##
## All positions/directions are in the suit's body frame (Godot: +Y up, front −Z)
## with the skeleton at rest. The output is a normal scene: tweak it in the
## editor, or edit the tables here and regenerate.

const DIR := "res://Entities/Vehicles/MobileSuits/RX93/"
const SCENE_PATH := DIR + "mobile_suit_rx93.tscn"
const ANIM_PATH := DIR + "Animations/rx93_animations.tres"
const MODEL := DIR + "Arts/mobile_suit_nu.glb"
const EQUIPMENT := "res://Entities/Equipment/RX93/"
const SKELETON := ^"Model/Armature/Skeleton3D"
# The model's belly is stretched taller (build_mobile_suit_nu.py, BELLY_*): everything
# from the pelvis down sits BELLY_DROP lower than on the source model. Positions below
# are the source's; lower-body ones go through _lowered().
const BELLY_DROP := 0.76
const LOWER_BONE_PREFIXES := ["root", "pelvis", "spine", "skirt_", "thigh", "shin", "foot", "calf_guard"]
# The legs carry about 45% of the mass, so the centre of mass drops ~0.45 of that.
const COM := Vector3(0.0, 14.6 - 0.34, 0.8)
const SENSOR_SCENE := \
		"res://Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.tscn"
# The ν's own cockpit variant: its hatch opening faces down the tunnel to the red chest door
# (the door is 40° below the sphere's centre, which can't move lower and stay in the chest).
const COCKPIT_SCENE := "res://Entities/Vehicles/Cockpits/CockpitLinearSeatV2Rail/cockpit_linear_seat_v2_rail.tscn"
const THRUSTER_SCENE := "res://Entities/Vehicles/Components/FlightControl/Thruster/thruster.tscn"

# name, bone, position, exhaust direction, thrust kN, gimbal: [cone, fore/aft, sideways] deg,
# plume m (verniers kept short next to the mains), nozzle scale, nozzle model.
# Positions/exhausts are the model's (yellow) thruster ports, measured in the body frame.
# 2D = swings in one plane only, fixed = no gimbal, so the limbs carrying them must move
# to aim them. Ports built into the armor show only a plume.
# Ratings below are design ratios (sized by nozzle). THRUST_SCALE: 63.0 / 59.5 keeps the
# thrust-to-weight the suit was tuned with (at 59.5 t) on the official 63.0 t max weight,
# ×1.5 for future chamber pressures (~1.6 MN per main; Docs/FlightControl/thrust_sizing.md).
const CONE_3D := [30.0, 90.0, 90.0]
# Mains are the model's own nozzles in two backpack pods, made deeper than on the source
# (see build_mobile_suit_nu.py) so they clear the body. Each pod pivots fore/aft
# only (2D) about its middle (ThrusterGuards), and the nozzles swing around that pivot
# (Thruster.swing_pivot): 8° to 78° back (±35° around 43° back; the modelled pods point 48°
# back). Nearly straight down for a climb; kept short of horizontal so the suit pitches
# nose-down and drives with the mains to move forward fast. Each nozzle also swings up to
# 10° sideways on its own (fast: no pod moves), outward only: the hyper bazooka sits
# between the pods. The cups nearly fill their channel in the pod (0.88 m in 0.90 m), so
# not more. The right pod's exhaust swinging right pushes the suit left, and vice versa.
const MAIN_EXHAUST := Vector3(0.0, -0.731, 0.682)
const MAIN_MODEL_EXHAUST := Vector3(0.0, -0.67, 0.74)
const MAIN_CONE := [35.0, 35.0, 5.0]
# Slot-shaped ports (flat plume along the slot): direction × length in the body frame, and
# the slot's width as the nozzle scale (the round plume's diameter is 0.76 × scale).
const SLOTS := {
	ChestR = [Vector3(-0.92, -0.14, -0.37) * 1.39, 0.74], ChestL = [Vector3(-0.92, 0.14, 0.37) * 1.39, 0.74],
	SkRearR = [Vector3(-0.74, -0.54, 0.4) * 1.57, 0.32], SkRearL = [Vector3(-0.74, 0.54, -0.4) * 1.57, 0.32],
	ShinCR = [Vector3(-0.1, 0.82, -0.56) * 0.76, 0.51], ShinCL = [Vector3(0.1, 0.82, -0.56) * 0.76, 0.51],
	ShinOR = [Vector3(-0.28, 0.71, -0.65) * 1.35, 0.28], ShinOL = [Vector3(-0.28, -0.71, 0.65) * 1.35, 0.28],
	ShinIR = [Vector3(0.05, 0.8, -0.6) * 1.35, 0.28], ShinIL = [Vector3(-0.05, 0.8, -0.6) * 1.35, 0.28],
}
const POD_HINGE := {MainRU = Vector3(1.33, 16.5, 3.4), MainRL = Vector3(1.33, 16.5, 3.4),
		MainLU = Vector3(-1.3, 16.65, 3.34), MainLL = Vector3(-1.3, 16.65, 3.34)}
# Each calf nozzle sits in its plate; the two swing together about the plate's hinge at
# the top front of the calf (from build_mobile_suit_nu.py), back only, away from the leg.
const CALF_MODEL_EXHAUST_R := Vector3(0.17, -0.9, 0.41)
const CALF_HINGE := {CalfR = Vector3(3.052, 8.062, 0.796), CalfL = Vector3(-3.033, 8.062, 0.796)}
# One-plane (2D) swings that don't sit centred on the rest direction: thruster →
# [direction the exhaust swings toward, min deg, max deg]. The calves swing back; the top
# shoulder nozzles from a little below their rest aim to nearly straight up.
const SWING_2D := {
	CalfR = [Vector3.BACK, 0.0, 40.0], CalfL = [Vector3.BACK, 0.0, 40.0],
	ShUpR = [Vector3.UP, -10.0, 45.0], ShUpL = [Vector3.UP, -10.0, 45.0],
}
const SOLE_3D := [30.0, 90.0, 90.0]
# The feet carry the sole nozzles and ease after their aim (ThrusterGuard follow_aim), within
# the ankle travel that clears the shin (Tools/Flight/foot_clip_probe.gd): toe down 40°, up
# 30°, tilt ±15°. They follow part of the swing, slowly, so the nozzle does the fast work.
const ANKLE_TOE_DOWN := -40.0
const ANKLE_TOE_UP := 30.0
const ANKLE_TILT := 15.0
const FOOT_FOLLOW := 0.6
const FOOT_SMOOTHING := 0.4
const FOOT_RATE_DEG := 60.0
const FORE_AFT := [25.0, 25.0, 0.0]      # 2D: swings fore/aft (about the port's sideways axis)
const UP_DOWN := [20.0, 20.0, 0.0]       # 2D, for forward-facing ports
const SIDE_SIDE := [20.0, 0.0, 20.0]     # 2D: swings left/right only
const FIXED := [0.0, 0.0, 0.0]
const MAIN_RATING_KN := 300.0
# Nozzle light on each main (lights the backpack and legs while boosting).
const MAIN_GLOW_LIGHT := 1.5
const THRUST_SCALE := 1.5 * 63.0 / 59.5
const MAIN_DYNAMICS := {spool_up_time = 0.12, spool_down_time = 0.08, gimbal_rate_deg = 240.0}
const VERNIER_DYNAMICS := {spool_up_time = 0.06, spool_down_time = 0.04, gimbal_rate_deg = 360.0}
const THRUSTERS := [
	# Backpack mains, 2 per side stacked, firing back and down.
	["MainRU", "backpack", Vector3(1.25, 16.75, 3.85), MAIN_EXHAUST, 1000.0, MAIN_CONE, 16.0, 1.30, false],
	["MainRL", "backpack", Vector3(1.25, 15.71, 3.53), MAIN_EXHAUST, 1000.0, MAIN_CONE, 16.0, 1.30, false],
	["MainLU", "backpack", Vector3(-1.23, 16.75, 3.85), MAIN_EXHAUST, 1000.0, MAIN_CONE, 16.0, 1.30, false],
	["MainLL", "backpack", Vector3(-1.23, 15.71, 3.53), MAIN_EXHAUST, 1000.0, MAIN_CONE, 16.0, 1.30, false],
	# Soles (the "toe" thrusters); the feet ease after their aim.
	["SoleR", "foot.R", Vector3(4.25, 0.26, 0.37), Vector3(0, -1, 0), 400.0, SOLE_3D, 2.0, 0.60, false],
	["SoleL", "foot.L", Vector3(-4.24, 0.26, 0.37), Vector3(0, -1, 0), 400.0, SOLE_3D, 2.0, 0.60, false],
	# Behind each calf, mostly down and a little back; its guard plate moves with it.
	["CalfR", "shin.R", Vector3(3.22, 5.8, 1.53), CALF_MODEL_EXHAUST_R, 400.0, FORE_AFT, 3.0, 0.80, false],
	["CalfL", "shin.L", Vector3(-3.2, 5.8, 1.53), CALF_MODEL_EXHAUST_R * Vector3(-1, 1, 1), 400.0, FORE_AFT, 3.0, 0.80, false],
	# Shoulder armor, two each: up-and-out (pushes the suit down) and out-and-down.
	["ShUpR", "shoulder.R", Vector3(4.79, 19.7, 0.45), Vector3(0.74, 0.67, 0.01), 480.0, FORE_AFT, 2.0, 0.50, false],
	["ShOutR", "shoulder.R", Vector3(4.95, 18.97, 0.44), Vector3(0.95, -0.3, 0.01), 480.0, FORE_AFT, 2.0, 0.50, false],
	["ShUpL", "shoulder.L", Vector3(-4.77, 19.7, 0.45), Vector3(-0.74, 0.67, 0.01), 480.0, FORE_AFT, 2.0, 0.50, false],
	["ShOutL", "shoulder.L", Vector3(-4.93, 18.97, 0.44), Vector3(-0.95, -0.3, 0.01), 480.0, FORE_AFT, 2.0, 0.50, false],
	# Chest vents, firing forward (push back / brake). With the backpack mains, the nearest
	# to the generator and the biggest-looking ports: nearly as strong as a main.
	["ChestR", "chest", Vector3(1.31, 17.26, -2.15), Vector3(0.39, -0.24, -0.89), 660.0, UP_DOWN, 6.5, 0.74, false],
	["ChestL", "chest", Vector3(-1.29, 17.26, -2.15), Vector3(-0.39, -0.24, -0.89), 660.0, UP_DOWN, 6.5, 0.74, false],
	# Front of each shin, below the knee: centre, outer, inner; left/right swing only.
	["ShinCR", "shin.R", Vector3(3.29, 6.96, -1.57), Vector3(0.24, -0.52, -0.82), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	["ShinOR", "shin.R", Vector3(4.36, 5.83, -0.13), Vector3(0.84, -0.15, -0.53), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	["ShinIR", "shin.R", Vector3(2.58, 5.39, -0.37), Vector3(-0.52, -0.49, -0.7), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	["ShinCL", "shin.L", Vector3(-3.28, 6.96, -1.57), Vector3(-0.24, -0.52, -0.82), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	["ShinOL", "shin.L", Vector3(-4.34, 5.83, -0.13), Vector3(-0.84, -0.15, -0.53), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	["ShinIL", "shin.L", Vector3(-2.56, 5.39, -0.37), Vector3(0.52, -0.49, -0.7), 240.0, SIDE_SIDE, 0.8, 0.30, false],
	# Rear skirts, one each, back and slightly out.
	["SkRearR", "skirt_rear.R", Vector3(1.78, 12.55, 2.45), Vector3(0.39, 0.13, 0.91), 240.0, FIXED, 1.1, 0.32, false],
	["SkRearL", "skirt_rear.L", Vector3(-1.76, 12.55, 2.45), Vector3(-0.39, 0.12, 0.91), 240.0, FIXED, 1.1, 0.32, false],
	# Side skirts, three small each: forward-out, back-out, out.
	["SkSideFR", "skirt_side.R", Vector3(2.11, 15.13, -0.81), Vector3(0.54, 0.25, -0.81), 220.0, FIXED, 0.7, 0.35, false],
	["SkSideBR", "skirt_side.R", Vector3(2.11, 15.13, 0.48), Vector3(0.54, 0.25, 0.81), 220.0, FIXED, 0.7, 0.35, false],
	["SkSideOR", "skirt_side.R", Vector3(2.61, 14.71, -0.16), Vector3(1, 0.01, 0), 220.0, FIXED, 0.7, 0.35, false],
	["SkSideFL", "skirt_side.L", Vector3(-2.09, 15.13, -0.81), Vector3(-0.54, 0.25, -0.81), 220.0, FIXED, 0.7, 0.35, false],
	["SkSideBL", "skirt_side.L", Vector3(-2.09, 15.13, 0.48), Vector3(-0.54, 0.25, 0.81), 220.0, FIXED, 0.7, 0.35, false],
	["SkSideOL", "skirt_side.L", Vector3(-2.59, 14.71, -0.16), Vector3(-1, 0.01, 0), 220.0, FIXED, 0.7, 0.35, false],
]

# name, center, size
const COLLIDERS := [
	["Torso", Vector3(0, 16.72, -0.8), Vector3(4.0, 4.96, 4.7)],  # down over the taller belly
	["Backpack", Vector3(0, 17.5, 3.6), Vector3(4.0, 7.0, 4.0)],
	["Head", Vector3(0, 20.2, -0.4), Vector3(1.6, 2.0, 2.2)],
	["Pelvis", Vector3(0, 12.8, -0.6), Vector3(5.0, 3.6, 4.6)],
	["ShoulderR", Vector3(3.35, 18.6, 0.4), Vector3(3.0, 3.0, 2.9)],
	["ShoulderL", Vector3(-3.35, 18.6, 0.4), Vector3(3.0, 3.0, 2.9)],
	["ArmR", Vector3(4.2, 14.4, 0.1), Vector3(1.8, 6.2, 2.0)],
	["ArmL", Vector3(-4.2, 14.4, 0.1), Vector3(1.8, 6.2, 2.0)],
	["LegR", Vector3(2.8, 6.8, 0.1), Vector3(3.0, 11.0, 3.2)],
	["LegL", Vector3(-2.8, 6.8, 0.1), Vector3(3.0, 11.0, 3.2)],
	["FootR", Vector3(4.35, 1.3, -1.5), Vector3(2.8, 2.6, 4.5)],
	["FootL", Vector3(-4.35, 1.3, -1.5), Vector3(2.8, 2.6, 4.5)],
]

# bone, axis (skeleton space), group, inertia kg·m², min angle, max angle, priority
# Human-like ranges, offsets from the animated pose. Signs: +X swings a hanging limb
# forward (hip flex, elbow bend), knees bend back (−X), +Z swings a right limb outward
# (left limbs mirror), +Y twists. A zero axis is along the bone: the forearm's own twist
# (the roll the rifle draw uses), small and low priority. Inertias here are only a fallback: every joint's bone is
# in the mass model (PARTS), which sets its inertia from the parts it swings (and refreshes
# it as the tanks drain). Twists move little mass, so they mostly add natural motion. The
# side hip swing stays small.
const AMBAC := [
	["upper_arm.R", Vector3.RIGHT, &"arm_r", 6.0e4, -35.0, 45.0, 0.7],
	["upper_arm.R", Vector3.BACK, &"arm_r", 6.0e4, -8.0, 35.0, 0.6],
	["upper_arm.R", Vector3.UP, &"arm_r", 1.0e4, -25.0, 25.0, 0.4],
	["forearm.R", Vector3.RIGHT, &"arm_r", 2.5e4, -5.0, 50.0, 0.6],
	["forearm.R", Vector3.ZERO, &"arm_r", 4.0e3, -30.0, 30.0, 0.3],
	["upper_arm.L", Vector3.RIGHT, &"arm_l", 6.0e4, -35.0, 45.0, 0.7],
	["upper_arm.L", Vector3.BACK, &"arm_l", 6.0e4, -35.0, 8.0, 0.6],
	["upper_arm.L", Vector3.UP, &"arm_l", 1.0e4, -25.0, 25.0, 0.4],
	["forearm.L", Vector3.RIGHT, &"arm_l", 2.5e4, -5.0, 50.0, 0.6],
	["forearm.L", Vector3.ZERO, &"arm_l", 4.0e3, -30.0, 30.0, 0.3],
	["thigh.R", Vector3.RIGHT, &"leg_r", 1.6e5, -30.0, 85.0, 1.0],
	["thigh.R", Vector3.BACK, &"leg_r", 1.6e5, -3.0, 15.0, 0.4],
	["thigh.R", Vector3.UP, &"leg_r", 2.0e4, -15.0, 15.0, 0.5],
	["shin.R", Vector3.RIGHT, &"leg_r", 4.5e4, -110.0, 5.0, 0.9],
	["thigh.L", Vector3.RIGHT, &"leg_l", 1.6e5, -30.0, 85.0, 1.0],
	["thigh.L", Vector3.BACK, &"leg_l", 1.6e5, -15.0, 3.0, 0.4],
	["thigh.L", Vector3.UP, &"leg_l", 2.0e4, -15.0, 15.0, 0.5],
	["shin.L", Vector3.RIGHT, &"leg_l", 4.5e4, -110.0, 5.0, 0.9],
	["spine", Vector3.UP, &"torso", 1.2e5, -12.0, 12.0, 0.8],
	["spine", Vector3.RIGHT, &"torso", 1.5e5, -10.0, 6.0, 0.5],
	# Side bend: its own group, so an arm weapon can hold the waist's twist. Hardly used
	# for balancing.
	["spine", Vector3.BACK, &"waist_bend", 1.5e5, -12.0, 12.0, 0.15],
]

# Mass model (LimbReaction, body frame): every part of the model, its solid volume
# (Tools/Godot/measure_part_volumes.gd, 0.2 m voxels), a density factor for what's inside
# it, and the share of that volume given to propellant tanks. The dry mass is split by
# volume × density, the propellant by volume × tank share. Dense: the chest (cockpit,
# generator), main pods (engines), waist frame, hands. Light: armour plates (skirts, calf
# plates, shoulder armour) and the big, mostly hollow feet. Tanks are spread around the
# body like a fighter's, most around the torso (chest, waist, backpack, skirts) and some in
# the thighs and shins, so the centre of mass barely moves as they drain (13.37 m full,
# 13.44 empty). Heavier leg tanks put it ~2 m under the backpack mains' line of thrust,
# and every forward push pitched the suit nose-down. The rifle, shield and backpack equipment add their own
# mass on the bone that carries them. Re-run the volume tool after changing the model.
const DRY_MASS := 27900.0
const PROPELLANT := 25200.0
const PARTS := [
	# bone, volume m³, density, tank share
	["chest", 59.38, 1.6, 0.2], ["spine", 5.52, 1.4, 0.0], ["pelvis", 27.90, 1.2, 0.4],
	["hatch", 0.44, 1.0, 0.0], ["head", 10.18, 1.0, 0.0],
	["backpack", 20.77, 1.3, 0.6], ["main_pod.R", 12.24, 1.6, 0.0], ["main_pod.L", 11.50, 1.6, 0.0],
	["main_nozzle_up.R", 0.72, 1.6, 0.0], ["main_nozzle_low.R", 0.71, 1.6, 0.0],
	["main_nozzle_up.L", 0.70, 1.6, 0.0], ["main_nozzle_low.L", 0.70, 1.6, 0.0],
	["shoulder.R", 17.34, 0.8, 0.0], ["upper_arm.R", 6.34, 1.2, 0.0], ["forearm.R", 12.69, 1.0, 0.0], ["hand.R", 2.83, 1.3, 0.0],
	["shoulder.L", 17.48, 0.8, 0.0], ["upper_arm.L", 6.35, 1.2, 0.0], ["forearm.L", 15.06, 1.0, 0.0], ["hand.L", 2.77, 1.3, 0.0],
	["skirt_front.R", 5.68, 0.5, 0.4], ["skirt_front.L", 6.01, 0.5, 0.4],
	["skirt_side.R", 3.34, 0.5, 0.3], ["skirt_side.L", 3.23, 0.5, 0.3],
	["skirt_rear.R", 7.98, 0.5, 0.5], ["skirt_rear.L", 7.90, 0.5, 0.5],
	["thigh.R", 22.86, 1.0, 0.15], ["shin.R", 46.46, 0.9, 0.1], ["foot.R", 32.86, 0.7, 0.0], ["calf_guard.R", 8.34, 0.6, 0.0],
	["thigh.L", 22.85, 1.0, 0.15], ["shin.L", 46.70, 0.9, 0.1], ["foot.L", 32.91, 0.7, 0.0], ["calf_guard.L", 8.30, 0.6, 0.0],
]

# Stances (StanceController): name, push direction (body frame), cone deg, joints as
# [bone, axis, deg] (AMBAC joints; hip +X flexes forward, knee −X bends back, +Z swings a
# right limb out, a left limb in). Legs only: arms stay free for equipment and balancing.
const STANCES := [
	# Legs forward, knees bent: soles and calves move in front of the COM to balance the
	# backpack's push.
	["climb", Vector3.UP, 50.0, [["thigh.R", Vector3.RIGHT, 25.0], ["shin.R", Vector3.RIGHT, -35.0],
			["thigh.L", Vector3.RIGHT, 25.0], ["shin.L", Vector3.RIGHT, -35.0]]],
	# Raise the leg on the side you're moving to, knee tucked (not kicked out): its swing
	# rolls the suit that way, and dropping it back helps roll it level.
	["strafe_right", Vector3.RIGHT, 50.0, [["thigh.R", Vector3.RIGHT, 70.0], ["shin.R", Vector3.RIGHT, -95.0],
			["thigh.R", Vector3.BACK, 6.0], ["thigh.L", Vector3.RIGHT, 10.0], ["shin.L", Vector3.RIGHT, -15.0]]],
	["strafe_left", Vector3.LEFT, 50.0, [["thigh.L", Vector3.RIGHT, 70.0], ["shin.L", Vector3.RIGHT, -95.0],
			["thigh.L", Vector3.BACK, -6.0], ["thigh.R", Vector3.RIGHT, 10.0], ["shin.R", Vector3.RIGHT, -15.0]]],
	# Legs trail back when driving forward, forward when braking or backing off.
	["forward", Vector3.FORWARD, 45.0, [["thigh.R", Vector3.RIGHT, -15.0], ["shin.R", Vector3.RIGHT, -25.0],
			["thigh.L", Vector3.RIGHT, -15.0], ["shin.L", Vector3.RIGHT, -25.0]]],
	["back", Vector3.BACK, 45.0, [["thigh.R", Vector3.RIGHT, 30.0], ["shin.R", Vector3.RIGHT, -25.0],
			["thigh.L", Vector3.RIGHT, 30.0], ["shin.L", Vector3.RIGHT, -25.0]]],
	# No descend stance: bending the legs for a descent moved thrusters that help it.
]

# Armor that follows a limb (LimbFollowers): bone, axis, source bone, source axis, factor
# when the source angle is > 0, factor when < 0, limit deg, follow the final pose (pose
# layers, AMBAC, stances, weapon aim) instead of the AMBAC angle alone, [ease in over this
# source angle range, deg]. Front skirts lift
# with a forward leg swing, rear skirts with a backward one, side skirts open with an
# outward swing and a little with either fore/aft swing. The shoulder armor rides all of
# the arm's fore/aft swing and half of its sideways one, so a raised or aimed arm never
# meets it; forward it eases in from 25° to 70°, so it stays level over the rifle's ready
# pose (tipping with it put its front edge into the rifle); back (reaching behind for the
# stowed rifle) it follows all the way.
const FOLLOWERS := [
	["skirt_front.R", Vector3.RIGHT, "thigh.R", Vector3.RIGHT, 0.85, 0.0, 75.0, true],
	["skirt_front.L", Vector3.RIGHT, "thigh.L", Vector3.RIGHT, 0.85, 0.0, 75.0, true],
	["skirt_rear.R", Vector3.RIGHT, "thigh.R", Vector3.RIGHT, 0.0, 0.85, 75.0, true],
	["skirt_rear.L", Vector3.RIGHT, "thigh.L", Vector3.RIGHT, 0.0, 0.85, 75.0, true],
	["skirt_side.R", Vector3.BACK, "thigh.R", Vector3.BACK, 1.0, 0.0, 30.0, true],
	["skirt_side.L", Vector3.BACK, "thigh.L", Vector3.BACK, 0.0, 1.0, 30.0, true],
	["skirt_side.R", Vector3.RIGHT, "thigh.R", Vector3.RIGHT, 0.35, 0.35, 30.0, true],
	["skirt_side.L", Vector3.RIGHT, "thigh.L", Vector3.RIGHT, 0.35, 0.35, 30.0, true],
	["shoulder.R", Vector3.RIGHT, "upper_arm.R", Vector3.RIGHT, 1.0, 1.0, 120.0, true, Vector2(25, 70), true],
	["shoulder.L", Vector3.RIGHT, "upper_arm.L", Vector3.RIGHT, 1.0, 1.0, 120.0, true, Vector2(25, 70), true],
	["shoulder.R", Vector3.BACK, "upper_arm.R", Vector3.BACK, 0.5, 0.5, 40.0, true],
	["shoulder.L", Vector3.BACK, "upper_arm.L", Vector3.BACK, 0.5, 0.5, 40.0, true],
]

# Poses: bone → list of [axis, degrees] rotations in skeleton space (applied in order).
# Rifle ready, held low: upper arm a little forward, elbow bent so the forearm and rifle
# point ahead at chest height, below the head's line of sight. The aim straightens the
# elbow toward the envelope's edges (MsWeapon.elbow_*).
const POSE_RIFLE := {
	"upper_arm.R": [[Vector3.RIGHT, 40.0], [Vector3.BACK, -8.0]],
	"forearm.R": [[Vector3.RIGHT, 50.0]],
	"hand.R": [],
}

# Rifle held low (in the hand, nothing locked): the arm a little forward and out, the
# elbow bent so the rifle points ahead and down past the leg. The arm stays free for AMBAC.
const POSE_RIFLE_LOW := {
	"upper_arm.R": [[Vector3.RIGHT, 3.0], [Vector3.BACK, 7.0]],
	"forearm.R": [[Vector3.RIGHT, 8.0]],
	"hand.R": [],
}
# Rifle ready / low blend in about as fast as the rifle comes up (MsWeapon.ready_time).
const RIFLE_POSE_BLEND := 0.4

# The rifle's stow: horizontal across the rear skirts below the main pods and in front of
# the hyper bazooka (which hangs behind the waist from 7.9 m to 19 m), muzzle left, grip
# down, held by a stow arm in a bay behind the right rear skirt's red marking (a hatch door
# in the model). Drawn, the door opens, the arm comes out and turns the rifle ~80° about
# the front-back axis (nothing flips: muzzle down, top inward, grip pointing right at the
# hand, flat side still toward the skirt) to RIFLE_GRAB behind the right hip, 10° short of
# vertical so the stock clears the main pod and the backpack and the barrel passes right
# of the bazooka. The hand reaches back for it like for a pistol on the hip (a pilot's own
# move): upper arm back, elbow out and back, the hand onto the grip from outside; the
# shoulder turns back and shrugs up a little (RIFLE_LEAN). It brings it back past the calf
# and forward round the outside of the leg (RIFLE_DRAW_KEYS) up to low ready, while the empty arm goes back in and
# the door shuts.
# Keys are where the rifle is: its wrist end, barrel and top directions, body frame.
const RIFLE_STOW := [Vector3(4.4, 10.4, 3.4), Vector3(-1, 0, 0), Vector3(0, 1, 0)]
const RIFLE_GRAB := [Vector3(5.2, 13.8, 3.45), Vector3(-0.17, -0.975, 0.14), Vector3(-0.985, 0.17, 0)]
# The turn itself stays in the plane of the back (the barrel crosses behind the bazooka);
# only once turned does the barrel tip back a little (its lower end behind the right calf).
const RIFLE_TURNED := [Vector3(5.2, 13.8, 3.45), Vector3(-0.174, -0.985, 0), Vector3(-0.985, 0.174, 0)]
# Pulled back and up, the muzzle swinging back (it hangs between the calves: it passes
# behind the right one), out (the muzzle swings out) while it starts turning its top forward, then forward beside the
# leg, barrel angled out: the rifle's body goes round the outside of the leg (straight from
# behind to low ready it cuts through it).
const RIFLE_DRAW_KEYS := [
	[Vector3(5.4, 14.6, 4.6), Vector3(-0.1, -0.93, 0.35), Vector3(-0.99, 0.1, 0.0)],
	[Vector3(6.5, 14.6, 3.0), Vector3(0.33, -0.9, 0.28), Vector3(-0.85, -0.3, -0.45)],
	[Vector3(6.4, 14.6, 1.0), Vector3(0.35, -0.85, -0.4), Vector3(-0.45, 0.25, -0.85)],
]
# The shoulder turns back and shrugs up for the reach, as a person's does: the waist
# twists a little, the collarbone goes back and up.
const RIFLE_LEAN := {
	"spine": [[Vector3.UP, -10.0], [Vector3.BACK, -5.0]],
	"clavicle.R": [[Vector3.UP, -10.0], [Vector3.BACK, 12.0]],
}
# The hatch: the red marking at the top of the right rear skirt, cut out as a door
# (build_mobile_suit_nu.py SKIRT_HATCH_*, bone skirt_hatch.R): centre, outward normal,
# hinge along its top edge, size. The stow arm's first link swings from folded in (into
# its bay, down) to straight out of it (RIFLE_ARM_LINK m), so the boom on to the gripper
# runs clear of the plate.
const RIFLE_HATCH := [Vector3(1.387, 14.01, 1.77), Vector3(0.257, 0.305, 0.917), Vector3(0.964, -0.019, -0.264),
		Vector2(0.91, 0.88)]
const RIFLE_ARM_LINK := 1.0
const RIFLE_ARM_IN := Vector3(0.0, -0.6, -1.0)
const RIFLE_ARM_OUT := Vector3(0.25, 0.4, 0.88)
# Where the gripper holds the rifle (its frame: side, top, back from the wrist end): the
# middle of its top edge, 3 m down the body from the wrist end (past the hand's fingers),
# fingers down both flat faces (0.63 m apart). Stowed that edge is right under the hatch;
# turned, it faces in, toward it: the arm always comes from the hatch's side.
const RIFLE_ARM_CLAMP := Vector3(0.27, 3.2, -3.0)
const RIFLE_GRIP_SPAN := 0.63
# The rifle's bulk the hand's arm keeps out of, in the rifle's frame (wrist at the origin,
# top +Y, muzzle −Z): its body from the stock end to the muzzle, 2.4 m over the wrist.
const RIFLE_CLEARANCE := [[Vector3(0.27, 2.4, 2.2), Vector3(0.27, 2.4, -9.4), 0.8]]

# Dug in behind the shield: the waist turns the left side 30° toward the threat (the hips
# stay: turning them turns the whole suit's mass and kicks the hull), the arm holds the
# shield in front with a natural bend, and the shield turns itself upright on its swivel
# (thigh to above the head, facing ahead). The legs aren't posed: they stay free for
# balancing. Solved for on the skeleton: the face points straight ahead, the shield stands
# upright and clears the chest front.
const POSE_SHIELD := {
	"spine": [[Vector3.UP, -30.0]],
	"upper_arm.L": [[Vector3.RIGHT, 10.0], [Vector3.BACK, 20.0]],
	"forearm.L": [[Vector3.RIGHT, 60.0], [Vector3.UP, -60.0]],
	"hand.L": [],
	"shield_mount.L": [[Vector3.RIGHT, -90.0]],
}
# Left arm raised forward: the shield's tip, where its missiles launch from, points ahead.
const POSE_SHIELD_FIRE := {
	"upper_arm.L": [[Vector3.RIGHT, 80.0], [Vector3.BACK, -6.0]],
	"forearm.L": [[Vector3.RIGHT, 10.0]],
	"hand.L": [],
}
# The twin head vulcans: between the muzzles, and each muzzle's offset to the side.
const VULCAN_POSITION := Vector3(0.0, 20.33, -1.15)
const VULCAN_SPACING := 0.57
const IDLE_BONES := ["upper_arm.R", "upper_arm.L", "forearm.R", "forearm.L", "hand.R", "hand.L",
		"thigh.R", "thigh.L", "shin.R", "shin.L", "spine", "head"]
const IDLE_LENGTH := 8.0

var _skel: Skeleton3D
var _skel_in_body := Transform3D.IDENTITY


func _initialize() -> void:
	var model: Node3D = load(MODEL).instantiate()
	_skel = model.get_node(^"Armature/Skeleton3D")
	_skel_in_body = model.get_node(^"Armature").transform * _skel.transform

	DirAccess.make_dir_recursive_absolute(DIR + "Animations")
	var library := _build_animations()
	ResourceSaver.save(library, ANIM_PATH)
	library = load(ANIM_PATH)

	var root := _build_scene(library)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
	ResourceSaver.save(packed, SCENE_PATH)
	print("[build_rx93_scene] wrote %s and %s" % [SCENE_PATH, ANIM_PATH])
	model.free()
	root.free()
	quit()


# --- Scene ---

func _build_scene(library: AnimationLibrary) -> RigidBody3D:
	var root := RigidBody3D.new()
	root.name = "MobileSuitRX93"
	root.set_script(load("res://Entities/Vehicles/MobileSuits/Common/mobile_suit_body.gd"))
	root.gravity_scale = 0.0
	root.can_sleep = false
	root.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	root.center_of_mass = COM
	root.mass = 46400.0
	# Seen from the seat through the open hatch: the airlock corridor (built into the
	# chest mesh) and the outer door.
	root.set("first_person_parts", [&"Chest", &"Hatch"] as Array[StringName])

	var model: Node3D = load(MODEL).instantiate()
	model.name = "Model"
	_add(root, root, model)

	for c in COLLIDERS:
		var shape := CollisionShape3D.new()
		shape.name = "Col" + c[0]
		var box := BoxShape3D.new()
		box.size = c[2]
		shape.shape = box
		shape.position = c[1] - Vector3(0, BELLY_DROP, 0) if c[0] in ["Pelvis", "LegR", "LegL", "FootR", "FootL"] else c[1]
		_add(root, root, shape)

	# The arms as outlines on the panoramic screen in DGFT / BVR (FireControl shows the
	# layer), so the rifle's arm is seen without the body blocking the view.
	var arms := SensorOutline.new()
	arms.name = "ArmOutline"
	arms.sensor_layer = Layers.SENSOR_COMBAT
	arms.shown_by_fire_control = true
	arms.fill_alpha = 0.04
	arms.per_mesh = true
	arms.only_meshes = [&"UpperArmL", &"UpperArmR", &"ForearmL", &"ForearmR", &"HandL", &"HandR"] as Array[StringName]
	_add(root, root, arms)

	var sensor_mount := _marker(root, "SensorHeadMount", Vector3(0, 20.0, -1.4))
	_add(root, sensor_mount, load(SENSOR_SCENE).instantiate())
	# Lowered (and back) so the airlock to the chest door is less steep; the fit test keeps
	# the whole cockpit sphere inside the hull here.
	var cockpit_mount := _marker(root, "CockpitMount", Vector3(0, 16.6, -0.2))
	_add(root, cockpit_mount, load(COCKPIT_SCENE).instantiate())

	_build_thrusters(root)
	_build_hatch(root)
	_build_flight_computer(root)
	_build_ambac(root)
	_build_limb_reaction(root)
	_build_thruster_guards(root)
	_build_stances(root)
	_build_limb_followers(root)
	_build_loadout(root)
	_build_animation(root, library)
	_build_fire_control(root)

	var cam := Camera3D.new()
	cam.name = "ExternalCamera"
	cam.set_script(load("res://Common/Controls/OrbitCamera/orbit_camera.gd"))
	cam.far = 8000.0
	_add(root, root, cam)
	cam.set("focus_offset", Vector3(0, 13.0, 0))
	cam.set("distance", 45.0)
	var views := Node.new()
	views.name = "ViewSwitcher"
	views.set_script(load("res://Entities/Vehicles/Components/ViewSwitcher/view_switcher.gd"))
	_add(root, root, views)
	views.set("external_camera", cam)
	return root


func _build_thrusters(root: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Thrusters"
	_add(root, root, group)
	var thruster_scene: PackedScene = load(THRUSTER_SCENE)
	var attachments := {}
	for t in THRUSTERS:
		var bone: String = t[1]
		if not attachments.has(bone):
			var attach := BoneAttachment3D.new()
			attach.name = "Attach_" + bone.replace(".", "_")
			attach.bone_name = bone
			attach.use_external_skeleton = true
			attach.external_skeleton = NodePath("../../" + String(SKELETON))
			_add(root, group, attach)
			attachments[bone] = attach
		var pos: Vector3 = _lowered(t[2], t[1])
		var exhaust: Vector3 = (t[3] as Vector3).normalized()
		var up := Vector3.UP if absf(exhaust.dot(Vector3.UP)) < 0.95 else Vector3.BACK
		# Thruster −Z = thrust direction = opposite of the exhaust.
		var basis := Basis.looking_at(-exhaust, up)
		if SWING_2D.has(t[0]):
			basis = _swing_basis(exhaust, SWING_2D[t[0]][0])
		var body_xf := Transform3D(basis, pos)
		var node: Node3D = thruster_scene.instantiate()
		node.name = t[0]
		_add(root, attachments[bone], node)
		node.transform = _bone_rest_in_body(bone).affine_inverse() * body_xf
		var rating: float = t[4]
		var is_main := rating >= MAIN_RATING_KN
		node.set("max_thrust", rating * THRUST_SCALE * 1000.0)
		var dynamics: Dictionary = MAIN_DYNAMICS if is_main else VERNIER_DYNAMICS
		for key: String in dynamics:
			node.set(key, dynamics[key])
		var gimbal: Array = t[5]
		node.set("gimbal_limit_deg", gimbal[0])
		node.set("gimbal_pitch_limit_deg", gimbal[1])
		node.set("gimbal_yaw_limit_deg", gimbal[2])
		node.set("plume_length", t[6])
		node.set("nozzle_scale", t[7])
		node.set("hud_label", _short_label(t[0]))
		node.set("show_nozzle", t[8])
		node.set("exhaust_fx", true)
		if is_main:
			node.set("glow_light_energy", MAIN_GLOW_LIGHT)
		if t[0].begins_with("Main"):
			node.set("gimbal_rate_deg", 90.0)  # a whole pod swings fore/aft
			node.set("gimbal_yaw_rate_deg", 240.0)  # the nozzle alone swings sideways
			# Outward only (MAIN_CONE's 5° each side of a 5° bias): local +X is the body's
			# +X, and +yaw tips the thrust that way, i.e. the exhaust inward.
			var right := (t[2] as Vector3).x > 0.0
			node.set("gimbal_yaw_bias_deg", -5.0 if right else 5.0)
		elif t[0].begins_with("Calf"):
			node.set("gimbal_rate_deg", 120.0)
		if SLOTS.has(t[0]):
			var slot: Array = SLOTS[t[0]]
			node.set("plume_slot", body_xf.basis.inverse() * (slot[0] as Vector3))
			node.set("nozzle_scale", slot[1])
		if POD_HINGE.has(t[0]):
			node.set("swing_pivot", body_xf.affine_inverse() * (POD_HINGE[t[0]] as Vector3))
		if CALF_HINGE.has(t[0]):
			node.set("swing_pivot", body_xf.affine_inverse() * _lowered(CALF_HINGE[t[0]], "calf_guard"))
		if SWING_2D.has(t[0]):
			var lo: float = SWING_2D[t[0]][1]
			var hi: float = SWING_2D[t[0]][2]
			node.set("gimbal_limit_deg", maxf(absf(lo), absf(hi)))
			node.set("gimbal_pitch_limit_deg", (hi - lo) * 0.5)
			node.set("gimbal_pitch_bias_deg", (hi + lo) * 0.5)
			node.set("gimbal_yaw_limit_deg", 0.0)


func _build_flight_computer(root: Node3D) -> void:
	var fc := Node.new()
	fc.name = "FlightComputer"
	fc.set_script(load("res://Entities/Vehicles/Components/FlightControl/flight_computer.gd"))
	_add(root, root, fc)
	var law := RateCommandControlLaw.new()
	law.attitude_solver = ThrustVectoringAttitudeSolver.new()
	# Roll at most 30° into a strafe: rolling further adds a little top acceleration but
	# a reversal then has to roll all the way back over first (full boost: 4.5 m in its
	# first second at 45°, 7.5 m at 30°). Pitch keeps 60° for dashes and climbs.
	law.attitude_solver.axis_limit_deg = Vector3(60.0, 3.0, 30.0)
	# The ν's clean yaw torque (~8 MN·m) is the same while it pushes at 4 G in any direction
	# (measured with its allocator): yaw keeps all of it under load, pitch and roll plan with 60%.
	law.loaded_torque_share = Vector3(0.6, 1.0, 0.6)
	# Movement limits ×1.5 with the thrust (THRUST_SCALE), so each keeps its share of it.
	law.cruise_accel_g = 1.2
	law.boost_accel_g = 10.5
	law.stop_accel_g = 9.0
	fc.set("control_law", law)
	var alloc := ConeProjectedAllocator.new()
	# The tight step goes ~2.3x further an iteration than the per-thruster bound: 30 of
	# them miss the demand by about what 60 did (Docs/Performance/frame_budget.md).
	alloc.tight_step = true
	alloc.iterations = 30
	fc.set("allocator", alloc)
	# Official empty weight 27.9 t; equipment ~15.9 t with the fin funnels (the flight tuning
	# predates their 6 t); propellant fills the rest of the
	# official 63.0 t max weight (every spare volume, like a fighter).
	fc.set("dry_mass", DRY_MASS)
	fc.set("propellant_capacity", PROPELLANT)
	fc.set("propellant", PROPELLANT)
	fc.set("specific_impulse", 12000.0)

	var input := Node.new()
	input.name = "PilotInput"
	input.set_script(load("res://Common/Controls/PilotInput/twin_stick_pilot_input.gd"))
	_add(root, fc, input)


## An airlock: the red outer door at the bottom of the chest slides up behind the chest
## front; behind it a corridor leads to the cockpit's own inner door. Order: the seat and
## right armrest turn clear (HatchCockpitParts, 0–0.25), the screen opens a doorway down
## the corridor, the inner door slides apart (0.35–0.6), then the outer door (0.6–1).
func _build_hatch(root: Node3D) -> void:
	var hatch := CockpitHatch.new()
	hatch.name = "CockpitHatch"
	_add(root, root, hatch)
	var door := HatchPanel.new()
	door.bone_name = &"hatch"
	door.open_angle_deg = 0.0
	# Along the door's own tilt (forward as it rises), past its full height, so it stays
	# behind the chest front and clear of the airlock corridor.
	door.slide = Vector3(0, 1.8, -0.69)
	door.window = Vector2(0.6, 1.0)
	hatch.panels = [door] as Array[HatchPanel]
	hatch.aperture_window = Vector2(0.2, 0.45)
	hatch.duration = 4.0
	hatch.skeleton = root.get_node(SKELETON)


func _build_limb_followers(root: Node3D) -> void:
	var node := LimbFollowers.new()
	node.name = "LimbFollowers"
	_add(root, root, node)
	node.skeleton = root.get_node(SKELETON)
	var list: Array[LimbFollower] = []
	for f in FOLLOWERS:
		var follower := LimbFollower.new()
		follower.bone_name = f[0]
		follower.axis = f[1]
		follower.source_bone = f[2]
		follower.source_axis = f[3]
		follower.positive = f[4]
		follower.negative = f[5]
		follower.min_angle_deg = -f[6]
		follower.max_angle_deg = f[6]
		follower.from_pose = f.size() > 7 and f[7]
		if f.size() > 8:
			follower.ease_in_deg = f[8]
		if f.size() > 9:
			follower.ease_in_positive_only = f[9]
		list.append(follower)
	node.followers = list


func _build_stances(root: Node3D) -> void:
	var node := StanceController.new()
	node.name = "StanceController"
	_add(root, root, node)
	var list: Array[MsStance] = []
	for st in STANCES:
		var stance := MsStance.new()
		stance.stance_name = st[0]
		stance.direction = st[1]
		stance.cone_deg = st[2]
		var bones := PackedStringArray()
		var axes := PackedVector3Array()
		var angles := PackedFloat32Array()
		for j in st[3]:
			bones.append(j[0])
			axes.append(j[1])
			angles.append(j[2])
		stance.bones = bones
		stance.axes = axes
		stance.angles_deg = angles
		if st.size() > 4:
			stance.transition_time = st[4]
		list.append(stance)
	node.stances = list


## Source-model position → stretched-model position: lower-body parts sit BELLY_DROP lower.
static func _lowered(pos: Vector3, bone: String) -> Vector3:
	for prefix: String in LOWER_BONE_PREFIXES:
		if bone.begins_with(prefix):
			return pos - Vector3(0, BELLY_DROP, 0)
	return pos


## Thruster basis for a one-plane swing: local X is the swing axis, so +pitch turns the
## exhaust toward `toward`, and +Z is the exhaust.
static func _swing_basis(exhaust: Vector3, toward: Vector3) -> Basis:
	var x := exhaust.cross(toward).normalized()
	return Basis(x, exhaust.cross(x), exhaust)


## The backpack pods and the calf plates (each carrying its nozzle) turn with their
## thrusters about their hinges; each main nozzle cup swings sideways in its pod with its
## thruster's own sideways gimbal; each foot eases after its sole nozzle's aim.
func _build_thruster_guards(root: Node3D) -> void:
	var node := ThrusterGuards.new()
	node.name = "ThrusterGuards"
	_add(root, root, node)
	node.skeleton = root.get_node(SKELETON)
	var guards: Array[ThrusterGuard] = []
	# bone, thrusters, full rotation (nozzle) or hinge (guard plate)
	for g in [["main_pod.R", ["MainRU", "MainRL"], false], ["main_pod.L", ["MainLU", "MainLL"], false],
			["calf_guard.R", ["CalfR"], false], ["calf_guard.L", ["CalfL"], false]]:
		var guard := ThrusterGuard.new()
		guard.bone_name = g[0]
		guard.thrusters = PackedStringArray(g[1])
		guard.full_rotation = g[2]
		if g[0].begins_with("main_pod"):
			guard.rest_thrust = -MAIN_MODEL_EXHAUST
			guard.min_angle_deg = -30.0  # back
			guard.max_angle_deg = 40.0   # forward, toward straight down
		if g[0].begins_with("calf_guard"):
			var side := 1.0 if g[0].ends_with(".R") else -1.0
			var exhaust := (CALF_MODEL_EXHAUST_R * Vector3(side, 1, 1)).normalized()
			guard.axis = _swing_basis(exhaust, Vector3.BACK).x
			guard.min_angle_deg = 0.0
			guard.max_angle_deg = 40.0
		guards.append(guard)
	# Each foot eases after its sole nozzle's aim.
	for n in [["foot.R", "SoleR"], ["foot.L", "SoleL"]]:
		var foot := ThrusterGuard.new()
		foot.bone_name = n[0]
		foot.thrusters = PackedStringArray([n[1]])
		foot.follow_aim = true
		foot.follow = FOOT_FOLLOW
		foot.smoothing_time = FOOT_SMOOTHING
		foot.max_rate_deg = FOOT_RATE_DEG
		foot.min_angle_deg = ANKLE_TOE_DOWN
		foot.max_angle_deg = ANKLE_TOE_UP
		foot.side_limit_deg = ANKLE_TILT
		guards.append(foot)
	# Turning about this tips the cup's exhaust toward −X: what +yaw (thrust to +X) does.
	var cup_axis := -MAIN_MODEL_EXHAUST.normalized().cross(Vector3.RIGHT).normalized()
	for n in [["main_nozzle_up.R", "MainRU"], ["main_nozzle_low.R", "MainRL"],
			["main_nozzle_up.L", "MainLU"], ["main_nozzle_low.L", "MainLL"]]:
		var cup := ThrusterGuard.new()
		cup.bone_name = n[0]
		cup.thrusters = PackedStringArray([n[1]])
		cup.follow_yaw = true
		cup.axis = cup_axis
		cup.smoothing_time = 0.0
		cup.min_angle_deg = -12.0
		cup.max_angle_deg = 12.0
		guards.append(cup)
	node.guards = guards


func _build_ambac(root: Node3D) -> void:
	var ambac := AmbacController.new()
	ambac.name = "Ambac"
	_add(root, root, ambac)
	ambac.skeleton = root.get_node(SKELETON)
	var joints: Array[AmbacJoint] = []
	for a in AMBAC:
		var j := AmbacJoint.new()
		j.bone_name = a[0]
		j.axis = a[1] if a[1] != Vector3.ZERO \
				else _skel.get_bone_global_rest(_skel.find_bone(a[0])).basis.y.normalized()
		j.group = a[2]
		j.inertia = a[3]
		j.min_angle_deg = a[4]
		j.max_angle_deg = a[5]
		j.priority = a[6]
		if j.bone_name.begins_with("thigh") or j.bone_name.begins_with("shin"):
			j.max_rate_deg = 150.0   # legs swing well beyond balancing travel for stances
			j.max_accel_deg = 600.0
		# Legs and waist are rated for the torque they were tuned with (table inertia × max
		# acceleration); the mass model's heavier limbs then swing slower on it. The arms
		# keep their acceleration limit (their mass was measured from the start).
		if not j.bone_name.begins_with("upper_arm") and not j.bone_name.begins_with("forearm"):
			j.max_torque = j.inertia * deg_to_rad(j.max_accel_deg)
		joints.append(j)
	ambac.joints = joints


func _build_limb_reaction(root: Node3D) -> void:
	var node := LimbReaction.new()
	node.name = "LimbReaction"
	_add(root, root, node)
	node.skeleton = root.get_node(SKELETON)
	node.reference_bone = &""
	node.drive_body_mass = true
	var weight := 0.0
	var tank := 0.0
	for p in PARTS:
		weight += p[1] * p[2]
		tank += p[1] * p[3]
	var list: Array[LimbSegment] = []
	for p in PARTS:
		var seg := LimbSegment.new()
		seg.bone_name = p[0]
		seg.mass = snappedf(DRY_MASS * p[1] * p[2] / weight, 0.1)
		seg.propellant_capacity = snappedf(PROPELLANT * p[1] * p[3] / tank, 0.1)
		list.append(seg)
	node.segments = list


## Weapons are exported where they sit on the suit, so they mount with an identity
## transform on the bone that carries them.
func _build_loadout(root: Node3D) -> void:
	var loadout := MsLoadout.new()
	loadout.name = "Loadout"
	_add(root, root, loadout)
	loadout.skeleton = root.get_node(SKELETON)
	for e in [["rx93_beam_rifle", &"hand.R", &"arm_r"], ["rx93_shield", &"shield_mount.L", &"arm_l"],
			["rx93_hyper_bazooka", &"backpack", &""], ["rx93_beam_saber", &"backpack", &""],
			["rx93_fin_funnels", &"backpack", &""]]:
		var eq: MsEquipment = load(EQUIPMENT + e[0] + ".tscn").instantiate()
		_add(root, loadout, eq)
		eq.mount_bone = e[1]
		eq.mount_transform = Transform3D.IDENTITY
		eq.ambac_group = e[2]
		if e[0] == "rx93_beam_rifle":
			eq.held_pose = &"rifle_low"
			eq.draw_motion = _rifle_draw(eq)


## The rifle's stow, its stow arm and the draw (RIFLE_*), as placements of the rifle
## relative to where it sits in the hand at rest.
func _rifle_draw(rifle: MsEquipment) -> MsDrawMotion:
	var muzzle := rifle.get_node(^"Weapon/Muzzle") as Node3D
	var in_hand := Transform3D(((rifle.get_node(^"Weapon") as Node3D).transform * muzzle.transform).basis.orthonormalized(),
			_bone_rest_in_body("hand.R").origin)
	var place := func(key: Array) -> Transform3D:
		var back := -(key[1] as Vector3).normalized()
		var side := (key[2] as Vector3).cross(back).normalized()
		return Transform3D(Basis(side, back.cross(side), back), key[0]) * in_hand.affine_inverse()
	var m := MsDrawMotion.new()
	m.stow_bone = &"skirt_rear.R"
	var clamp := in_hand * RIFLE_ARM_CLAMP
	var stow: Transform3D = place.call(RIFLE_STOW)
	var grab: Transform3D = place.call(RIFLE_GRAB)
	var turned: Transform3D = place.call(RIFLE_TURNED)
	# One turn about the front-back axis, the gripper carried from where it holds the stowed
	# rifle to where it holds the turned one; then the small tip back.
	var q0 := stow.basis.get_rotation_quaternion()
	var q1 := turned.basis.get_rotation_quaternion()
	var c0 := stow * clamp
	var c1 := turned * clamp
	var present: Array[Transform3D] = []
	for t in [0.33, 0.67]:
		var b := Basis(q0.slerp(q1, t))
		present.append(Transform3D(b, c0.lerp(c1, t) - b * clamp))
	present.append(turned)
	present.append(grab)
	print("[build_rx93_scene] rifle draw: gripper %s → %s, turned %.0f° about %s" % [
			c0.snapped(Vector3.ONE * 0.01), c1.snapped(Vector3.ONE * 0.01),
			rad_to_deg((q1 * q0.inverse()).get_angle()), (q1 * q0.inverse()).get_axis().snapped(Vector3.ONE * 0.01)])
	m.stow_transform = stow
	m.present_keys = present
	# The hand sets off while the stow arm is still turning it (it gets there as the turn ends).
	m.present_share = 0.75
	m.hand_start = 0.25
	m.hand_end = 1.0
	var draw: Array[Transform3D] = []
	for key: Array in RIFLE_DRAW_KEYS:
		draw.append(place.call(key))
	m.draw_keys = draw
	m.lean = RIFLE_LEAN
	m.lean_weights = PackedFloat32Array([1.0, 0.9, 0.6, 0.2])
	# Elbow out and back for the reach, then out round the hip.
	m.elbow_hints = PackedVector3Array([Vector3(1, 0.2, 0.6), Vector3(1, 0.2, 0.6), Vector3(1, 0.1, 0.3), Vector3(1, 0, 0)])
	m.hatch_bone = &"skirt_hatch.R"
	m.hatch_centre = RIFLE_HATCH[0]
	m.hatch_normal = RIFLE_HATCH[1]
	m.hatch_hinge = RIFLE_HATCH[2]
	m.hatch_size = RIFLE_HATCH[3]
	m.arm_link = RIFLE_ARM_LINK
	m.arm_in_dir = RIFLE_ARM_IN
	m.arm_out_dir = RIFLE_ARM_OUT
	m.arm_clamp = clamp
	# Gripper axes: out of the top edge, across it (the rifle's side), along it.
	m.arm_clamp_basis = Basis(in_hand.basis.y, in_hand.basis.x, in_hand.basis.y.cross(in_hand.basis.x))
	m.arm_grip_span = RIFLE_GRIP_SPAN
	m.upper_arm_bone = &"upper_arm.R"
	m.forearm_bone = &"forearm.R"
	m.hand_bone = &"hand.R"
	m.reach_time = 1.8
	m.draw_time = 1.5
	# Held still while it runs: the waist (the lean drives it) and the right rear skirt (the
	# stow arm stands on it). The legs stay free for AMBAC (and the stances), kept only from
	# swinging back into the rifle's path (draw_clip_probe.gd legs grid at=0.3 … 1.6): the
	# right thigh not behind vertical, its shin back ≤ thigh + knee −5°; the left thigh back
	# ≤ 5°, its shin back ≤ thigh + knee −40°. Forward they are free.
	m.held_groups = [&"torso", &"waist_bend"] as Array[StringName]
	m.held_followers = [&"skirt_rear.R"] as Array[StringName]
	m.drawing_leg_limits = [["", Vector3.RIGHT, "thigh.R", Vector3.RIGHT, "", Vector3.UP, 0.0, 0.0],
			["thigh.R", Vector3.RIGHT, "shin.R", Vector3.RIGHT, "", Vector3.UP, -5.0, 0.0],
			["", Vector3.RIGHT, "thigh.L", Vector3.RIGHT, "", Vector3.UP, -5.0, 0.0],
			["thigh.L", Vector3.RIGHT, "shin.L", Vector3.RIGHT, "", Vector3.UP, -40.0, 0.0]]
	# The calf plates swing back with their thrusters (up to 40°) into the rifle's path behind
	# the calves: held at rest while it runs.
	m.drawing_thruster_swing = {"CalfR": Vector2(0, 0), "CalfL": Vector2(0, 0)}
	# Stowed, the legs keep off it (draw_clip_probe.gd legs thighs / sweep): the right thigh no
	# further back than 20° (its skirt, carrying the stow arm, would tip the rifle into the
	# hyper bazooka), the left no further than 12° (its skirt would lift into the rifle), and
	# each shin no further back than thigh + knee −60° (right) / −75° (left). Only AMBAC's
	# balancing swings and the forward stance's trailing legs are cut short.
	m.stowed_leg_limits = [["", Vector3.RIGHT, "thigh.R", Vector3.RIGHT, "", Vector3.UP, -20.0, 0.0],
			["", Vector3.RIGHT, "thigh.L", Vector3.RIGHT, "", Vector3.UP, -12.0, 0.0],
			["thigh.R", Vector3.RIGHT, "shin.R", Vector3.RIGHT, "", Vector3.UP, -60.0, 0.0],
			["thigh.L", Vector3.RIGHT, "shin.L", Vector3.RIGHT, "", Vector3.UP, -75.0, 0.0]]
	for c: Array in RIFLE_CLEARANCE:
		m.clearance.append([in_hand * (c[0] as Vector3), in_hand * (c[1] as Vector3), c[2]])
	return m


func _build_animation(root: Node3D, library: AnimationLibrary) -> void:
	var player := AnimationPlayer.new()
	player.name = "PoseAnimations"
	_add(root, root, player)
	player.root_node = ^"../Model"
	player.add_animation_library(&"", library)
	var animator := MsPoseAnimator.new()
	animator.name = "PoseAnimator"
	_add(root, root, animator)
	animator.animation_player = player
	var layers: Array[MsPoseLayer] = []
	for p in [[&"rifle_low", POSE_RIFLE_LOW], [&"rifle_ready", POSE_RIFLE], [&"shield_guard", POSE_SHIELD],
			[&"shield_fire", POSE_SHIELD_FIRE]]:
		var layer := MsPoseLayer.new()
		layer.pose = p[0]
		layer.bones = PackedStringArray((p[1] as Dictionary).keys())
		if String(p[0]).begins_with("rifle"):
			layer.blend_time = RIFLE_POSE_BLEND
		layers.append(layer)
	animator.layers = layers


## Fire control, with the head vulcans (the rifle's and shield's weapons are in their
## equipment scenes). After the loadout and AMBAC, so its aim goes on top of theirs.
func _build_fire_control(root: Node3D) -> void:
	var fcs := FireControl.new()
	fcs.name = "FireControl"
	_add(root, root, fcs)
	# Targeting sensors: the lock is tracked from the head camera and the laser, not read
	# off the target (Docs/PhysicsAndSensors/sensors.md).
	var sensors := SensorSuite.new()
	sensors.name = "SensorSuite"
	_add(root, root, sensors)
	var vulcan := MsWeapon.new()
	vulcan.name = "Vulcan"
	_add(root, fcs, vulcan)
	vulcan.weapon_id = &"vulcan"
	vulcan.display_name = "60mm VULCAN"
	vulcan.hud_name = "VULCAN"
	vulcan.projectile = load("res://Entities/Projectiles/Specs/vulcan_60mm.tres")
	vulcan.max_ammo = 300
	vulcan.cycle_time = 60.0 / 1280.0   # 640 rpm per gun, two guns firing in turn
	vulcan.dispersion_deg = 0.22
	vulcan.always_on = true
	vulcan.ready_time = 0.3
	vulcan.mount_bone = &"head"
	vulcan.mount_position = VULCAN_POSITION
	vulcan.aim_bone = &"head"
	vulcan.az_limits = Vector2(-55.0, 55.0)
	vulcan.el_limits = Vector2(-25.0, 40.0)
	vulcan.slew_rate_deg = 200.0
	vulcan.on_target_deg = 0.6
	for side in [["MuzzleR", 1.0], ["MuzzleL", -1.0]]:
		var muzzle := Marker3D.new()
		muzzle.name = side[0]
		_add(root, vulcan, muzzle)
		muzzle.position = Vector3(VULCAN_SPACING * side[1], 0.0, 0.0)


# --- Animations ---

func _build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle())
	lib.add_animation(&"rifle_low", _pose(POSE_RIFLE_LOW))
	lib.add_animation(&"rifle_ready", _pose(POSE_RIFLE))
	lib.add_animation(&"shield_guard", _pose(POSE_SHIELD))
	lib.add_animation(&"shield_fire", _pose(POSE_SHIELD_FIRE))
	return lib


## Relaxed zero-g float: slightly bent knees and elbows, held still (no sway, so the
## suit never looks like it's drifting).
func _idle() -> Animation:
	var anim := Animation.new()
	anim.length = IDLE_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	for bone: String in IDLE_BONES:
		var track := _track(anim, bone)
		anim.rotation_track_insert_key(track, 0.0, _local(bone, _idle_rotations(bone)))
	return anim


func _idle_rotations(bone: String) -> Array:
	var side := 1.0 if bone.ends_with(".R") else -1.0
	var table := {
		"upper_arm": [[Vector3.RIGHT, 4.0], [Vector3.BACK, 6.0 * side]],
		"forearm": [[Vector3.RIGHT, 12.0]],
		"thigh": [[Vector3.RIGHT, 8.0], [Vector3.BACK, 3.0 * side]],
		"shin": [[Vector3.RIGHT, -14.0]],
		"head": [[Vector3.RIGHT, -3.0]],
	}
	return table.get(bone.get_slice(".", 0), [])


func _pose(pose: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = 0.1
	for bone: String in pose:
		anim.rotation_track_insert_key(_track(anim, bone), 0.0, _local(bone, pose[bone]))
	return anim


func _track(anim: Animation, bone: String) -> int:
	var track := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(track, NodePath("Armature/Skeleton3D:" + bone))
	return track


## Skeleton-space rotations (applied in order) → bone-local pose rotation.
func _local(bone: String, rotations: Array) -> Quaternion:
	var idx := _skel.find_bone(bone)
	var q := Quaternion.IDENTITY
	for r in rotations:
		q = Quaternion((r[0] as Vector3).normalized(), deg_to_rad(r[1])) * q
	var g := _skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	var rest := _skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	return rest * (g.inverse() * q * g)


# --- Helpers ---

func _bone_rest_in_body(bone: String) -> Transform3D:
	return _skel_in_body * _skel.get_bone_global_rest(_skel.find_bone(bone))


func _marker(root: Node3D, node_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.position = pos
	_add(root, root, m)
	return m


func _add(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


static func _short_label(node_name: String) -> String:
	return node_name.to_upper().replace("FRONT", "F").replace("REAR", "B").replace("SIDE", "S") \
			.replace("MAIN", "MN").replace("TOP", "T").replace("CHEST", "CH").replace("FOOT", "FT")
