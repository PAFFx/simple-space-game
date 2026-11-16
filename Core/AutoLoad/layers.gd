extends Node

const WORLD := 1 << 0
const VEHICLE_EXT := 1 << 1
const VEHICLE_FP := 1 << 2
const COCKPIT := 1 << 3
const PILOT := 1 << 4
const FX := 1 << 5
const HUD_3D := 1 << 6

# Sensor-specific sub-layers for fine-grained sensor occlusion toggling.
# Assign these to MeshInstance3D nodes IN ADDITION to VEHICLE_EXT so they
# remain visible to the third-person camera while being individually
# toggleable on the sensor camera via SensorHead.set_group_visible().
const SENSOR_BODY_PARTS := 1 << 7  # The suit's own body and carried weapons (shown in DGFT / BVR)
const SENSOR_WEAPONS    := 1 << 8  # Weapons (beam rifles, missile pods, etc.)
const SENSOR_SHIELDS    := 1 << 9  # Shields and armour panels
const SENSOR_COMBAT     := 1 << 10 # Outlines of the arms and the gun, shown in DGFT / BVR

const DEBUG := 1 << 19

# Physics layers.
## Shields: shot and sensor rays hit them, nothing collides with them (the suit carrying
## one never touches it).
const PHYS_SHIELD := 1 << 1

const MASK_THIRD_PERSION := WORLD | VEHICLE_EXT | FX
const MASK_FIRST_PERSON  := WORLD | VEHICLE_FP | COCKPIT | PILOT | FX | HUD_3D
# Sensor sees world + all sensor sub-layers. Includes VEHICLE_EXT so existing
# mech meshes (before sensor layers are assigned) still appear in the sensor view.
# Excludes COCKPIT to prevent the panoramic screen from appearing on itself.
const MASK_SENSOR        := WORLD | VEHICLE_EXT | FX \
                          | SENSOR_BODY_PARTS | SENSOR_WEAPONS | SENSOR_SHIELDS
