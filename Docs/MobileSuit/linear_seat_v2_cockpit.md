# RX-93 Cockpit (Linear Seat v2), Seated Pilot and Sensor Outlines

## Cockpit (`Cockpits/CockpitLinearSeatV2`)

The ν's cockpit: a contoured seat on the linear-seat boom, built by
`Tools/Blender/build_cockpit_linear_seat_v2.py` (after sketches of the seat, front and back, and
of the ball controller; the sketch's jump seat behind it is left out for now). It reuses the `CockpitLinearSeat` script
and every cockpit component; the model keeps the node names they look for.

```
CockpitLinearSeatV2 (CockpitLinearSeat script)
├── Model                    cockpit_linear_seat_v2.glb
│   ├── Shell, InnerDoorL/R, SeatBase, SeatBoom      fixed
│   ├── ArmrestL, GripL/BallL → HandL                fixed: left armrest
│   ├── BezelLeft, ScreenLeft, DisplayArmL           fixed: left monitor
│   └── SeatSwing            what turns for the hatch:
│       ├── Seat, SeatCollar, ArmrestR, Footrest, DisplayArmR
│       ├── GripR            ball controller unit (base, cradle, lever arm)
│       │   └── BallR        the ball (origin = its centre) → HandR
│       ├── PedalL / PedalR  (origin = heel hinge) → FootL / FootR
│       ├── BezelCentre/Right, ScreenCentre/Right
│       └── HatchPlate, HatchLock, HatchOverride       beside the cushion, right
├── PanoramicDisplayMount/PanoramicScreen, CameraMount/PlayerCamera3D, CockpitLight, PanoramicHud
├── ControlsAnimator         scheme = TWIN, pedal_travel_deg 26, pedal_stroke 0.075
├── Pilot (SeatedPilot)/AmateYuzuriha
├── CockpitGimbal, CockpitDisplays, CockpitClickMode
└── HatchCockpitParts        seat_turn_deg = −40, seat_riders = CameraMount, Pilot
```

- **A normal adult seat, set for the pilot.** The cushion is 0.50 m wide and 0.40 m deep, the back
  0.60 m to the shoulders, reclined 12°. The pilot model is small (about 1.40 m to the top of her
  hair, hip to eye 0.52 m, shoulder to wrist 0.37 m; an adult is 1.62–1.75 m and about 0.63 m), so
  she sits in it with room to spare. What is fitted to her is where the seat stands and how its
  adjustable parts are set: the cushion height puts her eye at the sphere's centre, the headrest
  rides low on its slide, the pedal carriages sit at the near end of their rail. Her joints are
  the `PILOT` constants at the top of the build script.
- **Shaped like a seat.** The cushion, back and headrest are curved shells
  (`Part.surface`): the back is hollowed across with a lumbar swell and shoulder wings, the cushion
  has raised sides and a waterfall front, the headrest wraps the head.
- **Pilot connectors** on the upper back (two plugs, two ports, the latch block), for a normal
  suit's backpack; harness reels and stowed yellow straps on the bolsters.
- **Armrests.** Just wide enough for the forearm, with the controller at the front. The side
  consoles (switch panel left, hatch lever right) are gone: they blocked the view down, and
  the flight-mode switches live on the sticks and keys.
- **Ball controllers.** The hand lies over the ball, fingers in the grooved slot round the front,
  thumb on the inner cheek with its three buttons. The ball stands on a base block whose lever
  arm runs back along the deck; the ball turns in the block's cradle.
- **The seat turns aside for the hatch,** as the first linear seat did: the seat, the pedals,
  the right armrest deck and the centre and right monitors turn 40° to the right, while the left
  deck (controller, switch panel) and the left monitor stay where they are, which leaves the
  pilot's way out clear. The swivel is at the seat's rear left, like a door's hinge, so the
  seat's left side hardly moves and clears the fixed deck; the main panel parts from the left
  one at a latch. Nodes outside the model that belong to the seat ride along
  (`HatchCockpitParts.seat_riders`): the pilot's eye and her body. Her left hand lets go of the
  left controller as the sequence starts and rests on her lap (`SeatedPilot.let_go`: any hand
  whose control is not under `SeatSwing`).
- **Hatch handles**, after a fighter's seat arming handles, as two handbrake-style levers lying
  fore and aft on the seat's right side beside the cushion (forward of the armrest's post, which
  now comes down at the rear). Their tops are warning tape (yellow, diagonal black and yellow
  bands down both edges) with the label in the middle, where the pilot sees them from the seat,
  so the state reads at a glance; the monitors' support arms run outboard of them. The override (HATCH OVERRIDE
  HANDLE), against the seat with its top level with the side rail, pivots at its rear and pulls
  up at its front. The lock, just outboard and a little higher, pivots at its front and pulls up
  at its tail; down it reads LOCK, up it bares a small UNLOCK on top of a block under it. The
  lock's grip has a tab over the override's front grip, so the override can't rise until the
  lock is up. Both up opens the hatch; the override pushed down closes it; the lock goes down
  only after the override. Click to pull (left) or push (right) (`HatchCockpitParts`:
  `HatchLock` / `HatchOverride`; the first linear seat keeps its guarded lever). From the eye
  their tops show past the right armrest.

