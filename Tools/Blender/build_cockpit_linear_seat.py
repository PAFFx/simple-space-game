"""Builds the late-UC style linear-seat cockpit capsule as a GLB.

Run:  blender -b -P Tools/Blender/build_cockpit_linear_seat.py -- <output.glb> [--aperture EL,HALF_AZ,HALF_EL]

--aperture places the hatch opening in the shell (degrees, default 0,36,36 = straight
ahead): a door-shaped rectangle on the plane facing that elevation, half sizes as angles
(matching the panoramic screen's aperture). Suits whose door isn't ahead get a variant.

Origin = centre of the panoramic sphere (pilot eye is ~8 cm in front of it).
The panoramic screen itself is generated at runtime (radius 1.25 m); everything
here must stay inside that radius except the outer Shell and the SeatBoom root.

Animated controls (GripL/R, PedalL/R) are separate objects whose origin is the
pivot, so Godot can rotate them directly.
"""

import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import mesh_kit as mk  # noqa: E402

SHELL_RADIUS = 1.32
# Hatch opening in the shell: centre elevation and half sizes (deg); see --aperture.
APERTURE = [0.0, 36.0, 36.0]


def materials():
    return {
        "shell": mk.make_material("CP_Shell", (0.16, 0.17, 0.19), metallic=0.6, roughness=0.45),
        "frame": mk.make_material("CP_Frame", (0.10, 0.11, 0.13), metallic=0.5, roughness=0.5),
        "fabric": mk.make_material("CP_SeatFabric", (0.07, 0.07, 0.08), roughness=0.9),
        "blue": mk.make_material("CP_SeatBlue", (0.08, 0.13, 0.30), roughness=0.8),
        "grip": mk.make_material("CP_Grip", (0.05, 0.05, 0.05), roughness=0.7),
        "yellow": mk.make_material("CP_AccentYellow", (0.95, 0.70, 0.08), roughness=0.4),
        "red": mk.make_material("CP_AccentRed", (0.75, 0.08, 0.08), roughness=0.4),
        "strip": mk.make_material("CP_LightStrip", (0.1, 0.3, 0.5), emission=(0.3, 0.75, 1.0), strength=3.0),
        "screen": mk.make_material("CP_Screen", (0.01, 0.03, 0.05), emission=(0.04, 0.18, 0.32), strength=1.0),
    }


def build_shell(m):
    """Outer capsule (outward normals) with the hatch aperture cut out of the front."""
    shell = mk.PartBuilder("Shell", m)
    shell.sphere((0, 0, 0), SHELL_RADIUS, "shell", segments=48, rings=24)
    el0, ha, he = (math.radians(a) for a in APERTURE)
    doomed = []
    for f in shell.bm.faces:
        c = f.calc_center_median() / SHELL_RADIUS
        # Into the aperture's frame (its centre straight ahead), then test the half sizes.
        y = c.y * math.cos(el0) + c.z * math.sin(el0)
        z = -c.y * math.sin(el0) + c.z * math.cos(el0)
        if y > 0.0 and abs(c.x / y) < math.tan(ha) and abs(z / y) < math.tan(he):
            doomed.append(f)
    bmesh.ops.delete(shell.bm, geom=doomed, context="FACES")

    # Portal frame around the aperture, between the screen (r 1.25) and the shell, so it
    # shows only through the open hatch (inside the screen it floated in the pilot's view).
    t = 0.07
    d = 1.285
    hw, hh = d * math.tan(ha), d * math.tan(he)
    rot = (APERTURE[0], 0.0, 0.0)

    def at(x, y, z):  # rotate an aperture-frame point up/down to the aperture's elevation
        return (x, y * math.cos(el0) - z * math.sin(el0), y * math.sin(el0) + z * math.cos(el0))

    shell.box(at(0, d, hh), (2 * hw + 0.1, 0.045, t), "frame", rot=rot)
    shell.box(at(0, d, -hh), (2 * hw + 0.1, 0.045, t), "frame", rot=rot)
    for s in (1.0, -1.0):
        shell.box(at(hw * s, d, 0), (t, 0.045, 2 * hh + 0.07), "frame", rot=rot)
    shell.box(at(0, d - 0.01, hh - 0.035), (1.4 * hw, 0.012, 0.012), "strip", rot=rot)
    shell.to_object(bevel=0.01)

    # Inner hatch door: two halves just outside the screen that slide apart sideways
    # (InnerDoorL / InnerDoorR, Godot slides them along x).
    di = 1.27
    iw, ih = di * math.tan(ha), di * math.tan(he)
    for side, s in (("L", -1.0), ("R", 1.0)):
        door = mk.PartBuilder(f"InnerDoor{side}", m)
        door.box((0, 0, 0), (iw, 0.02, 2 * ih), "shell", rot=rot)
        door.box(tuple(v * 1.0 for v in (0.0, -0.012, 0.0)), (0.012, 0.004, 2 * ih * 0.9), "strip", rot=rot)
        door.to_object(location=at(iw * 0.5 * s, di, 0), bevel=0.004)


