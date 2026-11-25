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

## B. Beam holes: rendering bugs

- [ ] **The glow and melt texture swims when the camera moves.** It changes with the view a lot.
  To find: the bore and floor are ray-traced inside the shader (virtual surfaces), and the
  melt bump and noise are sampled at those virtual hit points; derivative bump mapping
  (`dFdx`/`dFdy`) on such points is view-dependent. Sample the texture in hole space at stable
  coordinates and take the bump from the texture's own gradient, not screen derivatives.
- [ ] **Holes move back and forth when the suit moves or turns.** To find: the hole records'
  part frame (`part_to_model`) is uploaded in `HoleSet._process`; if the suit's transform is
  physics-interpolated or set after that, the holes lag a frame behind the mesh. Upload after the
  final transform, or compute the frame in the shader from the skinned vertex / bone.
- [ ] **A one-sided melt texture floats where the hole isn't round.** Panel openings, cuts and
  holes through thin or slanted shells are not cylinders, but the lip and heat zone are drawn
  around the analytic cylinder, so a molten ring appears on surface that isn't next to any real
  opening. The zone must follow the real opening (only where the surface is within reach of
  the bore wall, both faces), or be dropped for non-cylindrical openings.
- [ ] **The body looks hollow after hits.** A shot into the body leaves big see-through hollow
  areas. *Cause:* render meshes are thin shells; the bore walls are drawn only within each hole
  record, so wide holes and torn panels show straight into an empty shell. Needs an inside: a
  dark interior fill (back faces drawn as internals: frame, piping, a darkened volume) and/or
  real inner-frame meshes under the armour (already listed as "inner frame under intact
  armour").

## C. Power and hydraulics: the suit is a system, not a sack of tanks

- [ ] **Generators.** Two big Minovsky reactors in the abdomen below the cockpit (separate, but
  either one going up sets off a big explosion), plus a separate, smaller, tougher one in the
  backpack. Today: one reactor in the pelvis, r 0.85 m. Update the layout, the mass model and
  `_breach_reactor` (which reactor, how big a blast, chain to the other).
- [ ] **Half the suit blown off and it still works.** Power and hydraulics (the Minovsky lines
  from the reactors) must be a network: each limb, thruster group, sensor and display is fed
  through lines that run through the parts. Lines cut, so whatever is downstream loses power or
  pressure (limbs go limp, thrusters die, screens and sensors drop). A reactor lost leaves the
  rest on the other one, at reduced power.
- [ ] **Far more fire and explosions.** Most of a suit is hydraulics and electronics, not
  tanks: hits there should catch fire, arc and explode (sized by what is there), not only the
  tank cells. Ties into the network above (a ruptured line feeds a fire for a while).

## D. Equipment: weapons and the shield

- [ ] **Weapons have no hitbox and no destruction mesh.** The rifle, bazooka and funnels must be
  hit by beams and fragments (their own hull boxes), be holed like any part (hole records on
  their meshes) and break apart.
- [ ] **Stored energy and ammunition blow up big.** The hyper bazooka and its rounds, the rifle's
  E-pac, spare E-pacs: hit, they go off as real explosions (bazooka: its warheads), damaging
  whatever is near, not a small burst.
- [ ] **The I-field covers the front only.** A shot into the shield from behind bypasses the field
  and destroys the shield.
- [ ] **An I-field block doesn't melt.** It leaves black soot on the hit point and a lot of
  smoke, no molten lip.

## E. Smoke and fire

- [ ] **Real smoke, not steam.** Thick smoke that can block vision (and the sensors' view),
  lasting, drifting, lit by fires; fire on parts that were shot (burning lines and electronics)
  until it burns out.
- [ ] **A fresh cut face blows out white** for over a second (the cut cap's 1800 K glow, seen
  in the snap render): far too bright; tone it down with the other glows.
- [ ] **Remove the beam hit scatter effect and the glow after a hit.** It looks low-res. *Cause:*
  `ProjectileManager.impact` (flashes + sparks) on non-drilling contacts and the contact flash
  on drilling ones; the hole's own glow and DamageFx carry the hit.

## F. Explosion and beam scale

- [ ] **The reactor explosion grows with the zoom-out / FOV.** *Cause:* the flash sprite has a
  minimum angular size (`flash.gdshader`: `size = max(min(flash_size, max_angle·dist),
  min_angle·dist)`), so far away it stops shrinking. Big explosions need world size only.
- [x] **Beams bigger?** Decided: the beam's size is right; the **holes** must be bigger
  (rifle hole radius today 0.6 m), most of all through the cockpit (G).

## G. Cockpit: being hit and dying

- [x] **On destruction, go to the third-person view.** The cockpit stays after the suit is gone;
  zoom out to third person when the suit is destroyed (and when the pilot dies).
- [ ] **A hit to the cockpit breaks its gimbal.** The cockpit stops turning on its own and stays
  stuck to the suit's attitude.
- [ ] **Holes much bigger.** Beam holes through the cockpit are far too small, and holes
  everywhere should be bigger (the beam's size stays).
- [ ] **Every pierced screen breaks.** One shot kills several screens but only one shows cracks;
  every composite screen a beam passes through cracks (each crossing is a break).
- [ ] **Make a cockpit hit terrifying** even when the pilot lives. Sequence: the beam right in
  front of you, very bright and close; the screen dies (almost all of it); explosion, fire and
  smoke in the cabin. Then through the hole you see the inside of the suit (needs B: the body
  isn't hollow).

## H. Panoramic screen feeds

- [ ] **The camera-lost effect is bad.** Remove the block static and edge; a dead area is just
  black.
- [ ] **Losing a sub camera must not black out its sector.** The picture comes from the head's
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

## J. Drones (target drones, hunters)

- [ ] **A beam through a drone barely hurts it.** Most rifle hits on hunters (and likely the
  other drones) leave them flying and shooting. *Cause* (`target_drone.gd beam_contact`): a beam
  that goes through without touching the core or the gun only takes ~40% of its section
  (`_left`) and loses control with `control_chance`; nothing else happens. A rifle beam is far
  too strong for that: **any beam through a drone disables it** (power and control lines cut:
  it goes dead, drifts and tumbles, sparking and smoking, no thrust, no gun); **only a hit through
  the core explodes it**. A grazing hit that doesn't go through still costs it systems by where
  it hit (gun, sensors, thrusters).

## I. Notes

- Probes: `penetration_probe.gd` keeps passing; each visual fix gets a `damage_snapshot.gd` case
  (render and look at it before calling it done).
- Cost: profile with `Tools/Profiling/combat_bench.gd` after A (debris collision) and E (smoke).
