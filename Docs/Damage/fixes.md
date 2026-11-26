# Damage: fix and improvement list (play-test, 2026-11-27)

What the user found playing with the first damage pass (`summary.md`, "As built"), grouped by
the system each touches. Each item: what is wrong or wanted, then a **cause** where it is already
known from the code, or what to find out. `todo.md` keeps the original phase plan. Check boxes
when done.

Suggested order: **A** (nothing may be left floating), **B** (the holes themselves), **G**
(cockpit death), **J** (drones must go down), then **C/D** (systems and explosions), **E**, **F**, **H**.

---

## A. Destruction must be complete: nothing left floating, pieces are real

- [x] **Chunks and parts that come off have no collision.** They pass through the suit, the
  station, each other. *Cause:* `_make_debris` creates the RigidBody3D with
  `collision_layer = 0`, `collision_mask = 0`. Give debris a convex shape from its baked mesh
  (or the part's hull) on a debris layer that hits the world, other debris and suits.
- [x] **Things left floating after the suit is blown apart** (reactor breach): the cockpit, inner
  frame stubs, the rifle manipulator arms. *Cause:* `_blow_apart` bakes the parts and equipment,
  but nodes that are not parts (cockpit scene, `Stump` frames, the rifle stow arms, anything
  else under the suit) are neither baked nor hidden. Walk the whole vehicle: bake or hide
  everything visible.
- [x] **Cut-off pieces still ride the body.** Inner frames, cockpit parts, the screens, the
  V-fin and others float in place and move with the suit after their part is cut away. *Cause:*
  only the part's own mesh (and `Thrusters/` / `Cameras/` attachments) is hidden and baked;
  other meshes or nodes on that bone (V-fin, accessories, bone-attached props) are not. Collect
  everything that follows a severed bone (meshes skinned mostly to it, BoneAttachment3D
  children) and move it with the debris.
- [x] **Half-cut parts look solid.** A part cut most of the way through but not severed should
  not look whole: it should snap off at the cut, or hang by what is left (bent, sagging, a limp
  joint) and break off under load or the next hit.

- [x] **Parts cut nearly off stay hanging.** Not everything torn comes off clean:
  a limb cut through all but a strut or the cables dangles from the suit (an arm hanging, a
  shield still on what is left of the forearm), swinging with the suit's motion, until the
  next hit or a hard manoeuvre tears it away. Needs a physics joint between the debris body and
  the suit (a hinge or cone at the cut, breakable) and the debris kept drawn at the cut.
  *Done (2026-11-27):* a limb shot off (not torn off under load, not in a breach) stays
  hanging with a chance of 50% (less with less section left): a swinging joint at the cut or
  socket (cone 75°, twist 40°) and a few cables drawn from the stump. It tears loose when the
  load on it passes 20 m/s² (a hard boost), when what it hangs from comes off, or in a breach;
  equipment on it (the shield on a forearm) hangs with it.

- [x] **The shield stayed on and working after its arm was shot off** (play-test). It hangs
  from its own mount bone (`shield_mount.L`, under the forearm), not a damage part, so "what
  was on the severed parts" never matched it. Equipment now goes with the piece whose part it
  hangs from up the bone chain; on a part cut through, by which side of the cut it is on. The
  V-fin is part of the head mesh and goes with the head (checked).

- [x] **Inner frame left standing where a part was gone** (play-test: red-tipped struts at the
  backpack and pelvis). Every part torn off left a frame stub (joint drum, struts, cables up
  to 1.4 radii long), even bolted-on armour (skirts, main pods, nozzles). Now only jointed
  limbs (head, arms, hands, legs, feet) leave one, and it is short, in the socket.
  A later hit through the socket (beam or torn panel passing within ~0.8 m of it) knocks the
  stub loose: it flies off as debris, nothing left to hold it.

- [x] **The rifle's stow manipulator stayed after its skirt was shot off** (play-test). It is
  built on its own attachment on the skirt's bone, not part of the skirt's mesh; now it goes
  with the skirt's piece (its meshes copied onto it) and is hidden on the suit until repair.
  What it held can't be stowed any more (`MsLoadout.stow_lost`): a drawn rifle stays in the
  hand, still usable; repair gives the stow back.

## B. Beam holes: rendering bugs

- [x] **The glow and melt texture swims when the camera moves.** It changes with the view a lot.
  To find: the bore and floor are ray-traced inside the shader (virtual surfaces), and the
  melt bump and noise are sampled at those virtual hit points; derivative bump mapping
  (`dFdx`/`dFdy`) on such points is view-dependent. Sample the texture in hole space at stable
  coordinates and take the bump from the texture's own gradient, not screen derivatives.
- [x] **Holes move back and forth when the suit moves or turns.** To find: the hole records'
  part frame (`part_to_model`) is uploaded in `HoleSet._process`; if the suit's transform is
  physics-interpolated or set after that, the holes lag a frame behind the mesh. Upload after the
  final transform, or compute the frame in the shader from the skinned vertex / bone.
- [x] **A one-sided melt texture floats where the hole isn't round.** Panel openings, cuts and
  holes through thin or slanted shells are not cylinders, but the lip and heat zone are drawn
  around the analytic cylinder, so a molten ring appears on surface that isn't next to any real
  opening. The zone must follow the real opening (only where the surface is within reach of
  the bore wall, both faces), or be dropped for non-cylindrical openings.
- [x] **The body looks hollow after hits.** A shot into the body leaves big see-through hollow
  areas. *Cause:* render meshes are thin shells; the bore walls are drawn only within each hole
  record, so wide holes and torn panels show straight into an empty shell. Needs an inside: a
  dark interior fill (back faces drawn as internals: frame, piping, a darkened volume) and/or
  real inner-frame meshes under the armour (already listed as "inner frame under intact
  armour").

*Done (2026-11-27):* the damage code read bone poses before the skeleton modifiers (AMBAC,
limb reaction, aim): up to 2.4 m off what is drawn, so holes slid as the limbs swung; now
`FinalPoses` caches the pose after them and the hole frames upload on `skeleton_updated`. The
melt bump took screen derivatives inside branches (undefined where neighbouring pixels
branch differently: the dashed line round every hole and the floating ring): they are taken
once, before any branch or discard. Inside a hole the texture is triplanar in the hole's own
frame (no polar pinwheel, nothing moves with the view); the rim is textured over the part.
Back faces (the inside, only seen through openings) draw as dark metal and frame, not paint.
Still to do: real inner-frame meshes under the armour.

- [x] **Two shots into the same spot look see-through.** The shader took the first hole a
  pixel falls in and drew its wall or floor alone, so overlapping holes cut false gaps (or drew
  a wall where the other hole had removed the metal). The view ray now goes through the union
  of every hole it is in, to the first wall or floor still standing.

- [x] **The cut face of a stump still "moved" with the view** (play-test, the right forearm cut
  off). The re-solidified metal (bores, cut faces, lips) was nearly mirror-smooth and very
  metallic: its bumps mirrored the planet and the sun in specks that slid as the camera moved.
  Now matte slag (roughness ~0.75, metallic 0.55).
- [x] **A bare shield stopped the beam** after melting a big crater: 450 kg/m², ×3.3 on a
  slant, took more than a whole rifle shot. Now 250 kg/m², a slant at most doubles it: the
  beam goes through and on into the suit.

- [x] **Cut faces glared white at some angles and floated outside the limb** (play-test). The
  face is drawn in front of the back face it is on, so its depth is negative, and the bore's
  depth dimming `exp(−depth/1.6)` brightened it instead (×10 looking down a long piece). And it
  was drawn on any back face behind the plane, including open shells beyond the limb: now only
  within the real cross-section (the convex outline of where the plane meets the part's skin
  triangles), so a cut thin plate gets a thin face, not a slab.
- [x] **Bores drawn in empty space behind thin armour.** A hole's bore was drawn to the depth
  of the part's convex hull, not its real skin: behind a thin plate it floated in the air. Each
  part keeps its skin's triangles (bone space); a new hole records where the skin really is
  along its line (nested shells counted), and the bore is drawn only in that metal. The same
  for every hole on a part: beam bores, torn panel openings, and the torn socket craters
  (on the suit and on the piece that flew off: on a thin skirt the socket's floor, 0.7 m deep,
  hung in the air as a slab with the older holes punched through it).
- [x] **A smooth grey half-disc in a crater on the front skirt** (play-test): the floating
  socket floor, fixed above (confirmed in play).

## C. Power and hydraulics: the suit is a system, not a sack of tanks

- [x] **Generators.** Two big Minovsky reactors in the abdomen below the cockpit (separate, but
  either one going up sets off a big explosion), plus a separate, smaller, tougher one in the
  backpack. Today: one reactor in the pelvis, r 0.85 m. Update the layout, the mass model and
  `_breach_reactor` (which reactor, how big a blast, chain to the other). *Done (2026-11-28):*
  `reactor L` / `reactor R` (0.6 m, either one hit takes the suit, the blast centred on it) and a
  `backpack reactor` (0.45 m, 20% of the power): a hit scrams it 70% of the time (thrust drops to
  80%), else it goes up (`_backpack_breach`: a 3 GJ blast in the back, which sets off an abdomen
  reactor 60% of the time when it reaches one).
- [x] **Half the suit blown off and it still works.** Power and hydraulics (the Minovsky lines
  from the reactors) must be a network: each limb, thruster group, sensor and display is fed
  through lines that run through the parts. Lines cut, so whatever is downstream loses power or
  pressure (limbs go limp, thrusters die, screens and sensors drop). A reactor lost leaves the
  rest on the other one, at reduced power. *Done:* the reactors feed the torso's bus; the
  lines run out along the skeleton. A part whose lines ruptured has them cut half the time
  (`lines_cut`): it and everything beyond it lose power and pressure (limp, thrusters and
  cameras dead, equipment off), unless a live reactor sits on the way (the backpack feeds its
  pods). Thrust follows the live reactors' share (`power_share`). Applied on the next tick
  after any change (`_apply_power`); the fuzz's `power` and `control` rules check it.
- [x] **Far more fire and explosions.** Most of a suit is hydraulics and electronics, not
  tanks: hits there should catch fire, arc and explode (sized by what is there), not only the
  tank cells. Ties into the network above (a ruptured line feeds a fire for a while). *Done:*
  every part shot through ruptures its lines (a burst with arcs, fire 60% of the time, smoke),
  stores blow up big, the backpack reactor can go up.

- [x] **Thrusters on a destroyed part keep working** (play-test: backpack and chest shot to
  pieces, their thrusters still fire and show plumes). *Cause:* a thruster dies only when a
  beam's drilled line reaches it or its part is severed; the chest, spine and pelvis never
  sever, and a part shot down to nothing doesn't take its thrusters with it. *Fix:* a part's
  thrusters (and their feed lines) fail with the section lost: derated as it goes, dead below
  ~30% left; torn panels and bursts near a nozzle hit it too. *Done (d6df243):* a part's
  thrusters die below 30% of its section left (`THRUSTER_LEFT`); the fuzz checks it.

## D. Equipment: weapons and the shield

- [x] **Weapons have no hitbox and no destruction mesh.** The rifle, bazooka and funnels must be
  hit by beams and fragments (their own hull boxes), be holed like any part (hole records on
  their meshes) and break apart. *Done (2026-11-28):* they were already hit through their
  meshes' boxes; now every mesh on the beam's line gets an open through-hole
  (`_hole_equipment`, with the drill-in and blow-out effects), and a weapon its own stores blow
  up leaves the hand in pieces (`_tear_apart`: each mesh thrown off, a one-mesh weapon whole).
- [x] **Stored energy and ammunition blow up big.** The hyper bazooka and its rounds, the rifle's
  E-pac, spare E-pacs: hit, they go off as real explosions (bazooka: its warheads), damaging
  whatever is near, not a small burst. *Done:* `_stores_blast` tears 2.2× a burst's reach
  (rifle E-pac ~4.4 m, a bazooka warhead ~3.6 m), kicks the suit, throws loose debris and flashes
  nearby suits; the bazooka's four warheads cook off one after another along it. The explosion's
  sparks stay spark-sized and cool (they used to bloom into glowing balls that hung around).
- [x] **The I-field covers the front only.** A shot into the shield from behind bypasses the field
  and destroys the shield. *Done:* the field only takes beams coming onto its face (the shield's
  −X, `MsShield.get_front`); from behind the beam drills the plate, sets off the field's E-pac
  charges (`shield_charges_burst`) and wrecks the shield (probe `shieldback`).
- [x] **An I-field block doesn't melt.** It leaves black soot on the hit point and a lot of
  smoke, no molten lip.
  *Done:* it used to leave a 2.2 m, 2 cm deep crater whose flat floor, ray-traced behind the
  curved face, swam with the view and kept the shield's outline; now a scorch-only record
  (soot, no crater) and thick smoke off the face.

- [x] **Insides look hollow** (play-test): every inside surface seen through an opening (back
  faces) is now drawn as rough torn, re-melted metal (bump-mapped slag, triplanar over the
  part), the same as the bores, instead of a smooth dark shell.
  Holes: a crater ends in a floor of the same rough metal; a beam that went **through** leaves an
  open hole (user, 2026-11-27: capping through holes looked wrong). With the parts closed shells,
  the bore is drawn solid from where the beam entered the skin to where it left it for good
  (machinery inside, never an empty skin) and is open past that.
- [x] **The body (chest, waist) is the most hollow:** shots into it often open onto an empty
  shell. The render meshes are thin skins with nothing behind; the dark interior shading helps
  but there is no inside. Needs inner frame and machinery meshes under the torso armour
  (frame, reactor housing, cockpit block, ducts), drawn only where the armour is opened (or
  always: they cost little). *Done (2026-11-28):* `INNER_FRAME`, built at load on the chest and
  pelvis bones: a spine and a shoulder beam, hydraulic ducts, the two reactor housings (the
  reactors sit in them now, lower in the pelvis), hip actuators. Always drawn, fitted under the
  armour (damage_snapshot `insides` paints them and looks from eight sides: no pixel may show),
  holed with the armour along a beam (`_hole_inner`). The cockpit's dark screen sphere is the
  block a chest opening shows.
- [x] **The cockpit's panoramic screen shows through a hole in the chest** before the cockpit
  is breached. *Cause:* the cockpit shell is on the cockpit-only render layer (not drawn by the
  outside camera), but the screen mesh is also on the outside layer (`VEHICLE_EXT | COCKPIT`):
  through any hole in the chest skin the outside view sees the screen floating inside, no shell
  around it. *Fix:* the screen only on the cockpit layer (the sensor view excludes it already),
  and the cockpit shell's outside drawn for the outside camera, so a chest hole shows the
  cockpit block, and only a breach shows the screen.
  *Done (2026-11-28):* the screen is on the cockpit layer only; outside cameras see a twin
  (same mesh and material, `outside_view` instance uniform): dark glass with the same holes and
  cracks, the picture only while the hatch is open. Once a beam has jammed the gimbal the
  interior is drawn for outside cameras too (it can't turn into the hull): through the breach
  you see the wrecked, burning cabin.

## E. Smoke and fire

- [x] **Real smoke, not steam.** Thick smoke that can block vision (and the sensors' view),
  lasting, drifting, lit by fires; fire on parts that were shot (burning lines and electronics)
  until it burns out. *Done (2026-11-28):* a part shot through (its Minovsky lines ruptured)
  catches fire 60% of the time (`DamageFx.burn`, 6–20 s): flames in the channel, a flickering
  orange light, and thick grey smoke pouring out of both ends (world layer, so it hides what is
  behind it from the sensors too; shaded, so the sun and the fire light it), left behind in
  world space as the suit moves. Repair puts every attached effect out.
- [x] **A fresh cut face blows out white** for over a second (the cut cap's 1800 K glow, seen
  in the snap render): far too bright; tone it down with the other glows. *Done:* the part
  broke there, so only patches glow (`cut_temperature`, where the beam melted through); the rest
  is warm torn metal; peak 1400 K instead of 1800.
- [x] **Remove the beam hit scatter effect and the glow after a hit.** It looks low-res. *Cause:*
  `ProjectileManager.impact` (flashes + sparks) on non-drilling contacts and the contact flash
  on drilling ones; the hole's own glow and DamageFx carry the hit. *Done:* no contact flash on
  drilling targets; a beam on something that doesn't drill gets one short flash
  (`beam_splash`), no afterglow, no sparks. (The white-out in the forearm render is the rifle's
  E-pac going off, not the hit.)

## F. Explosion and beam scale

- [x] **The reactor explosion grows with the zoom-out / FOV.** *Cause:* the flash sprite has a
  minimum angular size (`flash.gdshader`: `size = max(min(flash_size, max_angle·dist),
  min_angle·dist)`), so far away it stops shrinking. Big explosions need world size only.
  *Done (2026-11-28):* it was the maximum: a flash is capped at 0.22 rad (a ball 0.9), so a
  260 m flash seen from the 500 m death view was drawn 110 m and grew as the camera pulled back.
  The reactor's flash and balls are `ProjectileManager.world_sized` (cap 1.25 rad): at the same
  instant the blast is 3× smaller from 3× as far (snapshot `breach`).
- [x] **The blast throws what is around it.** The reactor doesn't just vaporize the suit: its
  parts fly off (40–160 m/s, as before), and now debris already floating nearby (pieces shot
  off earlier, other suits' wreckage, `DEBRIS_GROUP`) is thrown outward too, as fast as the
  suit's own parts at that distance, spinning (a forearm shot off a second before: 0 → 58 m/s).
- [x] **Beams bigger?** Decided: the beam's size is right; the **holes** must be bigger
  (rifle hole radius today 0.6 m), most of all through the cockpit (G).

## G. Cockpit: being hit and dying

- [x] **On destruction, go to the third-person view.** The cockpit stays after the suit is gone;
  zoom out to third person when the suit is destroyed (and when the pilot dies).
- [x] **A hit to the cockpit breaks its gimbal.** The cockpit stops turning on its own and stays
  stuck to the suit's attitude. *Done:* `CockpitGimbal.jammed`: the capsule stays where it was in
  the suit, so its holes stay lined up with the chest's; repair frees it.
- [x] **Holes much bigger.** Beam holes through the cockpit are far too small, and holes
  everywhere should be bigger (the beam's size stays).
  **What this means (user, 2026-11-26):** the cockpit's holes look scripted: what the pilot
  sees from inside doesn't match what the beam did to the suit outside. The inside must be the
  same damage seen from the other side: the same beam line, the same width and melt as the
  chest's hole, its glow and cooling in step, and where the beam burned away part of the
  cockpit (the shell, a screen block, the seat rail, the hatch), that part is gone or melted in
  the cockpit view too, not just a round hole punched in the screen. One damage record drives
  both views.
  *Done (2026-11-28):* the beam's hole is `HoleSet.BEAM_GROW` (1.3×) its radius everywhere. A
  cockpit hit sends the beam's line and hole radius (`cockpit_holed(origin, direction, radius)`):
  the screen opens where that cylinder crosses it (its own fragments' distance to the line, a
  shattered edge 1.15× wider, a thin hot lip cooling on the HoleSet's clock with the shared
  `hole_heat.gdshaderinc`, a charred band), the cockpit's meshes get through-holes along the same
  line (open, no bore), and small pieces inside the cylinder, or with their own shaders (the
  MFDs, rail lamps) crossed at their middle, burn away. The cockpit sphere is hit where the beam
  enters it, not at its middle (it came after the pilot before).
- [x] **Every pierced screen breaks.** One shot kills several screens but only one shows cracks;
  every composite screen a beam passes through cracks (each crossing is a break).
  *Done:* each crossing's opening is sampled on the CPU (`_opening_panels`): every sub-screen it
  touches dies and every composite it touches cracks from it.
- [x] **Make a cockpit hit terrifying** even when the pilot lives. Sequence: the beam right in
  front of you, very bright and close; the screen dies (almost all of it); explosion, fire and
  smoke in the cabin. Then through the hole you see the inside of the suit (needs B: the body
  isn't hollow).
  *Done:* `_cockpit_hit_fx`: a blinding flash where the beam passed closest and the cabin light
  flashing with it (`CockpitBeamGlow.hit_flash`), a small fireball, 85% of the sub-screens
  flickering out in random order over 0.5 s (`PanoramicScreen.blackout`; the rest flicker for a
  few seconds), sparks, the air blasting out of the holes as fog, then fire at the holes with a
  flickering orange cabin light and smoke drawn out through them for ~8 s (`DamageFx.cabin`,
  emitters riding the capsule, prewarmed). The flames are still simple puffs (E).

- [x] **After the pilot dies the suit spins up, faster and faster.** *Cause* (measured): the
  pilot's death switches the flight computer's stabilisation off (`_kill_pilot`:
  `fcs_enabled = false`), but the beam that killed the pilot usually also left a thruster valve
  stuck open (or a tank venting). Nothing counters it: one main stuck at 18% spins the suit up
  by ~24°/s every second (245°/s after 10 s) until the propellant runs out. With the
  stabilisation left on, the same suit holds at 0°/s and drifts at 1 m/s. *Fix:* the flight
  computer is automatic and outlives the pilot: on the pilot's death it switches to a hold
  mode (null rotation and drift, no new commands) and keeps running until its power, its
  thrusters or its propellant are gone; it only shuts down when the suit has no reactor left.
  *Done (2026-11-27):* the flight computer keeps holding the suit after the pilot dies
  (`FlightComputer.pilot_lost`: no input, stabilisation on), and the stuck-open valve is gone
  from the thruster damage altogether.

## H. Panoramic screen feeds

- [x] **The camera-lost effect is bad.** Remove the block static and edge; a dead area is just
  black. *Done:* directions no live camera covers are plain black.
- [x] **Losing a sub camera must not black out its sector.** The picture comes from the head's
  cameras (eyes; the back of the head for the rear); the sub cameras only make the suit's own
  body and equipment see-through. A sub camera lost means: whatever it saw past is no longer
  see-through, so **you see that part of your own suit** in the feed, from the head's viewpoint.
  - A weapon or shield camera lost: the weapon's outline goes, the real weapon is drawn.
  - A body camera lost: the parts it saw past are drawn.
  - Black only where nothing can supply a picture (the head's cameras gone and no camera covers
    that direction).

  **Decided (2026-11-27):**
  - **Any damage to the suit shows the whole body** in the feed (drawn from the head's
    viewpoint, real meshes with their holes): seeing your own body is how you assess the
    damage. Undamaged, the body stays see-through as today.
  - **Shield and fin funnels** stay see-through (they would block the view) until they
    themselves are damaged; then they are drawn.
  - **Head's cameras gone**: the view comes from the chest camera (the left chest sensor).
    That gone too: no full front view any more; only what the remaining sub cameras cover,
    black elsewhere.

  *Done (2026-11-28):* the first damage (`part_damaged`, `part_severed`, `component_destroyed`)
  puts every part's mesh and what rides it on `SENSOR_OPAQUE` (`DamageModel._on_damaged`), all
  but the head the camera sits in and the plumes; the shield and fin funnels only once they are
  hit (a part of theirs damaged, a broken item, the shield's camera lost). Without the main
  camera (shot or the head gone) the SensorHead takes the picture from the left chest camera's
  place (`SensorHead.move_to`); repair puts it all back.

## J. Drones (target drones, hunters)

- [x] **A beam through a drone barely hurts it.** Most rifle hits on hunters (and likely the
  other drones) leave them flying and shooting. *Cause* (`target_drone.gd beam_contact`): a beam
  that goes through without touching the core or the gun only takes ~40% of its section
  (`_left`) and loses control with `control_chance`; nothing else happens. A rifle beam is far
  too strong for that: **any beam through a drone disables it** (power and control lines cut:
  it goes dead, drifts and tumbles, sparking and smoking, no thrust, no gun); **only a hit through
  the core explodes it**. A grazing hit that doesn't go through still costs it systems by where
  it hit (gun, sensors, thrusters).

  *Done (2026-11-27):* the drone is a test target, and a disabled one was hard to tell from a
  live one: a beam through it (or stopping ≥ 1 m deep) **blows it up**; through the core
  (now r 4.5 m of the 7 m drone, was 1.6) it goes up in the core's flash; a shallow hit
  wrecks its thrusters (jink and dodge at half).

## I. Notes

- Probes: `penetration_probe.gd` keeps passing; each visual fix gets a `damage_snapshot.gd` case
  (render and look at it before calling it done).
- Cost: profile with `Tools/Profiling/combat_bench.gd` after A (debris collision) and E (smoke).

## K. Automatic checks (branch feat/damage-v2, 2026-11-27)

`Tools/Damage/damage_fuzz.gd` (headless) lands random damage (real rifle beams at random parts
from random directions, severs, joint hits) round after round and checks rules after each:

- **own**: nothing shows on a part that is gone or past a cut. Ownership is generic now: every
  bone attachment and non-part skinned mesh belongs to the part up its bone chain
  (`DamageModel._followers`), copied onto the flying piece and hidden on the suit; smoke and
  sparks anchored on a lost part go with it.
- **thrust**: a hit thruster is out (no derated or stuck-nozzle outcomes any more, user's call):
  `Thruster.shut_down()` cuts thrust and plume at once; a part under 30% of its section loses
  its thrusters.
- **control**: a severed part, or one with a joint shot anywhere between it and the torso, is
  limp (`DamageModel.limp`): its AMBAC joints out, its weapons `limp` (can't aim or fire), its
  equipment `disabled` (can't be used, raised or drawn).
- **equip**, **sane** (no NaN, no runaway spin) and **frame** (slowest frames, attributed to
  the damage entry points that ran in them).

Frame cost found and fixed this way: part meshes are rigid (one bone each), so skinning is one
transform and baked debris shares the suit's mesh; mesh arrays read once (a read waits for the
render thread); torn panels use skins split ahead of time (a little each frame after load);
plates built from arrays with box colliders; component lookups cached; particle emitters and
hole lights pooled (creating them flooded the render thread: 40–50 ms stalls); effects and the
hole material warmed up after load. Fuzz, 12 rounds: worst damage frame 54 → ~18 ms
(reactor breach), frames over 12 ms 94 → ~25, p99 19 → 12 ms (headless, editor build).

**Cut faces by stencil (step 3, 2026-11-27):** a cut no longer traces its face in the mesh's
shader (convex-outline guesses, negative-depth glare, slabs on thin parts). The cut part's back
faces seen through the cut write the stencil (a next pass, `cut_stencil.gdshaderinc`), and a grid
across the cut plane, lifted onto the same torn offset, draws the face only there
(`cut_cap.gdshaderinc`, read after the opaque pass): the real cross-section, concave or not.
Eight stencil values cycle so neighbouring cuts don't share marks. All variants are compiled and
drawn once (a box too small to see, in front of the camera) after load: drawing them first on a
real cut cost ~100 ms. Debris hulls come from cached vertices (asking a mesh for its hull reads
it back from the render thread, ~9 ms per piece) and are made after load too.
Where a part's mesh was open behind the cut (no back face along the line of sight) the face had
a gap: the suit's parts are closed shells now (below).
Windowed combat bench with hits (12 s): average 4.5 ms (was 5.4–6.5), worst 23–25 ms (was 62–73).

**Closed part shells (2026-11-27):** `build_mobile_suit_nu.py` closes every open boundary loop
of the suit's parts with a fan of faces in a dark interior material (`MS_Interior`), wound to face
out; the new faces sit inside joints and sockets. Left open on purpose: the nozzle bells, the two
hatch doors, the doorways they close (chest, rear skirt) and the chest's airlock tunnel to the
cockpit; one-sided panels (a single face's outline) too. Every part but the chest is now closed,
so a cut face (stencil cap) and every hole close on real metal. Weapons are unchanged.

**What sits on what (2026-11-27):** a thruster belongs to the most specific part on or under its
mount bone whose box holds it (the main thrusters hang from the backpack bone but sit in their
nozzles: losing a pod's nozzles now kills its mains and their plumes). Equipment can name the
part that carries it while stowed (`MsEquipment.damage_part`): the fin funnels' rack sits on the
left main pod and goes with it; the beam saber's on the right main pod. The fuzz checks that
no live thruster sits inside a severed part.


## L. Play-test (2026-11-28)

- [x] **The cockpit stays closed from outside.** A beam through the chest and cockpit was open
  from the seat, but outside the bore was drawn solid where it crossed the cockpit. *Fix:* a
  hole knows where its line crosses the capsule (`Hole.cavity`, `COCKPIT_CAVITY` 1.4 m): no metal
  there, a through hole is open across it.
- [x] **Torn panel openings looked into the empty shell** (hollow at some angles, burnt at
  others). The opening is now a crater with a floor of torn metal, not through.
- [x] **Damage showed through solid parts in front** (a cut joint seen through an intact skirt).
  *Cause:* a cut face drawn on a back face wrote a depth in front of it, ahead of what really
  covered it. It keeps the back face's depth now.
- [x] **No switch to the chest camera** when the head's cameras are gone: only what the body
  cameras cover, black elsewhere.
- [x] **No outlines over the drawn body.** Once the suit is damaged the arms' overlay is off
  (`SensorHead.body_shown`), and a drawn thing's outlines go with it (they had been put on the
  drawn layer with their meshes).
- [x] **Explosions keep their world size at any distance and zoom** (every ball and explosion
  flash: no angular cap; up close it fills the view).
- [x] **The backpack is only the stub between the pods.** In the source model, the bazooka's
  tail (magazine with its four rounds, tail cap, handle, trigger, top rail and the two blocks
  joining the rail to the magazine) had been counted as backpack, and was left 1 m off the
  bazooka when the bazooka was moved back for the widened pods: now part of the bazooka (gone
  with it, its rounds go off with it). The fin funnel connector and the beam saber connector are
  their own meshes (`PodMountL`/`R`, on the backpack bone so they don't swing) that go with
  their pods (`MESH_PARTS`; the fuzz's `own` rule checks them).
- [ ] **Two holes into one spot from different angles** (user unsure it looks wrong): a render
  of two bores through the chest side (snapshot `overlap_clean`) shows them joined into one
  rough opening, nothing odd seen yet. Needs a screenshot of the case if it still looks wrong.
- [x] **The pilot is seen through a breached cockpit's holes** (drawn for outside cameras once
  the gimbal is jammed, like the cockpit around them).
- [x] **Pieces knocked off showed as outlines on the screen** (the fin funnels). Debris copied
  the equipment's sensor outline meshes too; it takes hardware only now (`_debris_worthy`), and
  the fuzz's `own` rule fails on any sensor-only mesh on debris.
- [x] **The screen's tear was blocked by molten metal.** The tear is wider than the beam hole,
  so the cockpit shell right behind it showed its molten rim through it. The cockpit's meshes
  open 1.5× the hole now, wider than the tear's jagged edge.