def build_seat(m):
    seat = mk.PartBuilder("Seat", m)
    seat.tbox((0, -0.05, -0.74), (0.46, 0.5), (0.5, 0.5), 0.1, "fabric")
    for s in (1.0, -1.0):
        seat.box((0.25 * s, -0.05, -0.68), (0.06, 0.5, 0.12), "fabric")
        seat.box((0.21 * s, -0.37, -0.38), (0.07, 0.11, 0.6), "fabric", rot=(12, 0, 0))
        seat.box((0.27 * s, -0.02, -0.75), (0.012, 0.3, 0.012), "strip")
    seat.box((0, -0.36, -0.4), (0.4, 0.1, 0.66), "fabric", rot=(12, 0, 0))
    seat.box((0, -0.305, -0.4), (0.16, 0.02, 0.55), "blue", rot=(12, 0, 0))
    seat.box((0, -0.24, 0.0), (0.28, 0.1, 0.26), "fabric")
    seat.box((0, -0.19, 0.0), (0.12, 0.012, 0.18), "blue")
    seat.to_object(bevel=0.012)
    # The seat swivels on a fixed base on the boom (the seat and right armrest turn to
    # clear the way to the hatch; the left armrest is fixed to the base).
    base = mk.PartBuilder("SeatBase", m)
    base.box((0, -0.1, -0.86), (0.3, 0.4, 0.14), "frame")
    base.cylinder((0, -0.05, -0.79), 0.13, 0.03, "grip", segments=20)
    base.to_object(bevel=0.01)

    boom = mk.PartBuilder("SeatBoom", m)
    boom.box((0, -0.85, -0.55), (0.18, 0.95, 0.14), "frame")
    boom.box((0, -0.85, -0.47), (0.04, 0.9, 0.012), "strip")
    boom.box((0, -0.42, -0.62), (0.22, 0.12, 0.3), "frame")
    boom.to_object(bevel=0.01)


EYE = Vector((0.0, 0.08, 0.0))
# Main monitor centre and size; the sub monitors (smaller) hang off its lower side edges,
# turned toward the pilot. Blender axes: x right, y forward, z up.
MAIN_CENTRE = Vector((0.0, 0.58, -0.44))
MAIN_SIZE = (0.44, 0.30)
SUB_SIZE = (0.17, 0.125)
SUB_TURN_DEG = 35.0
BEZEL = 0.014
# Seat swing group: the seat, pedals, footrest, right armrest (console, grip, hatch lever)
# and the main + right monitors turn together about a vertical axis through the seat to
# clear the way to the hatch (Godot drives it). The left armrest and left monitor stay.
SEAT_PIVOT = (0.0, -0.05, -0.6)
# Console tops in front of the grips (flat, y 0.17..0.28): the switch panel (left) and
# the hatch lever (right) lie flush on them.
FACE_CENTRE_Y, FACE_CENTRE_Z, FACE_TILT = 0.222, -0.43, 90.0


