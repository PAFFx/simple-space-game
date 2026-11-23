# Project Structure

## Directory Overview

```
simple-space-game/
├── Core/                          Base classes and project-wide singletons
│   ├── AutoLoad/                  Godot autoload singletons (registered in project.godot)
│   │   ├── layers.gd              Render layer bitmask definitions (Layers.WORLD, COCKPIT, etc.)
│   │   └── perf_overlay.gd        F3 performance overlay (FPS / frame times / render stats)
│   └── Base/                      Abstract base classes (interfaces)
│       ├── vehicle_base.gd        Abstract root for all pilotable vehicles
│       └── cockpit_base.gd        Abstract root for all cockpit interiors
│
├── Common/                        Reusable components with no entity-specific dependencies
│   ├── Calculations/              Pure-math, stateless utility classes
│   │   └── spatial_math.gd        General 3D math (ray-sphere intersection, etc.)
│   └── Controls/                  Player input components
│       ├── MouseLookController/
│       │   ├── mouse_look_controller.gd   Rotates parent Node3D from mouse input (current camera only)
│       │   └── mouse_look_controller.tscn
│       ├── OrbitCamera/           External camera orbiting a target in its own frame
│       └── PilotInput/            PilotCommand + swappable input sources (keyboard, twin sticks, HOTAS)
│
├── Entities/                      All game entities (characters, vehicles, environment)
│   ├── Characters/
│   │   └── AmateYuzuriha/         Pilot character model
│   │
│   ├── Equipment/                 Suit equipment, modelled and stored separately from suits
│   │   ├── Components/            MsEquipment base (mount, mass, pose, AMBAC group, input)
│   │   ├── BeamRifle/             Beam rifle scene + GLB
│   │   └── Shield/                Shield scene + GLB + HudSilhouette outline
│   │
│   ├── Projectiles/               ProjectileSpec, ProjectileManager, beam / flash shaders,
│   │                              Sounds/ (shot fire sounds, built by Tools/Audio)
│   │
│   ├── Environment/
│   │   └── Space/
│   │       ├── SpaceStation/      Space station with constant rotation components
│   │       ├── DebrisField/       MultiMesh rock shell for motion cues
│   │       ├── NavBuoy/           Blinking buoy that registers as a HUD contact
│   │       └── TargetDrone/       Practice targets: static, drifting, jinking, turret
│   │
│   └── Vehicles/
│       ├── Components/            Vehicle-level components shared across vehicle types
│       │   ├── FlightControl/     FlightComputer, Thruster, ControlLaws/, Allocators/, AttitudeSolvers/
│       │   ├── Ambac/             AMBAC limb balancing (controller, joints, skeleton modifier)
│       │   ├── Loadout/           MsLoadout: mounts equipment on bones, toggles it
│       │   ├── FireControl/       FireControl, MsWeapon, WeaponAimModifier (see Docs/Weapons)
│       │   ├── PoseAnimator/      AnimationTree with per-limb equipment pose layers
│       │   ├── Hatch/             CockpitHatch + HatchPanel (bone-driven, sequences screen aperture)
│       │   └── ViewSwitcher/      Cockpit ↔ external camera toggle
│       ├── Cockpits/              All cockpit interiors
│       │   ├── Components/        Cockpit components shared across cockpit types
│       │   │   ├── PanoramicDisplay/
│       │   │   │   ├── sensor_head.gd          Sensor camera manager
│       │   │   │   ├── sensor_head.tscn
│       │   │   │   ├── panoramic_screen.gd     Spherical display mesh + shader control
│       │   │   │   ├── panoramic_screen.tscn
│       │   │   │   ├── Helper/
│       │   │   │   │   └── sensor_fov_solver.gd   FOV + viewport sizing math
│       │   │   │   ├── Mesh/
│       │   │   │   │   └── panoramic_mesh_builder.gd  Sphere mesh generation
│       │   │   │   └── Shader/
│       │   │   │       └── panoramic_screen.gdshader  Reprojection + HUD composite + aperture
│       │   │   ├── PanoramicHud/  Equirectangular HUD canvas + HudWidget instruments + HudSilhouette
│       │   │   ├── SeatGimbal/    CockpitGimbal: keeps the cockpit on the pilot frame
│       │   │   ├── ControlsAnimator/  Grips/pedals follow the PilotCommand
│       │   │   └── SeatedPilot/   Character in the seat: pose, IK onto the controls, G lean
│       │   │
│       │   ├── CockpitLinearSeat/ Late-UC linear seat cockpit (extends CockpitBase)
│       │   ├── CockpitLinearSeatV2/  RX-93 cockpit: contoured seat, seated pilot (CockpitLinearSeat script)
│       │   ├── CockpitLinearSeatV2Rail/  the same with RX-0 style rail grips (slide, twist, roll)
│       │   └── CockpitRX0/        RX-0 specific cockpit interior
│       │       ├── cockpit_rx_0.gd    extends CockpitBase
│       │       ├── cockpit_rx_0.tscn
│       │       └── Arts/              Cockpit GLB import
│       │
│       └── MobileSuits/           All mobile suit vehicles
│           ├── Common/            MobileSuitBody: generic RigidBody suit root
│           ├── MSP02/             MSP-02 late-UC suit (generated scene, animations, GLB)
│           ├── Prototype/         MSP-01 prototype: RigidBody root, thrusters on bones, FCS, hatch
│           └── RX0/               RX-0 Full Armor Unicorn Gundam
│               ├── mobile_suit_rx_0.gd    extends VehicleBase
│               ├── mobile_suit_rx_0.tscn
│               └── Arts/                  Mech GLB import
│
├── Stages/                        Playable levels / scenes
│   ├── MobileSuitTestRange/       Main stage: MSP-02, station, buoys, debris field
│   └── LowEarthOrbit/
│       └── low_earth_orbit.tscn   Original RX-0 panoramic display stage
│
├── Docs/                          Architecture documentation
│   ├── structure.md               This file
│   ├── Audio/                     Buses, shot sounds, SFX lab
│   ├── FlightControl/             Thrusters, FBW control laws, allocation, controls
│   ├── MobileSuit/                Prototype suit + linear seat cockpit
│   ├── Performance/               Frame budget snapshots (where the frame time goes)
│   └── PanoramicCockpit/          Deep-dive docs for the panoramic display system + HUD
│
├── Tools/                         Non-Godot tooling (ignored by Godot via .gdignore)
│   ├── Audio/                     SFX lab: builds game sounds from sources (uv, sox, SuperCollider)
│   ├── Blender/                   Procedural model build scripts
│   ├── Flight/                    Flight-control probes and snapshots
│   ├── Godot/                     Scene generators (MSP-02 scene + animation library)
│   ├── Profiling/                 Frame-time probes (phases, cost per subtree, zoom cost, combat bench)
│   └── Weapons/                   Weapons, sensors and combat HUD probes (weapons, search
│                                  tracks, gun circle, HUD steadiness, hit rate) and snapshots
│
└── addons/                        Editor plugins (gdshader, plugin_refresher, gdLinter)
```

