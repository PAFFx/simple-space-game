"""Builds the MSP-02 late-UC mobile suit as a rigged GLB (no equipment; see build_beam_rifle.py
and build_shield.py).

Run:  blender -b -P Tools/Blender/build_mobile_suit_msp02.py -- <output.glb>

Rigid mech rig: every part is its own mesh, weighted 1.0 to one bone, so it can be animated or
re-rigged without re-weighting. Bone names are referenced from Godot (AMBAC joints, poses,
equipment mounts, thrusters), so keep them stable.

Key reference points (Blender space, Z up, front = +Y, right = +X):
  Cockpit centre      (0, 0.5, 16.1)   cavity is a 2.8 m cube around it
  Hatch hinges        upper (0, 2.5, 17.5)  lower (0, 2.5, 14.7)
  Head sensor (visor) (0, 1.35, 19.95)    head top ~21.2 m
  Right hand grip     (3.9, 0.1, 9.6)    left forearm hard point (-4.75, 0.05, 11.6)
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import mesh_kit as mk  # noqa: E402


def materials():
    return {
        "white": mk.make_material("MS_ArmorWhite", (0.86, 0.87, 0.89), roughness=0.42),
        "navy": mk.make_material("MS_ArmorNavy", (0.035, 0.04, 0.085), roughness=0.38),
        "frame": mk.make_material("MS_Frame", (0.32, 0.33, 0.36), metallic=0.6, roughness=0.4),
        "dark": mk.make_material("MS_Dark", (0.05, 0.05, 0.06), metallic=0.4, roughness=0.6),
        "yellow": mk.make_material("MS_AccentYellow", (0.95, 0.72, 0.06), roughness=0.4),
        "red": mk.make_material("MS_AccentRed", (0.72, 0.06, 0.06), roughness=0.4),
        "visor": mk.make_material("MS_Visor", (0.05, 0.3, 0.2), emission=(0.25, 1.0, 0.65), strength=4.0),
        "cavity": mk.make_material("MS_Cavity", (0.13, 0.13, 0.15), metallic=0.3, roughness=0.7),
    }


def bones():
    b = [
        ("root", (0, 0, 0), (0, 0, 1), None),
        ("pelvis", (0, 0, 12.2), (0, 0, 13.2), "root"),
        ("spine", (0, 0, 13.2), (0, 0, 14.2), "pelvis"),
        ("chest", (0, 0, 14.2), (0, 0, 18.4), "spine"),
        ("neck", (0, 0.3, 18.4), (0, 0.3, 19.1), "chest"),
        ("head", (0, 0.3, 19.1), (0, 0.3, 20.9), "neck"),
        ("backpack", (0, -2.0, 15.0), (0, -2.0, 17.0), "chest"),
        ("hatch_upper", (0, 2.5, 17.5), (0, 2.5, 18.0), "chest"),
        ("hatch_lower", (0, 2.5, 14.7), (0, 2.5, 14.2), "chest"),
    ]
    for side, s in (("R", 1.0), ("L", -1.0)):
        b += [
            (f"shoulder.{side}", (1.6 * s, 0, 17.6), (3.4 * s, 0, 17.6), "chest"),
            (f"upper_arm.{side}", (3.9 * s, 0, 17.2), (3.9 * s, 0, 13.8), f"shoulder.{side}"),
            (f"forearm.{side}", (3.9 * s, 0, 13.8), (3.9 * s, 0, 10.2), f"upper_arm.{side}"),
            (f"hand.{side}", (3.9 * s, 0, 10.2), (3.9 * s, 0, 9.0), f"forearm.{side}"),
            (f"skirt_front.{side}", (1.2 * s, 1.4, 13.1), (1.3 * s, 1.7, 11.1), "pelvis"),
            (f"skirt_side.{side}", (2.5 * s, 0, 13.0), (2.8 * s, 0, 11.1), "pelvis"),
            (f"skirt_rear.{side}", (1.0 * s, -1.4, 13.1), (1.1 * s, -1.7, 11.3), "pelvis"),
            (f"thigh.{side}", (1.5 * s, 0, 12.2), (1.5 * s, 0, 7.4), "pelvis"),
            (f"shin.{side}", (1.5 * s, 0, 7.4), (1.5 * s, 0, 1.7), f"thigh.{side}"),
            (f"foot.{side}", (1.5 * s, 0, 1.7), (1.5 * s, 1.3, 0.4), f"shin.{side}"),
        ]
    return b


def build_chest(m, arm):
    # Hollow frame around the cockpit cavity (x ±1.4, y -0.9..1.9, z 14.7..17.5).
    c = mk.PartBuilder("Chest", m)
    for s in (1.0, -1.0):
        c.tbox((2.15 * s, 0.45, 16.1), (1.5, 4.3), (1.5, 4.0), 3.6, "navy", shift=(0, -0.1))
        # Vent block either side of the hatch: housing + three slats.
        c.box((2.1 * s, 2.56, 16.45), (1.3, 0.1, 1.25), "dark")
        for z in (16.9, 16.48, 16.06):
            c.box((2.1 * s, 2.63, z), (1.1, 0.1, 0.17), "yellow")
        c.box((2.15 * s, 2.35, 17.6), (1.5, 0.45, 0.55), "white")
        c.box((2.95 * s, 0.3, 16.4), (0.1, 2.2, 1.6), "dark")
        c.box((2.4 * s, 1.0, 14.5), (1.0, 2.6, 0.5), "white")
    c.tbox((0, 0.35, 18.1), (5.8, 4.2), (4.6, 3.2), 0.7, "white")
    c.box((0, 1.95, 18.05), (2.0, 0.3, 0.5), "navy")
    c.box((0, -1.3, 16.1), (2.8, 0.8, 2.8), "cavity")
    c.box((0, 0.45, 14.45), (4.8, 4.0, 0.5), "frame")
    c.box((0, 2.48, 14.4), (1.0, 0.3, 0.35), "red")
    c.box((0, -0.2, 18.55), (2.0, 1.6, 0.3), "frame")
    c.to_object(armature=arm, bone="chest", bevel=0.05)


def build_hatch(m, arm):
    up = mk.PartBuilder("HatchUpper", m)
    up.box((0, 2.25, 16.8), (2.75, 0.7, 1.38), "navy")
    up.box((0, 2.61, 17.2), (2.2, 0.05, 0.12), "white")
    up.box((0, 1.91, 16.8), (2.5, 0.05, 1.2), "cavity")
    up.to_object(armature=arm, bone="hatch_upper", bevel=0.03)

    lo = mk.PartBuilder("HatchLower", m)
    lo.tbox((0, 2.25, 15.4), (2.45, 0.7), (2.75, 0.7), 1.38, "navy")
    lo.box((0, 2.61, 15.55), (0.9, 0.05, 0.5), "frame")
    lo.box((0, 1.91, 15.4), (2.3, 0.05, 1.2), "cavity")
    lo.to_object(armature=arm, bone="hatch_lower", bevel=0.03)


def build_core(m, arm):
    w = mk.PartBuilder("Waist", m)
    w.box((0, 0, 13.7), (2.4, 2.2, 1.0), "frame")
    w.box((0, 1.05, 13.7), (1.8, 0.3, 0.8), "white")
    for s in (1.0, -1.0):
        w.box((1.25 * s, 0.6, 13.7), (0.3, 1.2, 0.7), "white")
    w.to_object(armature=arm, bone="spine", bevel=0.04)

    p = mk.PartBuilder("Pelvis", m)
    p.tbox((0, 0.1, 12.4), (1.2, 1.6), (3.0, 2.4), 1.6, "frame")
    p.tbox((0, 1.15, 12.3), (0.8, 0.4), (1.4, 0.4), 1.4, "navy")
    p.box((0, 1.37, 12.6), (0.35, 0.1, 0.35), "yellow")
    for s in (1.0, -1.0):
        p.cylinder((1.5 * s, 0, 12.2), 0.55, 0.6, "frame", rot=(0, 90, 0))
    p.to_object(armature=arm, bone="pelvis", bevel=0.04)


def build_head(m, arm):
    n = mk.PartBuilder("Neck", m)
    n.cylinder((0, 0.3, 18.75), 0.45, 0.7, "frame")
    n.to_object(armature=arm, bone="neck", bevel=0.02)

    h = mk.PartBuilder("Head", m)
    h.tbox((0, 0.45, 19.9), (1.3, 1.6), (1.05, 1.35), 1.6, "white")
    h.box((0, 1.22, 19.85), (0.95, 0.3, 0.42), "dark")
    h.box((0, 1.32, 19.9), (0.98, 0.12, 0.2), "visor")
    h.box((0, 1.28, 19.35), (0.45, 0.12, 0.2), "red")
    h.box((0, 0.9, 20.8), (0.1, 1.0, 0.25), "yellow", rot=(-25, 0, 0))
    h.box((0, -0.45, 20.2), (0.7, 0.3, 0.5), "navy")
    for s in (1.0, -1.0):
        h.cylinder((0.66 * s, 0.45, 19.9), 0.28, 0.22, "navy", rot=(0, 90, 0))
        h.box((0.45 * s, 0.6, 20.75), (0.08, 0.55, 0.18), "white", rot=(-35, 0, 15 * s))
    h.to_object(armature=arm, bone="head", bevel=0.03)


def build_backpack(m, arm):
    bp = mk.PartBuilder("Backpack", m)
    bp.box((0, -1.8, 16.0), (1.6, 0.3, 2.2), "frame")
    bp.tbox((0, -2.4, 16.0), (2.2, 1.4), (2.6, 1.2), 3.2, "navy")
    bp.box((0, -3.12, 16.3), (1.4, 0.12, 1.8), "frame")
    for s in (1.0, -1.0):
        # Twin pods, each carrying an upper (rearward) and lower (downward) main nozzle.
        bp.cylinder((1.5 * s, -2.9, 16.0), 0.75, 3.4, "frame")
        bp.box((1.5 * s, -3.1, 16.4), (1.3, 1.1, 2.4), "white")
        bp.box((1.5 * s, -3.67, 16.4), (0.9, 0.06, 1.6), "navy")
        bp.cylinder((1.5 * s, -3.65, 17.15), 0.55, 0.35, "dark", rot=(90, 0, 0))
        bp.cylinder((1.5 * s, -2.9, 14.25), 0.6, 0.3, "dark")
        bp.box((1.5 * s, -2.9, 17.75), (0.7, 0.7, 0.2), "dark")
        bp.box((2.25 * s, -2.9, 16.0), (0.12, 0.8, 0.8), "dark")
    bp.to_object(armature=arm, bone="backpack", bevel=0.04)


def build_arm(m, arm, side, s):
    sh = mk.PartBuilder(f"Shoulder.{side}", m)
    sh.cylinder((3.3 * s, 0, 17.4), 0.6, 0.8, "frame", rot=(0, 90, 0))
    sh.tbox((4.1 * s, 0, 17.9), (2.0, 2.8), (2.3, 3.0), 2.0, "white")
    sh.tbox((4.1 * s, 0, 19.05), (2.3, 3.0), (1.9, 2.4), 0.3, "navy")
    sh.box((4.1 * s, 1.55, 17.7), (1.6, 0.12, 1.2), "navy")
    sh.box((4.1 * s, 1.62, 17.25), (1.2, 0.06, 0.2), "yellow")
    sh.box((5.27 * s, 0, 17.8), (0.12, 2.2, 1.4), "navy")
    sh.box((4.1 * s, -1.55, 18.1), (1.0, 0.2, 0.8), "dark")
    sh.to_object(armature=arm, bone=f"shoulder.{side}", bevel=0.05)

    ua = mk.PartBuilder(f"UpperArm.{side}", m)
    ua.box((3.9 * s, 0, 15.6), (1.0, 1.05, 3.0), "frame")
    ua.box((3.9 * s, 0.45, 15.9), (0.8, 0.2, 1.6), "white")
    ua.box((3.9 * s, -0.35, 14.05), (1.05, 0.9, 0.8), "white")
    ua.to_object(armature=arm, bone=f"upper_arm.{side}", bevel=0.04)

    fa = mk.PartBuilder(f"Forearm.{side}", m)
    fa.tbox((3.9 * s, 0.05, 12.0), (1.55, 1.6), (1.25, 1.35), 3.4, "white")
    fa.box((4.69 * s, 0.05, 12.3), (0.1, 1.0, 2.0), "navy")
    fa.box((4.72 * s, 0.05, 11.6), (0.08, 0.6, 0.6), "dark")
    fa.box((3.9 * s, 0.83, 12.6), (0.9, 0.08, 0.3), "red")
    fa.to_object(armature=arm, bone=f"forearm.{side}", bevel=0.04)

    hd = mk.PartBuilder(f"Hand.{side}", m)
    hd.box((3.9 * s, 0.1, 9.75), (0.75, 0.95, 0.9), "frame")
    hd.box((3.9 * s, 0.3, 9.05), (0.65, 0.85, 0.6), "dark", rot=(15, 0, 0))
    hd.box((3.52 * s, 0.5, 9.5), (0.2, 0.25, 0.5), "dark")
    hd.to_object(armature=arm, bone=f"hand.{side}", bevel=0.02)


def build_leg(m, arm, side, s):
    sf = mk.PartBuilder(f"SkirtFront.{side}", m)
    sf.tbox((1.25 * s, 1.45, 12.2), (1.5, 0.3), (1.6, 0.3), 2.2, "white", rot=(10, 0, 0))
    sf.box((1.25 * s, 1.66, 11.5), (1.2, 0.06, 0.18), "navy", rot=(10, 0, 0))
    sf.to_object(armature=arm, bone=f"skirt_front.{side}", bevel=0.03)

    ss = mk.PartBuilder(f"SkirtSide.{side}", m)
    ss.box((2.6 * s, 0, 12.2), (0.3, 1.9, 2.3), "white", rot=(0, -10 * s, 0))
    ss.box((2.78 * s, 0, 11.7), (0.06, 1.0, 0.6), "dark", rot=(0, -10 * s, 0))
    ss.to_object(armature=arm, bone=f"skirt_side.{side}", bevel=0.03)

    sr = mk.PartBuilder(f"SkirtRear.{side}", m)
    sr.box((1.0 * s, -1.5, 12.3), (1.6, 0.3, 2.0), "navy", rot=(-12, 0, 0))
    sr.box((1.0 * s, -1.72, 11.6), (0.8, 0.06, 0.5), "dark", rot=(-12, 0, 0))
    sr.to_object(armature=arm, bone=f"skirt_rear.{side}", bevel=0.03)

    th = mk.PartBuilder(f"Thigh.{side}", m)
    th.tbox((1.5 * s, 0, 9.8), (1.3, 1.4), (1.5, 1.6), 4.0, "frame")
    th.box((1.5 * s, 0.75, 10.0), (1.2, 0.25, 2.8), "white")
    th.box((2.25 * s, 0, 9.6), (0.1, 1.0, 2.2), "white")
    th.to_object(armature=arm, bone=f"thigh.{side}", bevel=0.04)

    sh = mk.PartBuilder(f"Shin.{side}", m)
    sh.cylinder((1.5 * s, 0, 7.4), 0.6, 1.2, "frame", rot=(0, 90, 0))
    sh.tbox((1.5 * s, 0.85, 7.3), (1.3, 0.6), (1.0, 0.5), 1.2, "navy")
    sh.tbox((1.5 * s, 0.05, 4.6), (1.9, 2.1), (1.5, 1.7), 5.2, "white")
    sh.box((1.5 * s, 1.08, 5.4), (1.1, 0.08, 1.6), "navy")
    sh.tbox((1.5 * s, -1.2, 3.6), (1.3, 0.8), (1.1, 0.6), 2.4, "frame")
    sh.box((2.45 * s, 0, 3.0), (0.08, 0.9, 0.5), "yellow")
    sh.cylinder((1.5 * s, 0, 1.7), 0.5, 1.0, "frame", rot=(0, 90, 0))
    sh.to_object(armature=arm, bone=f"shin.{side}", bevel=0.05)

    ft = mk.PartBuilder(f"Foot.{side}", m)
    ft.tbox((1.5 * s, 0.4, 0.55), (1.8, 3.4), (1.5, 2.4), 1.1, "navy", shift=(0, 0.2))
    ft.tbox((1.5 * s, 2.0, 0.4), (1.7, 0.8), (1.4, 0.5), 0.8, "white")
    ft.box((1.5 * s, -1.2, 0.45), (1.3, 0.6, 0.9), "white")
    ft.to_object(armature=arm, bone=f"foot.{side}", bevel=0.04)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "mobile_suit_msp02.glb"

    mk.reset_scene()
    m = materials()
    arm = mk.build_armature("Armature", bones())
    build_chest(m, arm)
    build_hatch(m, arm)
    build_core(m, arm)
    build_head(m, arm)
    build_backpack(m, arm)
    for side, s in (("R", 1.0), ("L", -1.0)):
        build_arm(m, arm, side, s)
        build_leg(m, arm, side, s)
    mk.export_glb(os.path.abspath(out))
    print(f"[build_mobile_suit_msp02] exported {out}")


main()
