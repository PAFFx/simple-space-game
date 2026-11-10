# Prototype Mobile Suit (MSP-01) and Linear Seat Cockpit

## Scene tree

```
MobileSuitPrototype (RigidBody3D + MobileSuitPrototype script, extends VehicleBase)
├── Model                       procedural GLB (Armature/Skeleton3D, one mesh per part)
├── Col*                        box colliders (inertia comes from these + mass)
├── SensorHeadMount/SensorHead  at the visor
├── CockpitMount/CockpitLinearSeat
│   ├── Model                   seat, consoles, grips, pedals, MFD, capsule shell
│   ├── PanoramicDisplayMount/PanoramicScreen (r = 1.25 m)
│   ├── CameraMount/PlayerCamera3D/MouseLookController
│   ├── CockpitLight            omni, lights COCKPIT layer only
│   ├── ControlsAnimator        grips/pedals follow the PilotCommand
│   └── PanoramicHud
├── Thrusters/Attach_<bone>/<Thruster>   BoneAttachment3D (external skeleton) per bone
├── FlightComputer/PilotInput
├── CockpitHatch                bone-driven hatch + screen aperture
├── ExternalCamera              OrbitCamera
└── ViewSwitcher
```

`VehicleBase` only requires `Node3D`, so the root can be a `RigidBody3D`: the cockpit, sensor and
thrusters are all carried by the simulated body. Gravity is 0 and damping is replaced with 0
(space). The centre of mass is set explicitly to `(0, 12.8, 0.4)`.

## Rig

Bones: `root, pelvis, spine, chest, head, backpack, hatch_upper, hatch_lower` plus
`shoulder/upper_arm/forearm/hand/skirt_front/skirt_side/thigh/shin/foot` with `.L` / `.R`.

Each part mesh is weighted 100% to one bone (a rigid mech rig). Mesh nodes are separate, so
render layers can be set per part (e.g. `SENSOR_BODY_PARTS`) later.

## Render layers

| What | Layers | Why |
|------|--------|-----|
| Suit parts | `VEHICLE_EXT` | Outside cameras only |
| Chest + hatch flaps | `VEHICLE_EXT \| VEHICLE_FP` | Pilot sees the cavity and hatch through the open aperture |
| Cockpit interior | `COCKPIT \| VEHICLE_EXT` | Pilot + outside cameras looking in; never the sensor |
| Thrusters + plumes | `VEHICLE_EXT` | Keeps the sensor image clean |

## Regenerating the models

Both models are built by Blender scripts in `Tools/Blender/` (see the README there). Edit the
script, re-run it, and Godot re-imports the GLB. Node and bone names stay stable, so the scenes
keep working.

## Design notes (late-UC cockpit)

- **Linear seat:** the seat floats on a boom at the centre of the 360° screen, so the pilot's eye
  is at the sphere centre and the reprojection is near-perfect.
- **Minimal physical controls:** two multi-function grips (right = rotation, left =
  translation with twist for up/down), pedals for yaw, a few console buttons. Everything else
  lives on the HUD/MFDs, in line with modern fighter philosophy (fewer steps, automated non-essentials).
- **Clamshell chest hatch** opening into a cavity sized around the capsule (2.8 m cube), with the
  screen aperture opening first, as in later UC designs.
