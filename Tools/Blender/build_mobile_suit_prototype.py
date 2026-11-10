"""Builds the prototype mobile suit (MSP-01) as a rigged GLB.

Run:  blender -b -P Tools/Blender/build_mobile_suit_prototype.py -- <output.glb>

Every part is a separate mesh rigidly skinned (weight 1.0) to a single bone, so
the suit can be animated later without re-weighting. Part meshes stay separate
so Godot can assign per-part render layers.

Key reference points (Blender space, Z up, front = +Y):
  Cockpit centre      (0, 0.4, 14.4)   cavity is a 2.8 m cube around it
  Hatch hinges        upper (0, 2.3, 15.8)  lower (0, 2.3, 13.0)
  Head sensor (visor) (0, 1.3, 17.6)
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import mesh_kit as mk  # noqa: E402

COCKPIT_CENTER = (0.0, 0.4, 14.4)
CAVITY_HALF = 1.4


def materials():
    return {
        "white": mk.make_material("MS_ArmorWhite", (0.84, 0.85, 0.87), roughness=0.45),
        "blue": mk.make_material("MS_ArmorBlue", (0.10, 0.17, 0.38), roughness=0.4),
        "frame": mk.make_material("MS_Frame", (0.20, 0.21, 0.24), metallic=0.6, roughness=0.4),
        "dark": mk.make_material("MS_Dark", (0.06, 0.06, 0.07), metallic=0.4, roughness=0.6),
        "yellow": mk.make_material("MS_AccentYellow", (0.95, 0.70, 0.08), roughness=0.4),
        "red": mk.make_material("MS_AccentRed", (0.70, 0.08, 0.08), roughness=0.4),
        "visor": mk.make_material("MS_Visor", (0.05, 0.3, 0.2), emission=(0.25, 1.0, 0.65), strength=4.0),
        "cavity": mk.make_material("MS_Cavity", (0.13, 0.13, 0.15), metallic=0.3, roughness=0.7),
    }


def bones():
    b = [
        ("root", (0, 0, 0), (0, 0, 1), None),
        ("pelvis", (0, 0, 10.6), (0, 0, 11.8), "root"),
        ("spine", (0, 0, 11.8), (0, 0, 13.0), "pelvis"),
        ("chest", (0, 0, 13.0), (0, 0, 16.4), "spine"),
        ("head", (0, 0.3, 16.5), (0, 0.3, 18.0), "chest"),
        ("backpack", (0, -1.6, 13.5), (0, -1.6, 15.5), "chest"),
        ("hatch_upper", (0, 2.3, 15.8), (0, 2.3, 16.3), "chest"),
        ("hatch_lower", (0, 2.3, 13.0), (0, 2.3, 12.5), "chest"),
    ]
    for side, s in (("R", 1.0), ("L", -1.0)):
        b += [
            (f"shoulder.{side}", (2.9 * s, 0, 15.4), (4.0 * s, 0, 15.4), "chest"),
            (f"upper_arm.{side}", (4.0 * s, 0, 15.0), (4.0 * s, 0, 11.6), f"shoulder.{side}"),
            (f"forearm.{side}", (4.0 * s, 0, 11.6), (4.0 * s, 0, 8.4), f"upper_arm.{side}"),
            (f"hand.{side}", (4.0 * s, 0, 8.4), (4.0 * s, 0, 7.2), f"forearm.{side}"),
            (f"skirt_front.{side}", (1.25 * s, 1.25, 11.3), (1.25 * s, 1.45, 9.6), "pelvis"),
            (f"skirt_side.{side}", (2.4 * s, 0, 11.2), (2.6 * s, 0, 9.6), "pelvis"),
            (f"thigh.{side}", (1.35 * s, 0, 10.4), (1.35 * s, 0, 6.3), "pelvis"),
            (f"shin.{side}", (1.35 * s, 0, 6.3), (1.35 * s, 0, 1.2), f"thigh.{side}"),
            (f"foot.{side}", (1.35 * s, 0, 1.2), (1.35 * s, 1.2, 0.3), f"shin.{side}"),
        ]
    return b


def build_torso(m, arm):
    # Chest is a hollow frame around the cockpit cavity so the open hatch shows a real opening.
    chest = mk.PartBuilder("Chest", m)
    for s in (1.0, -1.0):
        chest.tbox((2.1 * s, 0.3, 14.4), (1.4, 3.6), (1.4, 3.8), 2.8, "white")
        chest.box((2.15 * s, 2.25, 14.9), (1.3, 0.22, 1.9), "blue", rot=(0, 0, -8 * s))
        chest.box((2.15 * s, 2.4, 15.05), (0.9, 0.12, 0.18), "yellow")
        chest.box((2.15 * s, 2.4, 14.75), (0.9, 0.12, 0.18), "yellow")
        chest.box((2.75 * s, -0.2, 15.9), (0.6, 2.6, 0.5), "frame")
    chest.tbox((0, 0.35, 16.15), (5.6, 3.9), (4.8, 3.2), 0.7, "white")
    chest.box((0, 0.3, 12.8), (4.6, 3.4, 0.4), "frame")
    chest.box((0, -1.3, 14.4), (2.8, 0.6, 2.8), "cavity")
    chest.box((0, 1.6, 16.25), (1.6, 0.6, 0.45), "red")
    chest.to_object(armature=arm, bone="chest", bevel=0.05)

    waist = mk.PartBuilder("Waist", m)
    waist.box((0, 0, 12.0), (2.4, 2.4, 1.2), "frame")
    waist.box((0, 1.15, 12.1), (2.0, 0.3, 0.9), "white")
    waist.to_object(armature=arm, bone="spine", bevel=0.04)

    pelvis = mk.PartBuilder("Pelvis", m)
    pelvis.tbox((0, 0.1, 10.8), (1.0, 1.6), (2.6, 2.2), 1.6, "frame")
    pelvis.tbox((0, 1.05, 10.9), (0.7, 0.3), (1.3, 0.3), 1.2, "blue")
    pelvis.box((0, 1.25, 11.1), (0.4, 0.1, 0.4), "yellow")
    pelvis.box((0, -1.25, 10.4), (2.2, 0.3, 1.5), "white", rot=(-10, 0, 0))
    for s in (1.0, -1.0):
        pelvis.cylinder((1.35 * s, 0, 10.5), 0.5, 0.5, "frame", rot=(0, 90, 0))
    pelvis.to_object(armature=arm, bone="pelvis", bevel=0.04)


def build_hatch(m, arm):
    upper = mk.PartBuilder("HatchUpper", m)
    upper.box((0, 2.075, 15.075), (2.7, 0.42, 1.35), "white")
    upper.box((0, 2.3, 15.3), (2.2, 0.06, 0.12), "blue")
    upper.box((0, 1.84, 15.075), (2.5, 0.05, 1.2), "cavity")
    upper.to_object(armature=arm, bone="hatch_upper", bevel=0.03)

    lower = mk.PartBuilder("HatchLower", m)
    lower.tbox((0, 2.075, 13.725), (2.4, 0.42), (2.7, 0.42), 1.35, "blue")
    lower.box((0, 2.3, 13.9), (0.8, 0.06, 0.5), "frame")
    lower.box((0, 1.84, 13.725), (2.3, 0.05, 1.2), "cavity")
    lower.to_object(armature=arm, bone="hatch_lower", bevel=0.03)


def build_head(m, arm):
    head = mk.PartBuilder("Head", m)
    head.cylinder((0, 0.2, 16.8), 0.45, 0.6, "frame")
    head.tbox((0, 0.35, 17.6), (1.3, 1.5), (1.0, 1.3), 1.4, "white")
    head.box((0, 1.12, 17.3), (0.9, 0.3, 0.6), "frame")
    head.box((0, 1.22, 17.6), (1.0, 0.14, 0.24), "visor")
    head.box((0, 0.9, 18.35), (0.08, 0.9, 0.22), "yellow", rot=(-25, 0, 0))
    for s in (1.0, -1.0):
        head.cylinder((0.66 * s, 0.35, 17.6), 0.26, 0.2, "blue", rot=(0, 90, 0))
    head.to_object(armature=arm, bone="head", bevel=0.03)


def build_backpack(m, arm):
    bp = mk.PartBuilder("Backpack", m)
    bp.tbox((0, -2.3, 14.6), (2.6, 1.4), (3.0, 1.2), 3.0, "blue")
    bp.box((0, -3.05, 14.9), (1.8, 0.2, 1.6), "frame")
    for s in (1.0, -1.0):
        bp.box((0.9 * s, -2.7, 16.6), (0.3, 0.9, 2.2), "white", rot=(-15, 0, 0))
        bp.cylinder((0.8 * s, -2.6, 12.95), 0.45, 0.5, "frame")
    bp.to_object(armature=arm, bone="backpack", bevel=0.04)


def build_arm(m, arm, side, s):
    sh = mk.PartBuilder(f"Shoulder.{side}", m)
    sh.cylinder((3.1 * s, 0, 15.2), 0.55, 0.6, "frame", rot=(0, 90, 0))
    sh.tbox((4.0 * s, 0, 15.7), (1.7, 2.4), (2.0, 2.8), 1.8, "white")
    sh.tbox((4.0 * s, 0, 16.75), (2.0, 2.8), (1.7, 2.2), 0.3, "blue")
    sh.box((4.0 * s, 1.41, 15.5), (1.2, 0.05, 0.25), "yellow")
    sh.box((4.0 * s, -1.25, 16.45), (0.9, 0.6, 0.5), "frame")
    sh.to_object(armature=arm, bone=f"shoulder.{side}", bevel=0.05)

    ua = mk.PartBuilder(f"UpperArm.{side}", m)
    ua.box((4.0 * s, 0, 13.3), (0.95, 1.0, 3.2), "frame")
    ua.box((4.0 * s, -0.35, 11.75), (1.0, 0.9, 0.8), "white")
    ua.to_object(armature=arm, bone=f"upper_arm.{side}", bevel=0.04)

    fa = mk.PartBuilder(f"Forearm.{side}", m)
    fa.tbox((4.0 * s, 0.05, 10.0), (1.45, 1.55), (1.2, 1.3), 3.0, "white")
    fa.box((4.74 * s, 0.05, 10.0), (0.1, 1.0, 1.8), "blue")
    fa.to_object(armature=arm, bone=f"forearm.{side}", bevel=0.04)

    hand = mk.PartBuilder(f"Hand.{side}", m)
    hand.box((4.0 * s, 0.1, 7.95), (0.7, 0.9, 0.9), "frame")
    hand.box((4.0 * s, 0.25, 7.25), (0.6, 0.8, 0.6), "dark", rot=(15, 0, 0))
    hand.box((3.62 * s, 0.45, 7.7), (0.2, 0.25, 0.5), "dark")
    hand.to_object(armature=arm, bone=f"hand.{side}", bevel=0.02)


def build_leg(m, arm, side, s):
    sf = mk.PartBuilder(f"SkirtFront.{side}", m)
    sf.tbox((1.25 * s, 1.4, 10.3), (1.4, 0.28), (1.5, 0.28), 2.0, "white", rot=(10, 0, 0))
    sf.box((1.25 * s, 1.62, 9.7), (1.1, 0.06, 0.15), "blue", rot=(10, 0, 0))
    sf.to_object(armature=arm, bone=f"skirt_front.{side}", bevel=0.03)

    ss = mk.PartBuilder(f"SkirtSide.{side}", m)
    ss.box((2.45 * s, 0, 10.3), (0.28, 1.7, 2.1), "white", rot=(0, -10 * s, 0))
    ss.box((2.62 * s, 0, 10.0), (0.06, 1.2, 0.6), "frame", rot=(0, -10 * s, 0))
    ss.to_object(armature=arm, bone=f"skirt_side.{side}", bevel=0.03)

    th = mk.PartBuilder(f"Thigh.{side}", m)
    th.tbox((1.35 * s, 0, 8.4), (1.2, 1.3), (1.4, 1.5), 3.6, "frame")
    th.box((1.35 * s, 0.7, 8.6), (1.1, 0.25, 2.6), "white")
    th.to_object(armature=arm, bone=f"thigh.{side}", bevel=0.04)

    sh = mk.PartBuilder(f"Shin.{side}", m)
    sh.cylinder((1.35 * s, 0, 6.3), 0.55, 1.1, "frame", rot=(0, 90, 0))
    sh.tbox((1.35 * s, 0.75, 6.2), (1.2, 0.6), (1.0, 0.5), 1.0, "white")
    sh.tbox((1.35 * s, 0.05, 3.8), (1.8, 2.0), (1.45, 1.6), 4.6, "white")
    sh.tbox((1.35 * s, -1.1, 3.0), (1.2, 0.7), (1.0, 0.5), 2.2, "frame")
    sh.box((2.27 * s, 0.0, 2.4), (0.08, 0.9, 0.5), "yellow")
    sh.cylinder((1.35 * s, 0, 1.25), 0.45, 0.9, "frame", rot=(0, 90, 0))
    sh.to_object(armature=arm, bone=f"shin.{side}", bevel=0.05)

    ft = mk.PartBuilder(f"Foot.{side}", m)
    ft.tbox((1.35 * s, 0.4, 0.5), (1.7, 3.2), (1.4, 2.2), 1.0, "blue", shift=(0, 0.2))
    ft.tbox((1.35 * s, 1.9, 0.35), (1.6, 0.8), (1.3, 0.5), 0.7, "white")
    ft.box((1.35 * s, -1.1, 0.4), (1.2, 0.6, 0.8), "white")
    ft.to_object(armature=arm, bone=f"foot.{side}", bevel=0.04)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "mobile_suit_prototype.glb"

    mk.reset_scene()
    m = materials()
    arm = mk.build_armature("Armature", bones())

    build_torso(m, arm)
    build_hatch(m, arm)
    build_head(m, arm)
    build_backpack(m, arm)
    for side, s in (("R", 1.0), ("L", -1.0)):
        build_arm(m, arm, side, s)
        build_leg(m, arm, side, s)

    mk.export_glb(os.path.abspath(out))
    print(f"[build_mobile_suit_prototype] exported {out}")


main()