### Controls animation (`CockpitControlsAnimator`, scheme TWIN)

The `PilotCommand` is un-mixed back into stick travel the way `TwinStickPilotInput` mixes it, so
the keyboard moves the controls too:

| Control | Shows |
|---------|-------|
| Both balls tipped fore / aft together | forward / back |
| Balls tipped fore / aft against each other | yaw: right ball forward = left |
| Both balls tipped sideways | strafe |
| Balls tipped sideways against each other | roll: right ball right = roll right |
| Both balls tipped tops back | pitch up (adds to the fore / aft tilt) |
| Right pedal / left pedal | up / down thrust: the pressed one tips 26° and slides 6 cm forward on its rail, the other stays put |

Only the balls move (`BallL/R`, turning in their cradles about their centres); the units and
their lever arms stay put on the decks.

## Rail grip variant (`Cockpits/CockpitLinearSeatV2Rail`)

The ν's cockpit now (`build_rx93_scene.gd` `COCKPIT_SCENE`; v2 stays as the ball controller
version). The same cockpit with the ball controllers swapped for crossbar grips on rails, after the
RX-0's: everything else (seat, pedals, monitors, hatch, pilot) is v2's. The model is the same
build script with `--controller rail`; the scene differs from v2's only in the model, the
animator wiring and the pilot's finger curl (62°, 70°, 40°, thumb 30°, to wrap the bar).

```
GripL / GripR            rail plate on the armrest deck, a slot down its middle, travel scale
├── RailLampsL / R       lamps either side of the slot, every 6 mm: one mesh per rail
└── SlideL / SlideR      carriage in the slot, base and the clevis of a fore-aft hinge:
    │                    slides fore / aft, ±6 cm
    └── RollL / RollR    hinge knuckle and the upright on its outboard side: rolls ±20°
        └── BarL / BarR  crossbar grip running in from the upright, button cap on its inner
            │            end (red trigger on top, two thumb buttons behind): twists ±28°
            └── HandL / HandR    wrist target: palm down over the bar, fingers round its front
```

The rails give the fore / aft motion a long stroke (12 cm end to end), where the balls only
tilt. Animation (`CockpitControlsAnimator`, scheme RAIL): each grip does what the matching VKB
stick does in `TwinStickPilotInput` (average = translate, difference = turn), so the pilot's
hands move as the player's do; the animator honours that input's invert flags.

| Grip motion | Stick axis | Together | Against each other |
|-------------|------------|----------|--------------------|
| Slide fore / aft | fore / aft | forward / back | yaw: right forward = left |
| Bar twist, knuckles up | twist, clockwise | (none: up / down is on the pedals) | pitch: right up, left down = nose up |
| Roll, top right | left / right, right | strafe | roll: right right, left left = roll right |

On the sticks up / down is the twist's average (no pedals there); in the cockpit it is on the
pedals, linked like a fighter's rudder pedals: up slides the right pedal forward on its rail and
the left back by as much (3 cm at full demand), down the other way, the whole foot riding them.
Braking tips both pedals toes forward together about their heel hinges, by 70% of 16° for a
brake and all of it for a hard brake.

The lamps (red, bright enough to glow) are lit from the rail's rear end up to the
carriage, so each rail shows how far its grip is pushed; ahead of it they are black. Each rail's
lamps are one mesh drawn with `rail_lamp.gdshader`, no shadow: the animator sets its instance
uniform `lit_from` to the carriage's z. (As 64 separate lamps they cost 0.57 ms a frame in
draw submission; as two meshes, 0.08 ms, within noise.)

