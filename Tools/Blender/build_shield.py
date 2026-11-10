"""Builds the arm shield as a static GLB.

Run:  blender -b -P Tools/Blender/build_shield.py -- <output.glb>

Origin = forearm mount on the back. Long axis +Z (pointed end down), face +Y (Godot -Z).
Face outline (x, z) on the plane y = 0.5, used for the HUD silhouette:
  (-1.8, 2.8) (1.8, 2.8) (1.8, -2.0) (0.15, -4.6) (-0.15, -4.6) (-1.8, -2.0)
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import mesh_kit as mk  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "shield.glb"
    mk.reset_scene()
    m = {
        "white": mk.make_material("EQ_White", (0.86, 0.87, 0.89), roughness=0.42),
        "navy": mk.make_material("EQ_Navy", (0.05, 0.055, 0.09), roughness=0.4),
        "frame": mk.make_material("EQ_Frame", (0.32, 0.33, 0.36), metallic=0.6, roughness=0.4),
        "yellow": mk.make_material("EQ_Yellow", (0.95, 0.72, 0.06), roughness=0.4),
        "red": mk.make_material("EQ_Red", (0.72, 0.06, 0.06), roughness=0.4),
    }
    s = mk.PartBuilder("Shield", m)
    s.box((0, 0.35, 0.4), (3.6, 0.3, 4.8), "white")
    s.tbox((0, 0.35, -3.3), (0.3, 0.3), (3.6, 0.3), 2.6, "white")
    s.box((0, 0.52, 0.7), (2.4, 0.05, 3.4), "navy")
    s.box((0, 0.56, 1.7), (1.3, 0.04, 0.4), "yellow")
    s.box((0, 0.56, -0.9), (0.4, 0.04, 2.0), "red")
    for x in (1.7, -1.7):
        s.box((x, 0.3, 0.4), (0.25, 0.42, 4.8), "navy")
    s.box((0, 0.35, 2.75), (3.6, 0.42, 0.15), "navy")
    s.box((0, 0.0, 0.4), (0.8, 0.4, 1.6), "frame")
    s.box((0, -0.05, -1.6), (0.5, 0.3, 1.2), "frame")
    s.to_object(bevel=0.02)
    mk.export_glb(os.path.abspath(out), skins=False)
    print(f"[build_shield] exported {out}")


main()
