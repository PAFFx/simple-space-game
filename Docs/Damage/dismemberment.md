# Parts blown off: what games do, and the plan here

A beam through a part is followed by a burst (a propellant cell, electronics, an E-pac,
`physics.md` §5–6) that tears pieces off. Limbs come off at joints or where a hole leaves too
little holding them on. All of it is dynamic: wherever the hit lands. Two problems:

1. **There is nothing inside.** The model is armour shells. Whatever comes off leaves a view into
   an empty shell, and the piece that flies off is a paper-thin surface.
2. **Nothing may look disconnected.** A hole that nearly cuts a part, or a burst that takes the
   panels around an antenna, must not leave a piece floating on a sliver.

## The model we have (measured)

`count_islands` (headless, the ν GLB; pieces = position-welded connected parts of each mesh):
**35 meshes, ~7,000 vertices in all, 133 loose pieces.** Chest 22 pieces (929 vertices), backpack
19, head 12, pelvis 7, hands and feet 5, shoulders 4, thighs, forearms, pods 3, upper arms and
shins 2, skirts, spine and nozzles 1.

- The parts are **already separate meshes at the joints** (head, chest, spine, pelvis, upper arm,
  forearm, hand, thigh, shin, foot, skirts, pods, nozzles): severing at a joint needs no cutting.
- The big shells (forearm, thigh, shin) are **one or two welded pieces**: no ready-made panels;
  they have to be broken up at runtime.
- The model is **very low-poly** (a forearm is 134 vertices). Cutting, baking a pose and
  re-meshing a part on the CPU at the moment of a hit costs next to nothing.

## What games do

| Approach | Who | How | For us |
|---|---|---|---|
| Pre-cut points with caps | Fallout 3 / NV / 4, Dead Space | the model is split at fixed points when authored; each cut has a stump cap mesh, hidden until used | joints only; our parts are already split there |
| Location removal + damaged look | MechWarrior 5, BattleTech; War Thunder (turret, barrel, tracks are separate meshes; wrecks get a burnt material) | a destroyed location is removed; what's left swaps to a damaged mesh or material | the same as our joint severing; our systems side already goes further |
| Real-time plane slicing | Metal Gear Rising (blade mode) | the mesh is cut along any plane at runtime; the cut faces get generated caps with an interior texture | our mid-part cuts; the cap drawn by the shader instead, since our meshes aren't closed |
| Pre-fractured chunks in a bond graph | NVIDIA Blast / APEX, Unreal Chaos (Geometry Collections), Red Faction Guerrilla | broken into chunks offline; chunks bonded in a graph with strengths; damage breaks bonds; groups no longer connected to the anchor fall off | **the bond graph**, with chunks from the model's own pieces and from runtime fracture instead of offline |
| Node-beam soft body | BeamNG.drive | the vehicle is nodes and beams that bend and break; the mesh is skinned to the nodes; parts drop when their beams break | too costly for combat suits; we borrow its rule: **a part comes off when its load path is cut** |
| Voxels / blocks | Teardown, Space Engineers, From the Depths | holes are removed voxels; unsupported groups fall | no: a different art pipeline |
| Fake interiors | interior mapping (Marvel's Spider-Man windows); Sniper Elite's x-ray (real internal meshes shown only in the kill cam) | a shader draws depth that isn't there; or a few internal meshes shown when needed | the hole bore (`beam_effects.md`); **one generic inner frame** instead of every machine |
| Hide it with FX | nearly everyone | fire, smoke, sparks cover the seams for the first second | sparks, flash and vapour only (vacuum): after a second everything is visible, so it has to look right on its own |

Everyone who does this convincingly does two things: something **is** inside (a cap, a frame,
organs), and things come off **along real seams** (joints, panels, chunk boundaries), never as a
surface floating in space.

## The plan: six layers

### 1. An inner frame: the interior we do model

UC suits have a movable frame under the armour. Generate one, procedurally, per bone: a strut along
each bone, a joint housing at each pivot (a drum for hinges, a ball for the shoulder and hip),
one or two actuators spanning each joint, cable bundles along the struts. A kit of primitives
(like `Tools/Blender/mesh_kit.py`), sized to ~40–60% of each part hull's cross-section, dark
metal, a few thousand vertices for the whole suit. Skinned to the same skeleton, always there
(inside the shell it's hidden anyway; through seams it shows a little, as on a real kit).

It is what you see through a hole, behind a blown-off panel, at a stump and in a cut, lit by the
hole's glow. It also gives the cut-face shader something to draw on where the shell is open
(layer 5). The reactor block and the cockpit capsule sit in it as simple shapes.

### 2. Loose pieces come off whole

The model's 133 pieces (antennae, vulcan pods, vents, cover plates: to be identified with the
x-ray snapshot) are natural chunks. Each is a node in the bond graph, bonded to its part with a
strength [tune]. A burst within reach breaks its bond and it flies off whole: no cutting.

The mesh stays one draw call: each vertex carries its piece id (a vertex attribute written by the
scene generator); a "removed pieces" bitmask uniform collapses those vertices in the vertex
shader, and a baked copy of the piece (current pose, a few dozen vertices) flies as a rigid body.

### 3. Shell fracture for the big shells

Where a burst tears a part that has no loose pieces there (forearm, thigh, shin, the chest's
large plates):

1. **Size**: blow-off radius from the burst energy, `R ≈ k · E^(1/3)` [tune] (cube-root, as crater
   sizes scale): a 0.4 GJ tank cell ~2 m, a 1–10 MJ electronics burst ~0.3–0.6 m (one panel popped).
2. **Bake** the part's current pose on the CPU (skin its few hundred vertices with the bone
   poses), take the triangles within `R` of the burst, **tessellate** them to ~0.3 m edges.