The wrist rides on the bar, so all three motions carry the hand with them. The cockpit
snapshot tool's `rail` shot renders each motion, and its third argument puts this cockpit in
the ν in place of v2:
`... -s Tools/Godot/cockpit_snapshot.gd -- <out> rail res://Entities/Vehicles/Cockpits/CockpitLinearSeatV2Rail/cockpit_linear_seat_v2_rail.tscn`

## Seated pilot (`Cockpits/Components/SeatedPilot`)

`SeatedPilot` (the `Pilot` node, which is the seat frame) seats the character scene under it and
adds a `SeatedPilotPose` modifier to its skeleton. Every frame, from the rest pose:

1. the spine leans with `SeatedPilot.lean` and turns with the look (below), the head takes
   the rest of the look;
2. two-bone IK puts the ankles on `FootL/R` and the wrists on `HandL/R`, markers in the cockpit
   model that are children of the pedals and grips, so the limbs follow the animated controls;
3. feet and hands are turned onto the markers' frames, and the fingers curl round the ball.

Everything is solved in skeleton space from rest directions, so bone axes don't matter. The
Amate model's quirks are the script's defaults: its arm and leg bones are named one joint off,
it has no hand bone (the five finger roots turn together), and its skeleton is Z-up.

- **Looking round** (`PilotCamera`, `lean_enabled`): the eye rides on a body instead of turning
  on the spot. The head turns on the neck (the eye is 9 cm ahead of and 10 cm above the pivot;
  in pitch the eyes turn alone for the first 25° and the head tips by 60% of the rest, so the
  eye doesn't dip into the chest);
  the torso takes 30% of the yaw as a twist (up to 45°); from 40° to 125° to the side the pilot
  leans up to 30° that way (and 6° forward), enough to look past the headrest and over the seat
  back; looking down past 45° she leans forward, up to 18° at the 75° limit, so the eye comes out over
  her lap and sees the pedals and controls instead of clipping into her chest (starting the lean
  earlier was disorienting, a smaller lean let the eye clip). `PilotCamera.torso` is that turn; the pose applies
  it along the spine and gives the head what is left of the look, so the body matches the view
  and the hidden head never leaves a neck stump in front of the eye. The look is limited to
  ±150° of yaw and ±75° of pitch (`MouseLookController.yaw_limit`, `pitch_limit`).
- **G lean:** the suit's acceleration in the seat frame pushes the body the other way, through
  `max_lean_deg · tanh(g / g_reference)` (5° and 4 g) and a critically damped spring, so even the
  suit's big G only tips her a few degrees; leaning back into the seat takes `backward_share`. The eye leans with her
  (`PilotCamera.body_sway`), so her body never passes through it.
- **Layers:** the body is on `PILOT` (the pilot's eye sees her arms and legs); the head meshes
  are hidden from the eye and, like the cockpit, everything shows to outside cameras only while
  the hatch is unsealed. The beanie is hidden in the seat (it would sit in the headrest).
- **Boot weights:** the model's boots carried weight on the root bone `hips_01`, so seated, the
  soles stayed behind and the boots stretched. `Tools/Blender/fix_character_weights.py` moved
  that weight onto each vertex's strongest other bone, in place in the GLB.

## Sensor outlines (`PanoramicDisplay/sensor_outline.gd`)

The sensor never draws the suit, so its equipment is shown on the screen as outlines. A
`SensorOutline` under an equipment scene draws the real meshes into the sensor image, rim only:

1. the body, fully transparent, writes a stencil value;
2. the same mesh pushed out along its normals by a few pixels (in clip space, so the width is
   constant on screen) is drawn where that value isn't: a dark halo, then the rim.

The outline is the model's true silhouette from the sensor head at any angle and distance, and it
moves with the image because it is part of it. Units are drawn one after another, each with its
own stencil value, so overlapping units keep whole outlines: the fin funnels use `per_mesh` (six
outlines), the shield one. The shell mesh is the source mesh with normals averaged per position,
which keeps hard edges closed when pushed out. Cost: three small draw calls per unit in the
sensor viewport. Outline meshes sit on `SENSOR_WEAPONS` / `SENSOR_SHIELDS`, which only the sensor
camera draws.

`HudSilhouette` still places the label (`draw_outline = false`); other suits' shields keep its
drawn outline.

## Checking changes

`Tools/Godot/cockpit_snapshot.gd` renders the cockpit, pilot, outlines and the suit from fixed
views with scripted input and saves PNGs (see its header).
