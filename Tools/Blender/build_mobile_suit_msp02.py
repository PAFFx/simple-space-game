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
        "visor": mk.make_material("MS_Visor", (0.05, 0.45, 0.25), emission=(0.2, 0.9, 0.45), strength=1.6),
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
    # Hollow around the cockpit cavity (x ±1.4, y -0.9..1.9, z 14.7..17.5).
    # V-tapered torso: side blocks flare out and forward toward the shoulders.
    c = mk.PartBuilder("Chest", m)
    for s in (1.0, -1.0):
        c.tbox((2.1 * s, 0.35, 16.0), (1.3, 3.5), (1.6, 4.2), 3.4, "navy", shift=(0.12 * s, 0.15))
        # Frame strip around the hatch opening.
        c.box((1.48 * s, 2.5, 16.1), (0.14, 0.22, 2.9), "white")
        # Angled intake vents either side of the hatch.
        c.box((2.15 * s, 2.5, 16.5), (1.15, 0.14, 1.2), "dark", rot=(0, 0, -6 * s))
        for i, z in enumerate((16.9, 16.5, 16.1)):
            c.box((2.15 * s, 2.6, z), (1.0 - 0.08 * i, 0.08, 0.16), "yellow", rot=(0, 0, -6 * s))
        # Pectoral plate above the vents, sloping back into the collar.
        c.tbox((2.1 * s, 2.15, 17.55), (1.5, 0.7), (1.3, 0.4), 0.6, "white", rot=(-18, 0, 0))
        # Lower rib flare and side armour.
        c.tbox((2.2 * s, 0.9, 14.55), (1.3, 3.2), (1.6, 3.6), 0.5, "white")
        c.box((2.97 * s, 0.25, 16.2), (0.12, 2.4, 1.9), "white")
        c.box((3.04 * s, 0.25, 16.2), (0.05, 1.6, 0.25), "dark")
    # Shoulder yoke / collar: wide at the shoulders, sloping in toward the neck.
    c.tbox((0, 0.15, 18.05), (5.7, 4.1), (3.9, 2.7), 0.8, "white")
    c.tbox((0, 1.75, 18.0), (2.4, 0.5), (1.6, 0.4), 0.55, "navy")
    c.box((0, 1.98, 18.0), (0.5, 0.1, 0.18), "yellow")
    c.box((0, -1.3, 16.1), (2.8, 0.8, 2.8), "cavity")
    c.tbox((0, 0.4, 14.45), (3.2, 3.2), (4.6, 3.8), 0.5, "frame")
    c.tbox((0, 2.35, 14.4), (1.4, 0.4), (1.8, 0.4), 0.4, "red")
    c.cylinder((0, -0.1, 18.5), 0.7, 0.25, "frame", segments=8)
    c.to_object(armature=arm, bone="chest", bevel=0.07)


def build_hatch(m, arm):
    up = mk.PartBuilder("HatchUpper", m)
    up.box((0, 2.25, 16.8), (2.75, 0.7, 1.38), "navy")
    up.box((0, 2.61, 17.25), (2.3, 0.05, 0.1), "white")
    up.box((0, 2.61, 16.35), (0.9, 0.05, 0.1), "frame")
    up.box((0, 1.91, 16.8), (2.5, 0.05, 1.2), "cavity")
    up.to_object(armature=arm, bone="hatch_upper", bevel=0.04)

    lo = mk.PartBuilder("HatchLower", m)
    lo.tbox((0, 2.25, 15.4), (2.4, 0.7), (2.75, 0.7), 1.38, "navy")
    lo.box((0, 2.61, 15.6), (1.2, 0.05, 0.45), "frame")
    lo.box((0, 2.61, 15.05), (1.8, 0.05, 0.08), "white")
    lo.box((0, 1.91, 15.4), (2.3, 0.05, 1.2), "cavity")
    lo.to_object(armature=arm, bone="hatch_lower", bevel=0.04)