def _frame(right, normal, up):
    """4x4 placing local x/y/z on right / normal / -up (quads face local +Y with their
    texture top at local -Z after the flip Godot applies; see CockpitDisplays)."""
    m = Matrix((right, normal, -up)).transposed().to_4x4()
    return m


def _place(pb, matrix, build):
    """Runs build() (geometry at the origin) and moves the new faces by `matrix`."""
    before = set(pb.bm.faces)
    build()
    new = [f for f in pb.bm.faces if f not in before]
    bmesh.ops.transform(pb.bm, matrix=matrix, verts=list({v for f in new for v in f.verts}))


def _strut(pb, a, b, size, mat):
    """Box of cross-section `size` from point a to point b."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    side = axis.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(axis)
    m = Matrix.Translation((a + b) * 0.5) @ Matrix((side, axis, up)).transposed().to_4x4()
    _place(pb, m, lambda: pb.box((0, 0, 0), (size, (b - a).length, size), mat))


def _monitor(name, m, centre, right, normal, up, size):
    """Bezel box and screen quad (`Screen<name>`) facing `normal`. Returns both objects."""
    bezel = mk.PartBuilder(f"Bezel{name}", m)
    frame = Matrix.Translation(centre - normal * 0.012) @ _frame(right, normal, up)
    _place(bezel, frame, lambda: bezel.box((0, 0, 0), (size[0] + 2 * BEZEL, 0.02, size[1] + 2 * BEZEL), "frame"))
    bezel_obj = bezel.to_object(bevel=0.005)
    scr = mk.PartBuilder(f"Screen{name}", m)
    _place(scr, Matrix.Translation(centre) @ _frame(right, normal, up),
           lambda: scr.quad((0, 0, 0), size[0], size[1], "screen"))
    return bezel_obj, scr.to_object()


def _face_matrix(s):
    """Frame of a console's front face: x right, y forward along the face, z out of it."""
    t = math.radians(FACE_TILT - 90.0)
    fwd = Vector((0, math.cos(t), math.sin(t)))
    out = Vector((0, -math.sin(t), math.cos(t)))
    return Matrix.Translation((0.36 * s, FACE_CENTRE_Y, FACE_CENTRE_Z + 0.002)) @ \
        Matrix((Vector((1, 0, 0)), fwd, out)).transposed().to_4x4()


def build_consoles(m):
    groups = {}
    for side, s in (("R", 1.0), ("L", -1.0)):
        con = mk.PartBuilder(f"Console{side}", m)
        con.box((0.34 * s, -0.02, -0.5), (0.13, 0.55, 0.07), "frame")
        con.tbox((0.36 * s, 0.27, -0.48), (0.2, 0.24), (0.18, 0.2), 0.1, "frame")
        con.box((0.36 * s, 0.27, -0.545), (0.16, 0.2, 0.03), "grip")
        con.box((0.44 * s, 0.27, -0.47), (0.012, 0.18, 0.012), "strip")
        objs = [con.to_object(bevel=0.008)]

        # Grip pivot sits on top of the console pod.
        grip = mk.PartBuilder(f"Grip{side}", m)
        grip.cylinder((0, 0, 0.015), 0.045, 0.03, "frame")
        grip.cylinder((0, 0, 0.095), 0.028, 0.13, "grip", radius_top=0.032)
        grip.box((0, -0.005, 0.165), (0.055, 0.06, 0.02), "grip")
        grip.box((0, -0.01, 0.178), (0.018, 0.018, 0.012), "yellow")
        grip.box((0.015 * s, 0.015, 0.178), (0.012, 0.012, 0.01), "red")
        grip.box((0, 0.033, 0.12), (0.014, 0.012, 0.035), "red")
        objs.append(grip.to_object(location=(0.36 * s, 0.33, -0.43), bevel=0.004))
        groups[side] = objs

        pedal = mk.PartBuilder(f"Pedal{side}", m)
        pedal.box((0, 0.1, 0.03), (0.1, 0.24, 0.022), "grip", rot=(25, 0, 0))
        pedal.box((0, 0.1, 0.045), (0.07, 0.15, 0.006), "frame", rot=(25, 0, 0))
        pedal.to_object(location=(0.13 * s, 0.45, -1.0), bevel=0.004)

    # Brackets joining the armrests to the seat: the right one to the swivelling seat
    # (they turn together), the left one, an L under the cushion and up outside the seat
    # side, to the fixed base.
    right = mk.PartBuilder("ArmrestBracketR", m)
    right.box((0.305, -0.04, -0.578), (0.055, 0.32, 0.09), "frame")
    groups["R"].append(right.to_object(bevel=0.006))
    left = mk.PartBuilder("ArmrestBracketL", m)
    left.box((-0.24, -0.1, -0.825), (0.2, 0.08, 0.04), "frame")
    left.box((-0.325, -0.1, -0.68), (0.04, 0.08, 0.29), "frame")
    left.to_object(bevel=0.006)

    # Left console face: mount for Godot's switch panel (its local +Y out of the face,
    # -Z forward along it once in Godot).
    mount = bpy.data.objects.new("SwitchPanelMount", None)
    bpy.context.scene.collection.objects.link(mount)
    mount.matrix_world = _face_matrix(-1.0)
    plate = mk.PartBuilder("SwitchPanelPlate", m)
    _place(plate, _face_matrix(-1.0), lambda: plate.box((0, 0, -0.003), (0.15, 0.1, 0.006), "grip"))
    groups["L"].append(plate.to_object(bevel=0.002))
    return groups


