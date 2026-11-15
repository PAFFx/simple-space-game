"""Capsule shell shared by the linear-seat cockpit build scripts: the outer sphere with the
hatch opening cut out, the portal frame around it and the two inner door halves."""

import math

import bmesh

import mesh_kit as mk

SHELL_RADIUS = 1.32


def build_shell(m, aperture):
    """`aperture` = (centre elevation, half azimuth, half elevation) in degrees.
    Needs the materials "shell", "frame" and "strip"."""
    shell = mk.PartBuilder("Shell", m)
    shell.sphere((0, 0, 0), SHELL_RADIUS, "shell", segments=48, rings=24)
    el0, ha, he = (math.radians(a) for a in aperture)
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
    rot = (aperture[0], 0.0, 0.0)

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
        door.box((0.0, -0.012, 0.0), (0.012, 0.004, 2 * ih * 0.9), "strip", rot=rot)
        door.to_object(location=at(iw * 0.5 * s, di, 0), bevel=0.004)