def build_core(m, arm):
    w = mk.PartBuilder("Waist", m)
    w.cylinder((0, 0, 13.7), 1.0, 1.0, "frame", segments=8, radius_top=1.15)
    w.tbox((0, 0.9, 13.95), (1.0, 0.3), (1.2, 0.3), 0.38, "white")
    w.tbox((0, 0.88, 13.5), (0.9, 0.3), (1.05, 0.3), 0.36, "white")
    for s in (1.0, -1.0):
        w.box((0.95 * s, 0.55, 13.7), (0.25, 0.9, 0.75), "white", rot=(0, 0, 20 * s))
    w.to_object(armature=arm, bone="spine", bevel=0.05)

    p = mk.PartBuilder("Pelvis", m)
    p.tbox((0, 0.0, 12.55), (1.4, 1.8), (2.8, 2.3), 1.3, "frame")
    # Crotch block: tapered navy plate with a yellow marker.
    p.tbox((0, 1.05, 12.3), (0.55, 0.45), (1.25, 0.5), 1.4, "navy", shift=(0, 0.1))
    p.box((0, 1.33, 12.7), (0.32, 0.08, 0.32), "yellow")
    for s in (1.0, -1.0):
        p.cylinder((1.5 * s, 0, 12.2), 0.55, 0.7, "frame", rot=(0, 90, 0), segments=8)
    p.to_object(armature=arm, bone="pelvis", bevel=0.05)


def build_head(m, arm):
    n = mk.PartBuilder("Neck", m)
    n.cylinder((0, 0.3, 18.75), 0.38, 0.7, "frame", segments=8)
    n.cylinder((0, 0.3, 18.55), 0.55, 0.2, "dark", segments=8)
    n.to_object(armature=arm, bone="neck", bevel=0.02)

    h = mk.PartBuilder("Head", m)
    # Helmet: narrows to the top and slightly to the back.
    h.tbox((0, 0.35, 19.95), (1.15, 1.35), (0.95, 1.05), 1.3, "white", shift=(0, -0.08))
    h.box((0, -0.3, 19.95), (0.9, 0.45, 0.95), "navy")
    # Face: slim visor band in a dark frame, grey faceplate and chin with vents.
    h.box((0, 1.0, 20.0), (0.9, 0.16, 0.3), "dark")
    h.tbox((0, 1.07, 20.0), (0.8, 0.06), (0.7, 0.06), 0.16, "visor")
    h.tbox((0, 0.98, 19.58), (0.42, 0.3), (0.66, 0.34), 0.5, "frame")
    for z in (19.5, 19.62, 19.74):
        h.box((0, 1.16, z), (0.3, 0.03, 0.05), "dark")
    # Forehead crest and a single swept blade antenna.
    h.tbox((0, 0.95, 20.45), (0.4, 0.5), (0.16, 0.3), 0.36, "white")
    h.box((0, 0.65, 20.9), (0.06, 0.75, 0.16), "yellow", rot=(-38, 0, 0))
    for s in (1.0, -1.0):
        h.tbox((0.58 * s, 0.62, 19.62), (0.12, 0.85), (0.12, 0.6), 0.65, "white", rot=(0, 0, -8 * s))
        h.cylinder((0.6 * s, 0.25, 20.05), 0.24, 0.2, "navy", rot=(0, 90, 0), segments=8)
        h.cylinder((0.33 * s, 1.02, 20.28), 0.06, 0.12, "dark", rot=(90, 0, 0), segments=6)
        h.box((0.25 * s, -0.5, 20.6), (0.04, 0.04, 0.6), "frame", rot=(-25, 0, 0))
    h.to_object(armature=arm, bone="head", bevel=0.035)


def build_backpack(m, arm):
    bp = mk.PartBuilder("Backpack", m)
    bp.box((0, -1.8, 16.0), (1.6, 0.3, 2.2), "frame")
    bp.tbox((0, -2.4, 16.1), (2.0, 1.3), (2.5, 1.2), 3.2, "navy")
    bp.tbox((0, -3.06, 16.4), (1.3, 0.12), (1.5, 0.12), 2.0, "frame")
    for s in (1.0, -1.0):
        # Twin pods reaching down to the waist; each ends in two downward main bells.
        bp.cylinder((1.5 * s, -2.9, 15.35), 0.8, 4.5, "frame", segments=8)
        bp.tbox((1.5 * s, -3.1, 16.1), (1.25, 1.1), (1.4, 1.2), 3.0, "white")
        bp.box((1.5 * s, -3.72, 16.1), (0.8, 0.06, 2.1), "navy")
        bp.box((1.5 * s, -3.74, 17.0), (0.5, 0.06, 0.16), "yellow")
        bp.tbox((1.5 * s, -2.9, 13.35), (1.3, 1.2), (1.6, 1.5), 0.5, "navy")
        for dx in (-0.35, 0.35):
            bp.cylinder((1.5 * s + dx, -2.95, 12.95), 0.32, 0.4, "dark", rot=(-25, 0, 0), segments=10)
        bp.box((2.32 * s, -2.9, 16.0), (0.12, 0.8, 0.8), "dark")
        # Beam saber hilt in its rack, angled out over the shoulder.
        bp.cylinder((0.65 * s, -2.55, 18.0), 0.13, 1.1, "white", rot=(0, 18 * s, 0), segments=8)
        bp.cylinder((0.82 * s, -2.55, 18.55), 0.15, 0.18, "dark", rot=(0, 18 * s, 0), segments=8)
    bp.to_object(armature=arm, bone="backpack", bevel=0.05)