def build_footrest_and_mfd(m, groups):
    rest = mk.PartBuilder("Footrest", m)
    rest.box((0, 0.24, -0.9), (0.08, 0.5, 0.06), "frame", rot=(-18, 0, 0))
    rest.box((0, 0.46, -1.0), (0.42, 0.06, 0.05), "frame")
    rest.to_object(bevel=0.006)

    # Displays after the Xi Gundam's: a large main monitor ahead (situational awareness)
    # with two small sub monitors hinged to its lower side edges, turned toward the pilot
    # (left: engines and fuel, right: target). No legs: the main and right sub ride an arm
    # from the right armrest, the left sub one from the left; the arms meet the backs.
    normal = (EYE - MAIN_CENTRE).normalized()
    right = Vector((1, 0, 0))
    up = right.cross(normal) * -1.0
    up = up if up.z > 0 else -up
    hw, hh = MAIN_SIZE[0] * 0.5, MAIN_SIZE[1] * 0.5
    main = _monitor("Centre", m, MAIN_CENTRE, right, normal, up, MAIN_SIZE)
    groups["R"].extend(main)
    phi = math.radians(SUB_TURN_DEG)
    for side, s in (("L", -1.0), ("R", 1.0)):
        outward = right * (s * math.cos(phi)) + normal * math.sin(phi)
        sub_normal = normal * math.cos(phi) - right * (s * math.sin(phi))
        sub_right = outward if s > 0 else -outward
        hinge = MAIN_CENTRE + right * (s * (hw + BEZEL)) - up * (hh - SUB_SIZE[1] * 0.5 - BEZEL)
        centre = hinge + outward * (SUB_SIZE[0] * 0.5 + 2 * BEZEL)
        sub = _monitor("Left" if s < 0 else "Right", m, centre, sub_right, sub_normal, up, SUB_SIZE)
        groups[side].extend(sub)
        # Hinge blocks joining the sub to the main.
        hinge_obj = mk.PartBuilder(f"Hinge{side}", m)
        for k in (-1.0, 1.0):
            p = hinge + outward * BEZEL + up * (k * SUB_SIZE[1] * 0.3) - normal * 0.02
            hinge_obj.box(tuple(p), (0.018, 0.024, 0.026), "grip")
        groups[side].append(hinge_obj.to_object())
        # Arm from the armrest's front-inner corner to the back of the monitor.
        arm = mk.PartBuilder(f"DisplayArm{side}", m)
        # It meets the monitor's bottom edge from below and behind, so from the seat it
        # stays under the screens instead of crossing them.
        bottom = (centre - up * (SUB_SIZE[1] * 0.5 + BEZEL)) if s < 0 else \
            (MAIN_CENTRE + right * (hw * 0.55) - up * (hh + BEZEL))
        _strut(arm, (0.28 * s, 0.34, -0.48), tuple(bottom - normal * 0.035 - up * 0.01), 0.028, "frame")
        groups[side].append(arm.to_object(bevel=0.004))