3. **Seeds**: 2–5 random points on the shell within `R`. Each small triangle goes to its nearest
   seed by centroid. Because the triangles are small, the pieces' outlines come out **jagged**,
   like torn plate, with no clipping maths.
4. **Thickness**: each piece is extruded inward by the armour thickness [tune: 0.1–0.2 m] with side
   walls along its outline, edge material torn and hot: a plate, not a sheet.
5. **The gap**: on the part, a breach record (centre, radius, seeds; same budget as holes) makes
   the shader discard the same region (nearest seed within `R`), with a torn, scorched edge band
   around it. Through the gap: the inner frame.
6. **Flight**: each piece a `RigidBody3D` (convex hull of its vertices), mass from its area ×
   the armour's areal density [tune], velocity = the part's velocity at that point + the burst's
   push (outward from the burst, falling with distance), spin from the off-centre push. Hole
   records it overlapped go with it (converted to its space), so a flying panel still glows and
   cools.

The layout follows: the armour over that region is gone, so the next beam or fragment finds the
components under it unprotected.

### 4. Severing at joints

A destroyed joint or a broken structure link (`summary.md`) takes the part and everything beyond:

- **The limb**: its meshes (and its frame) baked in the current pose into static meshes, the
  originals hidden, one rigid body with the mass model's mass and inertia, leaving with the
  momentum it had (`v + ω × r`) plus the separating push.
- **The stump**: the parent keeps the frame's joint housing (now visible), **3–6 torn cables**
  hanging from it (short verlet ropes) with sparking ends for 5–20 s, and a torn edge band on
  the parent's armour around the opening, so the factory seam doesn't read as clean.
- In vacuum there's no gravity on the cables: they stream away from the suit's thrust, like the
  droplets, on their own.

### 5. Cuts through a part

When a part breaks somewhere other than a joint (layer 6 decides where):

- A **cut surface** through the hole, across the part, displaced by noise so it is never flat.
  The attached part draws only its side, the detached copy only the other (both from the same
  record). The frame's strut is cut by the same surface.
- The **cut face** is drawn by the shader: where the view ray passes through the opening, it is
  marched a few steps against the noisy surface, and the hit is shaded as cut metal and written to
  `DEPTH`. Near the beam's hole it's melted and dripping (the hole's own temperature), farther
  out torn, with frozen melt runs. It cools to dark, uneven metal: not flat, not a coloured cap.
- Geometry slicing (Metal Gear Rising style) is the alternative for the detached piece, since it's
  baked and static, but generated caps need closed meshes and ours aren't (the volume
  measurement leaked through seams). The shader cap doesn't care.

### 6. The structural check: nothing floats

After every hole, breach or loss, each part is checked so that whatever looks disconnected
**is** disconnected:

- **Long parts** (upper arms, forearms, thighs, shins, pods): the hull is sliced at ~8 stations
  along the bone (once, at load). A hole or breach removes its share of a station's
  cross-section (chord × width). Below ~35% left [tune] the part breaks there: layer 5 at that
  station, through the hole. A beam that drills a forearm near its edge leaves it on; one through
  the middle of a thin forearm takes the hand off.
- **Loose pieces**: one whose attachment area is inside a hole or breach detaches (layer 2).
- **Load** (later): a weakened limb can be torn off by the suit's own manoeuvre: mass × the
  hull's acceleration × lever against what's left of the section.

### Covering the moment, honestly

Flash, sparks, the propellant's ice glitter, a few small generic shards (~10 low-poly plate shapes,
instanced, cooling colours) at the break: enough to make the instant violent. They are gone within
a second or two in vacuum, so layers 1–6 carry the look after that.

## What it looks like: a beam through a thigh

1. 0–5 ms: the beam's head drills the armour; its tail pours on through the hole
   (`beam_effects.md`).
2. On its line: an actuator, then a water cell that stops the rest of the beam and flashes to
   steam: a few ms later it bursts.
   `R` ≈ 2 m: four jagged plates blow off the front and two off the back, tumbling away glowing
   where the hole crossed them; ice spray glitters and is gone. Through the gaps: the thigh's
   frame strut and the hip actuator, lit red by the hole.
3. The check: the hole and the breach leave 30% of the thigh's section at that height. The thigh
   breaks there: the leg below drifts off, a cut face of torn and melted metal, the strut cut.
   The knee and foot thrusters go with it; the mass model and the capability map follow; AMBAC
   loses that leg.
4. If it had left 50%, the leg stays on, limp if the hip actuator was on the line, or working if
   not.

## Godot notes

- **CPU skinning for baking**: per vertex, the weighted sum of `skeleton.get_bone_global_pose(b) *
  skin.get_bind_pose(b)`; a part is a few hundred vertices. Done in the hit's tick.
- **New meshes**: `ArrayMesh` / `SurfaceTool`; pieces get `ConvexPolygonShape3D` from their
  vertices; debris collides with nothing but other suits (or nothing) [tune].
- **Budgets** [tune]: ≤ 24 free pieces in flight; past it, or 60 s, or 2 km away, the oldest go.
- **Draw calls**: pieces add one each while they fly; the suit's own meshes never split (piece ids
  and discard), so an intact suit costs what it does today.
- **Shared shader budget**: holes, breaches and cuts share each mesh's record arrays.

## Limitations

- The inner frame is generic: struts, joint drums, actuators, cables. Not the real machinery of
  each part (that would be per-part modelling).
- Seeds and noise make every breach different, but they don't follow the model's painted panel
  lines; pieces can cross a painted seam.
- Pieces are rigid; nothing bends or dents (BeamNG-style deformation is out of scope).
- The cut face and the breach edge are drawn by the shader: right from any angle, but they have
  no silhouette of their own (a cut seen exactly edge-on shows the shell's edge).