def build_arm(m, arm, side, s):
    sh = mk.PartBuilder(f"Shoulder.{side}", m)
    sh.cylinder((3.3 * s, 0, 17.4), 0.6, 0.8, "frame", rot=(0, 90, 0), segments=8)
    # Shoulder block: rounded top seen from the side (drum along X), flat armour
    # plates front and back, a navy outer face and a yellow stripe.
    sh.cylinder((4.15 * s, 0, 17.95), 1.25, 2.1, "white", rot=(0, 90, 0), segments=8)
    sh.tbox((4.15 * s, 0, 17.05), (1.9, 2.9), (2.1, 3.1), 0.7, "white")
    for y in (1.42, -1.42):
        sh.tbox((4.15 * s, y, 17.6), (2.0, 0.28), (1.7, 0.22), 1.7, "navy")
    sh.box((4.15 * s, 1.58, 17.0), (1.4, 0.06, 0.16), "yellow")
    sh.cylinder((5.22 * s, 0, 17.8), 0.85, 0.08, "navy", rot=(0, 90, 0), segments=8)
    sh.tbox((4.15 * s, 0, 19.2), (1.2, 1.4), (0.8, 1.0), 0.15, "frame")
    sh.to_object(armature=arm, bone=f"shoulder.{side}", bevel=0.05)

    ua = mk.PartBuilder(f"UpperArm.{side}", m)
    ua.cylinder((3.9 * s, 0, 15.55), 0.46, 2.9, "frame", segments=8)
    ua.tbox((4.2 * s, 0, 15.5), (0.3, 0.95), (0.3, 1.0), 2.2, "white")
    ua.cylinder((3.9 * s, 0, 13.85), 0.46, 1.0, "frame", rot=(0, 90, 0), segments=8)
    ua.tbox((3.9 * s, -0.4, 13.9), (0.9, 0.5), (0.8, 0.4), 0.9, "white")
    ua.to_object(armature=arm, bone=f"upper_arm.{side}", bevel=0.04)

    fa = mk.PartBuilder(f"Forearm.{side}", m)
    # Tapered forearm armour, wider at the elbow.
    fa.cylinder((3.9 * s, 0.05, 11.95), 0.6, 3.3, "white", segments=8, radius_top=0.78)
    fa.box((4.62 * s, 0.05, 12.2), (0.08, 0.75, 2.0), "navy")
    fa.box((4.66 * s, 0.05, 11.6), (0.06, 0.5, 0.5), "dark")
    fa.box((3.9 * s, 0.72, 12.9), (0.8, 0.08, 0.25), "red")
    fa.cylinder((3.9 * s, 0.05, 10.25), 0.55, 0.25, "frame", segments=8)
    fa.to_object(armature=arm, bone=f"forearm.{side}", bevel=0.04)

    hd = mk.PartBuilder(f"Hand.{side}", m)
    hd.box((3.9 * s, 0.1, 9.75), (0.62, 0.85, 0.75), "frame")
    for i, y in enumerate((0.4, 0.15, -0.1, -0.35)):
        hd.box((3.9 * s, y + 0.1, 9.1 + 0.03 * i), (0.5, 0.2, 0.62), "dark", rot=(12, 0, 0))
    hd.box((3.55 * s, 0.45, 9.5), (0.18, 0.22, 0.5), "dark", rot=(0, 0, 15 * s))
    hd.box((4.22 * s, 0.1, 9.8), (0.06, 0.6, 0.5), "white")
    hd.to_object(armature=arm, bone=f"hand.{side}", bevel=0.02)