def build_hatch_lever(m, groups):
    """Yellow/black striped pull handle on the right console's front face (HatchHandle,
    origin on its pivot): pull it up toward the pilot to open the hatch."""
    base = mk.PartBuilder("HatchLeverBase", m)
    _place(base, _face_matrix(1.0), lambda: base.box((0, 0.0, 0.004), (0.06, 0.09, 0.008), "grip"))
    groups["R"].append(base.to_object(bevel=0.002))
    handle = mk.PartBuilder("HatchHandle", m)
    # Built in the face frame (x right, y forward along the face, z out), pivot at origin.
    for k in (-1.0, 1.0):
        handle.box((0.022 * k, 0.025, 0.012), (0.008, 0.05, 0.008), "yellow")
    n = 6
    for i in range(n):
        x = -0.03 + 0.06 * (i + 0.5) / n
        handle.box((x, 0.05, 0.016), (0.06 / n, 0.016, 0.016), "yellow" if i % 2 == 0 else "grip")
    obj = handle.to_object(bevel=0.001)
    obj.matrix_world = _face_matrix(1.0) @ Matrix.Translation((0, -0.03, 0.008))
    groups["R"].append(obj)
    # Guard over it (HatchGuard, origin on its hinge at the base's forward edge): a
    # striped cover that flips forward, away from the pilot, to free the handle.
    guard = mk.PartBuilder("HatchGuard", m)
    gl, gw, gh = 0.095, 0.07, 0.034
    for i in range(5):
        guard.box((0, -gl * (i + 0.5) / 5, gh), (gw, gl / 5, 0.004), "yellow" if i % 2 == 0 else "grip")
    for k in (-1.0, 1.0):
        guard.box((gw * 0.5 * k, -gl * 0.5, gh * 0.5), (0.004, gl, gh), "yellow")
    guard.box((0, -gl, gh * 0.5), (gw, 0.004, gh), "yellow")
    gobj = guard.to_object(bevel=0.001)
    gobj.matrix_world = _face_matrix(1.0) @ Matrix.Translation((0, 0.046, 0.008))
    groups["R"].append(gobj)


def build_seat_pivot(groups):
    """Parents the seat swing group to SeatSwing so Godot can turn it."""
    pivot = bpy.data.objects.new("SeatSwing", None)
    bpy.context.scene.collection.objects.link(pivot)
    pivot.location = SEAT_PIVOT
    for name in ("Seat", "Footrest", "PedalL", "PedalR"):
        groups["R"].append(bpy.data.objects[name])
    for o in groups["R"]:
        _parent_keep(o, pivot)


def _parent_keep(obj, parent):
    """Parents `obj` to `parent`, keeping where it is."""
    bpy.context.view_layer.update()  # parent.matrix_world must reflect its location
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    obj.matrix_world = world


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "cockpit_linear_seat.glb"
    if "--aperture" in argv:
        APERTURE[:] = [float(v) for v in argv[argv.index("--aperture") + 1].split(",")]

    mk.reset_scene()
    m = materials()
    build_shell(m)
    build_seat(m)
    groups = build_consoles(m)
    build_footrest_and_mfd(m, groups)
    build_hatch_lever(m, groups)
    build_seat_pivot(groups)

    for obj in bpy.data.objects:
        obj.select_set(False)
    mk.export_glb(os.path.abspath(out), skins=False)
    print(f"[build_cockpit_linear_seat] exported {out}")


main()