---

## Layer Architecture

The project follows a strict dependency direction:

```
Stages
  └── depends on → Entities
                      └── depends on → Core/Base, Common, Cockpits/Components
                                           └── depends on → Core/AutoLoad, Common/Calculations
```

- **`Core/`** has no game dependencies — only Godot built-ins.
- **`Common/`** depends only on `Core/` (for `Layers` autoload, `VehicleBase`, `CockpitBase`).
- **`Entities/`** depends on `Core/` and `Common/`.
- **`Stages/`** depends on `Entities/` only — no direct component references.

---

## Core/Base — Abstract Interfaces

Godot 4 has no interface keyword. Interfaces are implemented as base classes whose unimplemented
virtual methods call `push_error()` at runtime.

### `VehicleBase`

Root script for any pilotable vehicle (mobile suit, ship, fighter, etc.). It only requires
`Node3D`, so it can sit on a `RigidBody3D` root (see `MobileSuitPrototype`).
`find_component(Script)` returns the first descendant of a given script class, for one-off lookups
such as `vehicle.find_component(FlightComputer)`.

**To create a new vehicle:**
1. Create a scene whose root node has a script extending `VehicleBase`.
2. Add a `Marker3D` named `SensorHeadMount` — place the `SensorHead` scene as its child.
3. Add a `Marker3D` named `CockpitMount` — place the cockpit scene as its child.
4. Implement `get_sensor_head_mount()` and `get_cockpit_mount()` using `get_node()`.

```gdscript
class_name MyShip extends VehicleBase

func get_cockpit_mount() -> Marker3D:
    return get_node("CockpitMount") as Marker3D

func get_sensor_head_mount() -> Marker3D:
    return get_node("SensorHeadMount") as Marker3D
```

**Important:** Use `get_node()` directly — not `@onready` — so the getters work when called from
a child's `_ready()`, which fires before the parent's own `_ready()`.

### `CockpitBase`

Root script for any cockpit interior.

**To create a new cockpit:**
1. Create a scene whose root node has a script extending `CockpitBase`.
2. Add a `Marker3D` named `CameraMount` — place `PlayerCamera3D` (+ `MouseLookController`) as its child.
3. Add a `Marker3D` named `PanoramicDisplayMount` — place the `PanoramicScreen` scene as its child.
4. Implement `get_camera_mount()` and `get_display_mount()` using `get_node()`.

```gdscript
class_name MyCockpit extends CockpitBase

func get_camera_mount() -> Marker3D:
    return get_node("CameraMount") as Marker3D

func get_display_mount() -> Marker3D:
    return get_node("PanoramicDisplayMount") as Marker3D
```

---

## Component Auto-Discovery

Components (`SensorHead`, `PanoramicScreen`) find each other at `_ready()` by walking the scene
tree — no manual export wiring needed.