def build_leg(m, arm, side, s):
    sf = mk.PartBuilder(f"SkirtFront.{side}", m)
    sf.tbox((1.25 * s, 1.45, 12.2), (1.25, 0.25), (1.55, 0.3), 2.2, "white", rot=(12, 0, -4 * s))
    sf.tbox((1.25 * s, 1.64, 12.3), (0.9, 0.05), (1.15, 0.05), 1.4, "navy", rot=(12, 0, -4 * s))
    sf.to_object(armature=arm, bone=f"skirt_front.{side}", bevel=0.03)

    ss = mk.PartBuilder(f"SkirtSide.{side}", m)
    ss.tbox((2.6 * s, 0, 12.15), (0.25, 1.5), (0.3, 2.0), 2.3, "white", rot=(0, -12 * s, 0))
    ss.box((2.77 * s, 0, 11.7), (0.06, 0.9, 0.55), "dark", rot=(0, -12 * s, 0))
    ss.box((2.76 * s, 0, 12.6), (0.04, 1.2, 0.12), "navy", rot=(0, -12 * s, 0))
    ss.to_object(armature=arm, bone=f"skirt_side.{side}", bevel=0.03)

    sr = mk.PartBuilder(f"SkirtRear.{side}", m)
    sr.tbox((1.0 * s, -1.5, 12.3), (1.3, 0.28), (1.6, 0.3), 2.0, "navy", rot=(-14, 0, 0))
    sr.box((1.0 * s, -1.72, 11.6), (0.7, 0.06, 0.45), "dark", rot=(-14, 0, 0))
    sr.to_object(armature=arm, bone=f"skirt_rear.{side}", bevel=0.03)

    th = mk.PartBuilder(f"Thigh.{side}", m)
    th.cylinder((1.5 * s, 0, 9.8), 0.62, 4.0, "frame", segments=8, radius_top=0.72)
    th.tbox((1.5 * s, 0.62, 9.9), (0.95, 0.3), (1.15, 0.35), 3.0, "white")
    th.tbox((2.1 * s, 0, 9.7), (0.25, 1.1), (0.28, 1.3), 2.6, "white")
    th.to_object(armature=arm, bone=f"thigh.{side}", bevel=0.04)

    sh = mk.PartBuilder(f"Shin.{side}", m)
    sh.cylinder((1.5 * s, 0, 7.4), 0.6, 1.25, "frame", rot=(0, 90, 0), segments=8)
    # Knee armour: navy wedge pointing forward, white cap.
    sh.tbox((1.5 * s, 0.75, 7.35), (1.1, 0.5), (0.9, 0.75), 1.3, "navy", shift=(0, 0.15))
    sh.tbox((1.5 * s, 1.05, 7.85), (0.8, 0.3), (0.55, 0.2), 0.5, "white")
    # Shin: long and flaring toward the ankle, calf bulge behind.
    sh.tbox((1.5 * s, 0.15, 4.4), (1.95, 2.1), (1.35, 1.5), 5.0, "white")
    sh.tbox((1.5 * s, 1.15, 4.9), (0.9, 0.12), (0.6, 0.12), 3.0, "navy")
    sh.tbox((1.5 * s, -1.05, 3.6), (1.35, 0.9), (1.0, 0.6), 2.8, "white", shift=(0, -0.1))
    sh.box((1.5 * s, -1.55, 3.3), (0.8, 0.08, 1.4), "dark")
    sh.box((2.46 * s, 0.2, 2.8), (0.06, 0.8, 0.45), "yellow")
    sh.cylinder((1.5 * s, 0, 1.7), 0.5, 1.05, "frame", rot=(0, 90, 0), segments=8)
    sh.to_object(armature=arm, bone=f"shin.{side}", bevel=0.06)

    ft = mk.PartBuilder(f"Foot.{side}", m)
    ft.tbox((1.5 * s, 0.5, 0.5), (1.55, 3.6), (1.2, 2.5), 0.9, "navy", shift=(0, 0.3))
    ft.tbox((1.5 * s, 2.3, 0.4), (1.35, 1.0), (1.05, 0.55), 0.7, "white", shift=(0, -0.15))
    ft.tbox((1.5 * s, -1.25, 0.45), (1.25, 0.6), (1.05, 0.5), 0.85, "white")
    ft.tbox((1.5 * s, 0.2, 1.15), (1.3, 1.6), (1.0, 1.1), 0.5, "white")
    ft.to_object(armature=arm, bone=f"foot.{side}", bevel=0.05)


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
