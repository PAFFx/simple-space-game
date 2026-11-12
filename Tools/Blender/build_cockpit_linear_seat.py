"""Builds the late-UC style linear-seat cockpit capsule as a GLB.

Run:  blender -b -P Tools/Blender/build_cockpit_linear_seat.py -- <output.glb>

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

import mesh_kit as mk  # noqa: E402

SHELL_RADIUS = 1.32
APERTURE_HALF_DEG = 36.0


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
    limit = math.radians(APERTURE_HALF_DEG)
    doomed = []
    for f in shell.bm.faces:
        c = f.calc_center_median()
        az = math.atan2(c.x, c.y)
        el = math.asin(max(-1.0, min(1.0, c.z / SHELL_RADIUS)))
        if abs(az) < limit and abs(el) < limit:
            doomed.append(f)
    bmesh.ops.delete(shell.bm, geom=doomed, context="FACES")

    # Portal frame around the aperture (visible from outside and from the seat).
    t = 0.07
    shell.box((0, 1.12, 0.80), (1.70, 0.28, t), "frame")
    shell.box((0, 1.12, -0.80), (1.70, 0.28, t), "frame")
    for s in (1.0, -1.0):
        shell.box((0.82 * s, 1.12, 0), (t, 0.28, 1.67), "frame")
    shell.box((0, 1.04, 0.765), (1.2, 0.02, 0.012), "strip")
    shell.to_object(bevel=0.01)


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
    seat.box((0, -0.1, -0.86), (0.3, 0.4, 0.14), "frame")
    seat.to_object(bevel=0.012)

    boom = mk.PartBuilder("SeatBoom", m)
    boom.box((0, -0.85, -0.55), (0.18, 0.95, 0.14), "frame")
    boom.box((0, -0.85, -0.47), (0.04, 0.9, 0.012), "strip")
    boom.box((0, -0.42, -0.62), (0.22, 0.12, 0.3), "frame")
    boom.to_object(bevel=0.01)


def build_consoles(m):
    for side, s in (("R", 1.0), ("L", -1.0)):
        con = mk.PartBuilder(f"Console{side}", m)
        con.box((0.34 * s, -0.02, -0.5), (0.13, 0.55, 0.07), "frame")
        con.tbox((0.36 * s, 0.27, -0.48), (0.2, 0.24), (0.18, 0.2), 0.1, "frame")
        con.box((0.36 * s, 0.27, -0.545), (0.16, 0.2, 0.03), "grip")
        con.box((0.44 * s, 0.27, -0.47), (0.012, 0.18, 0.012), "strip")
        for i in range(3):
            con.box(((0.30 + 0.035 * i) * s, 0.16, -0.425), (0.022, 0.022, 0.012), "yellow" if i == 1 else "grip")
        con.to_object(bevel=0.008)

        scr = mk.PartBuilder(f"ScreenConsole{side}", m)
        scr.quad((0.36 * s, 0.2, -0.428), 0.14, 0.09, "screen", rot=(110, 0, 0))
        scr.to_object()

        # Grip pivot sits on top of the console pod.
        grip = mk.PartBuilder(f"Grip{side}", m)
        grip.cylinder((0, 0, 0.015), 0.045, 0.03, "frame")
        grip.cylinder((0, 0, 0.095), 0.028, 0.13, "grip", radius_top=0.032)
        grip.box((0, -0.005, 0.165), (0.055, 0.06, 0.02), "grip")
        grip.box((0, -0.01, 0.178), (0.018, 0.018, 0.012), "yellow")
        grip.box((0.015 * s, 0.015, 0.178), (0.012, 0.012, 0.01), "red")
        grip.box((0, 0.033, 0.12), (0.014, 0.012, 0.035), "red")
        grip.to_object(location=(0.36 * s, 0.33, -0.43), bevel=0.004)

        pedal = mk.PartBuilder(f"Pedal{side}", m)
        pedal.box((0, 0.1, 0.03), (0.1, 0.24, 0.022), "grip", rot=(25, 0, 0))
        pedal.box((0, 0.1, 0.045), (0.07, 0.15, 0.006), "frame", rot=(25, 0, 0))
        pedal.to_object(location=(0.13 * s, 0.45, -1.0), bevel=0.004)


def build_footrest_and_mfd(m):
    rest = mk.PartBuilder("Footrest", m)
    rest.box((0, 0.24, -0.9), (0.08, 0.5, 0.06), "frame", rot=(-18, 0, 0))
    rest.box((0, 0.46, -1.0), (0.42, 0.06, 0.05), "frame")
    rest.box((0, 0.6, -0.82), (0.05, 0.05, 0.36), "frame", rot=(-20, 0, 0))
    rest.to_object(bevel=0.006)

    # Three displays in front, after the Xi Gundam's: a large centre tablet low ahead
    # (situational awareness) and a screen either side on an arm (left: engines and fuel,
    # right: target). Each faces the pilot's eye; Godot paints them (CockpitDisplays).
    for name, center, size, rot in DISPLAYS:
        bezel = mk.PartBuilder(f"Bezel{name}", m)
        bezel.box(center, (size[0] + 0.03, 0.022, size[1] + 0.03), "frame", rot=rot)
        bezel.to_object(bevel=0.006)
        scr = mk.PartBuilder(f"Screen{name}", m)
        # A hair in front of the bezel, toward the eye.
        eye = (0.0, 0.08, 0.0)
        d = [eye[i] - center[i] for i in range(3)]
        n = math.sqrt(sum(x * x for x in d))
        front = tuple(center[i] + d[i] / n * 0.012 for i in range(3))
        scr.quad(front, size[0], size[1], "screen", rot=rot)
        scr.to_object()

    arms = mk.PartBuilder("DisplayArms", m)
    arms.box((0, 0.6, -0.68), (0.06, 0.05, 0.22), "frame", rot=(-20, 0, 0))
    for s in (1.0, -1.0):
        arms.box((0.31 * s, 0.46, -0.42), (0.035, 0.035, 0.2), "frame", rot=(-25, 0, 0))
    arms.to_object(bevel=0.005)


# name, centre (Blender: x right, y forward, z up; eye at y 0.08), size (w, h), rotation
# turning the quad's +Y face toward the eye.
DISPLAYS = [
    ("Centre", (0.0, 0.62, -0.5), (0.40, 0.28), (137.0, 0.0, 0.0)),
    ("Left", (-0.33, 0.55, -0.30), (0.22, 0.16), (152.6, 0.0, 35.0)),
    ("Right", (0.33, 0.55, -0.30), (0.22, 0.16), (152.6, 0.0, -35.0)),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "cockpit_linear_seat.glb"

    mk.reset_scene()
    m = materials()
    build_shell(m)
    build_seat(m)
    build_consoles(m)
    build_footrest_and_mfd(m)

    for obj in bpy.data.objects:
        obj.select_set(False)
    mk.export_glb(os.path.abspath(out), skins=False)
    print(f"[build_cockpit_linear_seat] exported {out}")


main()
