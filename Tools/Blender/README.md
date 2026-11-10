# Blender build scripts

Procedural sources for the prototype models. Godot ignores this folder (`Tools/.gdignore`).

```sh
blender -b -P Tools/Blender/build_mobile_suit_prototype.py -- \
    Entities/Vehicles/MobileSuits/Prototype/Arts/mobile_suit_prototype.glb

blender -b -P Tools/Blender/build_cockpit_linear_seat.py -- \
    Entities/Vehicles/Cockpits/CockpitLinearSeat/Arts/cockpit_linear_seat.glb
```

- `mesh_kit.py`: shared helpers (tapered boxes, cylinders, quads, materials, armature, GLB export).
- Blender space: Z up, model front = +Y, right = +X. The glTF exporter converts this to Godot's
  Y-up / front = -Z.
- Keep object and bone names stable: the Godot scenes reference `GripL`, `PedalR`, `hatch_upper`,
  `shin.R`, etc.