```
SensorHead._ready()
  → VehicleBase.find_vehicle(self)   walk up tree to nearest VehicleBase
  → vehicle.get_cockpit()            first CockpitBase child of CockpitMount
  → cockpit.get_player_camera()      first Camera3D child of CameraMount
  → cockpit.get_panoramic_screen()   first PanoramicScreen child of PanoramicDisplayMount

PanoramicScreen._ready()
  → VehicleBase.find_vehicle(self)   walk up tree to nearest VehicleBase
  → vehicle.get_sensor_head()        first SensorHead child of SensorHeadMount
```

Both components keep their dependencies as `@export` so they can be set manually for
standalone testing (e.g. a test scene without a full vehicle hierarchy).

---

## Scene Hierarchy: Assembly Point

**The vehicle scene is the assembly point.** The stage scene (`low_earth_orbit.tscn`) only
knows about the top-level vehicle scene — it has no knowledge of cockpit internals.

```
low_earth_orbit.tscn
  └── MobileSuitRX0  (mobile_suit_rx_0.tscn)   ← drop in and done
        ├── SensorHeadMount/SensorHead
        └── CockpitMount/CockpitRX0  (cockpit_rx_0.tscn)
              ├── PanoramicDisplayMount/PanoramicScreen
              └── CameraMount/PlayerCamera3D/MouseLookController
```

The vehicle scene assembles the cockpit, sensor, camera, and input controller. The stage just
places the vehicle.

---

## Render Layers (`Core/AutoLoad/layers.gd`)

| Constant | Bit | Camera masks that include it |
|----------|-----|------------------------------|
| `WORLD` | 1 | First-person, third-person, sensor |
| `VEHICLE_EXT` | 2 | Third-person, sensor |
| `VEHICLE_FP` | 4 | First-person only |
| `COCKPIT` | 8 | First-person only — **excluded from sensor** |
| `PILOT` | 16 | First-person only |
| `FX` | 32 | All cameras |
| `HUD_3D` | 64 | First-person only |
| `SENSOR_BODY_PARTS` | 128 | Sensor only (opt-in via `set_group_visible()`) |
| `SENSOR_WEAPONS` | 256 | Sensor only (opt-in) |
| `SENSOR_SHIELDS` | 512 | Sensor only (opt-in) |

`COCKPIT` is excluded from `MASK_SENSOR` so the panoramic screen never appears recursively
inside its own sensor feed.

---

## Adding a New Vehicle / Cockpit

### New cockpit for an existing vehicle type

1. Create `Entities/Vehicles/Cockpits/CockpitXXX/cockpit_xxx.gd` extending `CockpitBase`.
2. Build `cockpit_xxx.tscn` with `CameraMount` and `PanoramicDisplayMount` markers and their children.
3. In the vehicle scene, replace the cockpit instance under `CockpitMount` with the new scene.
4. Nothing else — auto-discovery handles the rest.

### New vehicle type

1. Create `Entities/Vehicles/<Category>/<Name>/<name>.gd` extending `VehicleBase`.
2. Build the vehicle scene with `SensorHeadMount` and `CockpitMount` markers.
3. Implement `get_sensor_head_mount()` and `get_cockpit_mount()`.
4. Place the vehicle in any stage.

### Sharing the panoramic display on a new vehicle

The `PanoramicDisplay` components live in `Cockpits/Components/` — shared across all cockpit
types. Any cockpit that extends `CockpitBase` and has a `PanoramicDisplayMount` with a
`PanoramicScreen` child automatically works with `SensorHead`.

---

## Key Technical Documents

| Document | Contents |
|----------|---------|
| `Docs/PanoramicCockpit/summary.md` | System overview, scene tree, data flow, performance |
| `Docs/PanoramicCockpit/sensor_head.md` | FOV algorithm, SubViewport trick, dynamic viewport sizing |
| `Docs/PanoramicCockpit/panoramic_screen.md` | UV2 encoding, mesh generation, segment mask API |
| `Docs/PanoramicCockpit/panoramic_screen_shader.md` | Shader walkthrough, coordinate systems, artefact guide |
| `Docs/PanoramicCockpit/hud.md` | HUD canvas mapping, writing widgets, hatch aperture timeline |
| `Docs/FlightControl/summary.md` | Input → FBW → allocator → thruster pipeline, swapping stages, controls, HOTAS |
| `Docs/FlightControl/thrust_sizing.md` | Thruster ratings vs Raptor, nozzle size vs chamber pressure, jet power and Isp, the ×1.5 thrust change |
| `Docs/MobileSuit/prototype.md` | Prototype suit scene tree, rig, render layers, regenerating models |
| `Docs/MobileSuit/linear_seat_v2_cockpit.md` | RX-93 linear seat v2 cockpit and its rail grip variant, seated pilot (IK, G lean), sensor outlines |
| `Docs/Weapons/summary.md` | Fire control, envelopes and aiming, projectiles, beam look, controls, test tools |
| `Docs/Audio/summary.md` | External bus, shot fire sounds, the SFX lab and its recipes |
| `Docs/Audio/todo.md` | Sounds still to make; parked enemy / pass-by / cockpit-warning work |
| `Docs/Performance/frame_budget.md` | Frame time by phase, subtree and GPU pass (dated snapshot), measuring pitfalls |
