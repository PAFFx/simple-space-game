# Blender build scripts

Procedural sources for the prototype models. Godot ignores this folder (`Tools/.gdignore`).

```sh
blender -b -P Tools/Blender/build_mobile_suit_prototype.py -- \
    Entities/Vehicles/MobileSuits/Prototype/Arts/mobile_suit_prototype.glb

blender -b -P Tools/Blender/build_cockpit_linear_seat.py -- \
    Entities/Vehicles/Cockpits/CockpitLinearSeat/Arts/cockpit_linear_seat.glb

blender -b -P Tools/Blender/build_mobile_suit_msp02.py -- \
    Entities/Vehicles/MobileSuits/MSP02/Arts/mobile_suit_msp02.glb
blender -b -P Tools/Blender/build_beam_rifle.py -- Entities/Equipment/BeamRifle/Arts/beam_rifle.glb
blender -b -P Tools/Blender/build_shield.py -- Entities/Equipment/Shield/Arts/shield.glb

# RX-93 cockpit (linear seat v2); the aperture is the ν's hatch corridor.
blender -b -P Tools/Blender/build_cockpit_linear_seat_v2.py -- \
    Entities/Vehicles/Cockpits/CockpitLinearSeatV2/Arts/cockpit_linear_seat_v2.glb --aperture -37.3,20.5,25.3
# The same cockpit with RX-0 style rail grips instead of the ball controllers.
blender -b -P Tools/Blender/build_cockpit_linear_seat_v2.py -- \
    Entities/Vehicles/Cockpits/CockpitLinearSeatV2Rail/Arts/cockpit_linear_seat_v2_rail.glb --aperture -37.3,20.5,25.3 --controller rail

# After rebuilding the MSP-02 GLB, regenerate its scene + animations:
godot-mono --headless --path . -s Tools/Godot/build_msp02_scene.gd

# RX-93 ν Gundam: rigs the downloaded model (Sources/) and splits off its weapons.
blender -b -P Tools/Blender/build_mobile_suit_nu.py -- Tools/Blender/Sources/rx-93_nu_gundam.glb /tmp/nu
cp /tmp/nu/mobile_suit_nu.glb Entities/Vehicles/MobileSuits/RX93/Arts/
cp /tmp/nu/nu_*.glb Entities/Equipment/RX93/Arts/
godot-mono --headless --path . -s Tools/Godot/build_rx93_scene.gd
```

- `Sources/rx-93_nu_gundam.glb`: downloaded (Sketchfab) static model, kept as the source of truth.
  Check its licence before sharing the project. The build script welds it back into 174 parts and
  assigns them to bones/weapons by index (`GROUPS`), so a different source file needs a new table.

- `cockpit_shell.py`: the capsule shell and inner door shared by both cockpit scripts.
- `fix_character_weights.py`: plain Python, patches stray skin weights in a GLB in place (already
  applied to the Amate model's boots).
- `mesh_kit.py`: shared helpers (tapered boxes, cylinders, quads, materials, armature, GLB export).
- Blender space: Z up, model front = +Y, right = +X. The glTF exporter converts this to Godot's
  Y-up / front = -Z.
- Keep object and bone names stable: the Godot scenes reference `GripL`, `PedalR`, `hatch_upper`,
  `shin.R`, etc.
