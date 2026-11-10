"""Builds the beam rifle as a static GLB.

Run:  blender -b -P Tools/Blender/build_beam_rifle.py -- <output.glb>

Origin = grip point (where the hand closes). Barrel along +Y (Godot -Z), scope up (+Z).
Muzzle at (0, 6.05, 0.75).
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import mesh_kit as mk  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "beam_rifle.glb"
    mk.reset_scene()
    m = {
        "navy": mk.make_material("EQ_Navy", (0.05, 0.055, 0.09), roughness=0.4),
        "white": mk.make_material("EQ_White", (0.86, 0.87, 0.89), roughness=0.42),
        "frame": mk.make_material("EQ_Frame", (0.32, 0.33, 0.36), metallic=0.6, roughness=0.4),
        "dark": mk.make_material("EQ_Dark", (0.05, 0.05, 0.06), metallic=0.4, roughness=0.6),
        "yellow": mk.make_material("EQ_Yellow", (0.95, 0.72, 0.06), roughness=0.4),
        "lens": mk.make_material("EQ_Lens", (0.05, 0.3, 0.2), emission=(0.25, 1.0, 0.65), strength=3.0),
    }
    r = mk.PartBuilder("BeamRifle", m)
    r.tbox((0, 0.6, 0.55), (0.55, 3.2), (0.5, 3.0), 1.0, "navy")
    r.box((0, 2.8, 0.75), (0.45, 1.6, 0.5), "white")
    r.cylinder((0, 3.9, 0.75), 0.2, 3.6, "frame", rot=(90, 0, 0))
    r.cylinder((0, 5.8, 0.75), 0.3, 0.5, "dark", rot=(90, 0, 0))
    r.box((0, 0.5, 1.3), (0.35, 1.4, 0.35), "white")
    r.box((0, 1.22, 1.3), (0.25, 0.06, 0.25), "lens")
    r.tbox((0, -1.9, 0.55), (0.4, 1.8), (0.35, 1.6), 0.8, "navy")
    r.box((0, -2.75, 0.5), (0.42, 0.15, 0.9), "dark")
    r.box((0, -0.1, -0.35), (0.3, 0.45, 0.9), "dark", rot=(15, 0, 0))
    r.box((0, 0.9, -0.15), (0.4, 0.9, 0.6), "frame")
    r.box((0.21, 0.9, -0.15), (0.02, 0.6, 0.12), "yellow")
    r.box((0, 2.1, 0.05), (0.25, 0.3, 0.6), "dark")
    r.to_object(bevel=0.02)
    mk.export_glb(os.path.abspath(out), skins=False)
    print(f"[build_beam_rifle] exported {out}")


main()
