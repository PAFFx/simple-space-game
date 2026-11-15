"""Builds the RX-93's cockpit (linear seat v2) as a GLB: a contoured adult-size seat on the
linear-seat boom with a fold-down jump seat behind it, ball controllers on the
armrest decks, a three-panel monitor array and sliding foot pedals.

Run:  blender -b -P Tools/Blender/build_cockpit_linear_seat_v2.py -- <output.glb> [--aperture EL,HALF_AZ,HALF_EL]

Origin = centre of the panoramic sphere; the pilot's eye is 8 cm in front of it. The seat
is a normal adult seat; what is fitted to the pilot is where it stands and how its
adjustable parts are set (cushion height, headrest slide, armrest decks, pedal carriages),
so that her eye is at the centre and she reaches the controls. The pilot model is small
(about 1.40 m, hip to eye 0.52 m, shoulder to wrist 0.37 m); her joints are below (PILOT).
Everything except the Shell and the SeatBoom root stays inside the screen radius (1.25 m).

Node names are the contract with the Godot components (same as the linear seat):
  SeatSwing            everything that turns to clear the hatch (the whole seat unit)
  GripL / GripR        ball controller units (base, cradle, lever arm)
  BallL / BallR        the balls (children of the units), origin at their centre: the
                       part Godot turns
  PedalL / PedalR      origin on the heel hinge (Godot slides and tilts them)
  ScreenCentre/Left/Right, HatchHandle, HatchGuard, SwitchPanelMount, InnerDoorL/R
  HandL/R, FootL/R     empties: where the pilot's wrists and ankles go (children of the
                       grips and pedals, so they follow them)
  JumpSeat, JumpSeatCushion  the passenger's seat behind the pilot's: frame with back
                       pad, and the cushion (origin on its hinge, built folded up)
"""

import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import mesh_kit as mk  # noqa: E402
from cockpit_shell import build_shell  # noqa: E402

APERTURE = [0.0, 36.0, 36.0]

# PILOT: where the seated pilot's joints are (x for the right side).
EYE = Vector((0.0, 0.08, 0.0))
RECLINE = math.radians(12.0)
HIP = Vector((0.063, 0.09, -0.52))

# Seat (adult size): cushion 0.50 m wide and 0.40 m deep, back 0.60 m to the shoulders
# (below the pilot's eye, so she can look behind over it, beside the headrest).
SEAT_TOP = -0.60          # cushion surface under the hips
PAN_BACK = -0.01
PAN_DEPTH = 0.40
PAN_HALF = 0.25
BACK_ORIGIN = Vector((0.0, PAN_BACK, SEAT_TOP))   # crease between the cushion and the back
BACK_HEIGHT = 0.6
# Headrest slide: the pad's span up the back and how far it stands out of the back's plane.
HEAD_LOW, HEAD_HIGH, HEAD_PROUD = 0.5, 0.82, 0.05
SEAT_PIVOT = (0.0, 0.08, -0.72)

# Armrest decks: one level each side, x from the inner edge out, y back to front.
DECK_TOP = -0.405
DECK_X = (0.262, 0.52)
DECK_Y = (-0.1, 0.34)
CONSOLE_X, CONSOLE_Y = 0.425, 0.1
GRIP_PIVOT = Vector((0.305, 0.275, DECK_TOP))   # right; the ball centre is BALL_UP above
BALL_R = 0.042
BASE_H = 0.03
BALL_UP = BASE_H + BALL_R + 0.004
PEDAL_PIVOT = Vector((0.085, 0.4, -0.975))      # right heel hinge
PEDAL_TILT = math.radians(24.0)
RAIL_SLOPE = 0.0494 / 0.42                       # the pedal rail's rise per metre forward

MAIN_CENTRE = Vector((0.0, 0.62, -0.40))
MAIN_SIZE = (0.40, 0.28)
SUB_SIZE = (0.22, 0.16)
SUB_TURN_DEG = 35.0
BEZEL = 0.012


def materials():
    return {
        "shell": mk.make_material("CP_Shell", (0.16, 0.17, 0.19), metallic=0.6, roughness=0.45),
        "frame": mk.make_material("CP_Frame", (0.36, 0.375, 0.40), metallic=0.45, roughness=0.5),
        "dark": mk.make_material("CP_FrameDark", (0.15, 0.155, 0.17), metallic=0.5, roughness=0.5),
        "tube": mk.make_material("CP_Tube", (0.52, 0.535, 0.56), metallic=0.85, roughness=0.32),
        "fabric": mk.make_material("CP_SeatFabric", (0.055, 0.058, 0.066), roughness=0.92),
        "pad": mk.make_material("CP_SeatPad", (0.10, 0.105, 0.118), roughness=0.85),
        "grip": mk.make_material("CP_Grip", (0.035, 0.035, 0.038), roughness=0.65),
        "yellow": mk.make_material("CP_AccentYellow", (0.90, 0.64, 0.05), roughness=0.55),
        "jump": mk.make_material("CP_JumpSeatYellow", (0.86, 0.60, 0.05), roughness=0.85),
        "jump_dark": mk.make_material("CP_JumpSeatOchre", (0.62, 0.42, 0.04), roughness=0.88),
        "red": mk.make_material("CP_AccentRed", (0.75, 0.08, 0.08), roughness=0.4),
        "strip": mk.make_material("CP_LightStrip", (0.1, 0.3, 0.5), emission=(0.3, 0.75, 1.0), strength=3.0),
        "screen": mk.make_material("CP_Screen", (0.01, 0.03, 0.05), emission=(0.04, 0.18, 0.32), strength=1.0),
    }


# ── modelling helpers ────────────────────────────────────────────────────────

def axis_matrix(a, b):
    """Matrix placing local +Z along a→b, at their midpoint."""
    a, b = Vector(a), Vector(b)
    z = (b - a).normalized()
    x = z.cross(Vector((0, 0, 1)))
    if x.length < 1e-3:
        x = Vector((1, 0, 0))
    x.normalize()
    y = z.cross(x)
    return Matrix.Translation((a + b) * 0.5) @ Matrix((x, y, z)).transposed().to_4x4()


def frame_matrix(origin, right, fwd, up):
    """Matrix with local x/y/z on right / fwd / up."""
    return Matrix.Translation(origin) @ Matrix((right, fwd, up)).transposed().to_4x4()


class Part(mk.PartBuilder):
    """PartBuilder with rounded boxes, rods and tubes, an optional local frame
    (`self.frame`: geometry is built in it) and smooth shading with baked chamfers."""

    def __init__(self, name, materials):
        super().__init__(name, materials)
        self.frame = Matrix.Identity(4)

    def _finish_faces(self, faces, mat, matrix):
        return super()._finish_faces(faces, mat, self.frame @ matrix)

    def _absorb(self, tmp, mat, matrix):
        mesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(mesh)
        tmp.free()
        before = set(self.bm.faces)
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        return self._finish_faces([f for f in self.bm.faces if f not in before], mat, matrix)

    def rbox(self, center, size, mat, rot=None, r=0.012, seg=3):
        """Box with every edge rounded by r."""
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
        r = min(r, min(size) * 0.49)
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=r, segments=seg, profile=0.5, affect="EDGES")
        return self._absorb(tmp, mat, self._matrix(center, rot))

    def rod(self, a, b, radius, mat, segments=12, radius_b=None):
        a, b = Vector(a), Vector(b)
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segments, radius1=radius,
                                    radius2=radius if radius_b is None else radius_b, depth=(b - a).length)
        faces = list({f for v in res["verts"] for f in v.link_faces})
        return self._finish_faces(faces, mat, axis_matrix(a, b))

    def bar(self, a, b, size, mat):
        """Box of cross-section `size` (w, h) from a to b."""
        a, b = Vector(a), Vector(b)
        m = axis_matrix(a, b)
        before = set(self.bm.faces)
        self.box((0, 0, 0), (size[0], size[1], (b - a).length), mat)
        new = [f for f in self.bm.faces if f not in before]
        bmesh.ops.transform(self.bm, matrix=self.frame @ m @ self.frame.inverted(),
                            verts=list({v for f in new for v in f.verts}))

    def tube(self, points, radius, mat, closed=False, sides=3):
        """Round tube through `points`, corners rounded (a NURBS path)."""
        cu = bpy.data.curves.new("tmp", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = radius
        cu.bevel_resolution = sides
        cu.use_fill_caps = True
        cu.resolution_u = 5
        sp = cu.splines.new("NURBS")
        sp.points.add(len(points) - 1)
        for p, co in zip(sp.points, points):
            p.co = (*co, 1.0)
        sp.order_u = 3
        sp.use_cyclic_u = closed
        sp.use_endpoint_u = not closed
        obj = bpy.data.objects.new("tmp", cu)
        bpy.context.scene.collection.objects.link(obj)
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(obj)
        bpy.data.curves.remove(cu)
        before = set(self.bm.faces)
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        return self._finish_faces([f for f in self.bm.faces if f not in before], mat, Matrix.Identity(4))

    def surface(self, fn, nu, nv, thickness, back, mat_fn):
        """Padded shell: fn(u, v) (u −1..1, v 0..1) is its face; the body is that face
        moved `thickness` along `back`. mat_fn(u, v) names the face's material; the back
        and rim are "frame"."""
        grid = [[self.bm.verts.new(fn(-1.0 + 2.0 * i / nu, j / nv)) for i in range(nu + 1)] for j in range(nv + 1)]
        rear = [[self.bm.verts.new(v.co + back * thickness) for v in row] for row in grid]
        by_mat = {}

        def face(verts, mat, toward):
            f = self.bm.faces.new(verts)
            f.normal_update()
            if f.normal.dot(toward) < 0.0:
                f.normal_flip()
            by_mat.setdefault(mat, []).append(f)

        for j in range(nv):
            for i in range(nu):
                quad = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
                face(quad, mat_fn(-1.0 + 2.0 * (i + 0.5) / nu, (j + 0.5) / nv), -back)
                face([rear[j][i], rear[j][i + 1], rear[j + 1][i + 1], rear[j + 1][i]], "frame", back)
        rim = [(grid[0][i], grid[0][i + 1], rear[0][i + 1], rear[0][i], grid[1][i]) for i in range(nu)]
        rim += [(grid[nv][i], grid[nv][i + 1], rear[nv][i + 1], rear[nv][i], grid[nv - 1][i]) for i in range(nu)]
        rim += [(grid[j][0], grid[j + 1][0], rear[j + 1][0], rear[j][0], grid[j][1]) for j in range(nv)]
        rim += [(grid[j][nu], grid[j + 1][nu], rear[j + 1][nu], rear[j][nu], grid[j][nu - 1]) for j in range(nv)]
        for a, b, c, d, inside in rim:
            face([a, b, c, d], "frame", (a.co + b.co) * 0.5 - inside.co)
        for mat, faces in by_mat.items():
            for f in faces:
                f.material_index = self._slot(mat)
        bmesh.ops.transform(self.bm, matrix=self.frame, verts=[v for row in grid + rear for v in row])

    def ball(self, center, radius, mat, segments=24, rings=12, scale=(1, 1, 1)):
        faces = self.sphere((0, 0, 0), radius, mat, segments=segments, rings=rings)
        verts = list({v for f in faces for v in f.verts})
        m = self.frame @ Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*scale, 1.0)) @ self.frame.inverted()
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        return faces

    def to_object(self, location=(0, 0, 0), chamfer=0.0025, local=False, **kwargs):
        """Emits the object with origin `location`. Geometry is authored in world space,
        or round the origin with `local`."""
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        if chamfer > 0.0:
            hard = [e for e in self.bm.edges if len(e.link_faces) == 2
                    and e.calc_face_angle(0.0) > math.radians(50)]
            bmesh.ops.bevel(self.bm, geom=hard, offset=chamfer, segments=1, affect="EDGES", clamp_overlap=True)
        for f in self.bm.faces:
            f.smooth = True
        if not local:
            bmesh.ops.translate(self.bm, vec=-Vector(location), verts=self.bm.verts)
        obj = super().to_object(location=location, **kwargs)
        obj.data.set_sharp_from_angle(angle=math.radians(32))
        return obj


def empty(name, matrix, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = matrix
    if parent is not None:
        parent_keep(obj, parent)
    return obj


def parent_keep(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    obj.matrix_world = world


def mirror(v, s):
    return Vector((v[0] * s, v[1], v[2]))


# ── seat ─────────────────────────────────────────────────────────────────────

def back_frame():
    up = Vector((0, -math.sin(RECLINE), math.cos(RECLINE)))
    fwd = Vector((0, math.cos(RECLINE), math.sin(RECLINE)))
    return frame_matrix(BACK_ORIGIN, Vector((1, 0, 0)), fwd, up)


def bump(x, centre, width):
    return math.exp(-((x - centre) / width) ** 2)


def back_surface(u, v):
    """The backrest's face in the back frame (u across −1..1, v up 0..1): hollowed
    across, a lumbar swell low down, wings at the shoulders."""
    z = 0.015 + v * BACK_HEIGHT
    half = 0.235 - 0.02 * bump(v, 0.38, 0.2) + 0.03 * bump(v, 0.8, 0.16) - 0.05 * max(0.0, v - 0.88) / 0.12
    wrap = (0.085 - 0.03 * v) * abs(u) ** 2.6
    y = 0.02 * bump(z, 0.17, 0.1) - 0.012 * bump(z, 0.42, 0.14) + wrap
    return Vector((u * half, y, z))


def pan_surface(u, v):
    """The seat cushion's top (u across, v from the back to the front edge): raised
    sides, a slight rise under the thighs, a waterfall front."""
    y = PAN_BACK + v * PAN_DEPTH
    side = 0.05 * abs(u) ** 3 * (1.0 - 0.5 * max(0.0, v - 0.7) / 0.3)
    z = SEAT_TOP - 0.012 * bump(v, 0.18, 0.2) + 0.012 * bump(v, 0.7, 0.2) - 0.07 * max(0.0, v - 0.84) ** 2 / 0.0256
    return Vector((u * (PAN_HALF - 0.012 * v), y, z + side))


def head_surface(u, v):
    """Headrest pad in the back frame: wraps round the back of the head."""
    z = HEAD_LOW + v * (HEAD_HIGH - HEAD_LOW)
    return Vector((u * 0.155, HEAD_PROUD + 0.065 * abs(u) ** 2.4 - 0.008 * bump(v, 0.5, 0.4), z))


def build_seat(m):
    seat = Part("Seat", m)
    top = SEAT_TOP

    def trim(u, v):
        return "fabric" if abs(u) < 0.5 else "pad"

    # Pan: contoured cushion on a grey bucket.
    seat.surface(pan_surface, 18, 16, 0.05, Vector((0, 0, -1)), trim)
    mid_y = PAN_BACK + PAN_DEPTH * 0.5
    seat.rbox((0, mid_y - 0.01, top - 0.075), (PAN_HALF * 2 + 0.03, PAN_DEPTH + 0.01, 0.06), "frame", r=0.022)
    for s in (1.0, -1.0):
        seat.rbox(((PAN_HALF + 0.012) * s, mid_y - 0.02, top - 0.025), (0.018, PAN_DEPTH - 0.05, 0.1), "frame", r=0.007)
    # Pull handle between the knees (as on an ejection seat).
    fy = PAN_BACK + PAN_DEPTH
    seat.tube([(-0.035, fy - 0.035, top - 0.06), (-0.035, fy + 0.012, top - 0.025), (0.035, fy + 0.012, top - 0.025),
               (0.035, fy - 0.035, top - 0.06)], 0.008, "yellow")
    for i in range(5):
        x = -0.024 + 0.012 * i
        if i % 2 == 0:
            seat.rod((x - 0.005, fy + 0.012, top - 0.0245), (x + 0.005, fy + 0.012, top - 0.0245), 0.0088, "grip")

    # Back, in its own reclined frame: x right, y out of the cushion, z up the back.
    seat.frame = back_frame()
    seat.surface(back_surface, 20, 26, 0.06, Vector((0, -1, 0)), trim)
    for i in range(4):                                       # ribbed pad under the headrest
        z = 0.47 + 0.03 * i
        seat.rbox((0, back_surface(0, (z - 0.015) / BACK_HEIGHT).y + 0.004, z), (0.2, 0.016, 0.024), "pad", r=0.007)
    # Pilot connectors on the upper back, for a normal suit's backpack: two plugs, two
    # ports and the latch block under them (low enough to lie under the pilot's back).
    for s in (1.0, -1.0):
        base = Vector((0.04 * s, back_surface(0.17 * s, 0.7).y, 0.44))
        seat.rod(base + Vector((0, -0.004, 0)), base + Vector((0.016 * s, 0.012, 0.03)), 0.011, "tube", 14)
        seat.rod(base + Vector((0.016 * s, 0.012, 0.03)), base + Vector((0.02 * s, 0.014, 0.036)), 0.008, "yellow", 12)
        port = Vector((0.036 * s, back_surface(0.15 * s, 0.6).y, 0.385))
        seat.rod(port - Vector((0, 0.004, 0)), port + Vector((0, 0.005, 0)), 0.012, "dark", 14)
        seat.rod(port, port + Vector((0, 0.0065, 0)), 0.006, "tube", 10)
    latch_y = back_surface(0, 0.5).y
    seat.rbox((0, latch_y + 0.004, 0.31), (0.05, 0.016, 0.085), "dark", r=0.006)
    seat.rbox((0, latch_y + 0.012, 0.33), (0.03, 0.008, 0.03), "frame", r=0.003)
    for s in (1.0, -1.0):
        # Harness: reel on the shoulder, yellow strap stowed down the bolster, buckle.
        x = 0.135 * s
        seat.rbox((x, back_surface(0.55 * s, 0.93).y + 0.006, BACK_HEIGHT - 0.05), (0.055, 0.02, 0.03), "dark", r=0.005)
        for k in range(6):
            v = 0.9 - 0.1 * k
            p = back_surface(0.56 * s, v)
            q = back_surface(0.56 * s, v - 0.1)
            seat.bar(p + Vector((0, 0.004, 0)), q + Vector((0, 0.004, 0)), (0.036, 0.005), "yellow")
        seat.rbox((x, back_surface(0.56 * s, 0.32).y + 0.01, 0.2), (0.046, 0.014, 0.04), "dark", r=0.004)
        seat.rbox((0.245 * s, 0.07, 0.05), (0.012, 0.08, 0.036), "yellow", rot=(-35, 0, 0), r=0.003)   # lap belt
    # Headrest: a wrapping pad between two slim cheek blocks (narrow, so the pilot can lean
    # out and look behind), on a slide (it sits low here for a small pilot; the rails run on up).
    seat.surface(head_surface, 12, 10, 0.05, Vector((0, -1, 0)), lambda u, v: "fabric" if abs(u) < 0.62 else "pad")
    hz = (HEAD_LOW + HEAD_HIGH) * 0.5
    for s in (1.0, -1.0):
        seat.rbox((0.158 * s, HEAD_PROUD + 0.005, hz), (0.034, 0.1, HEAD_HIGH - HEAD_LOW - 0.05), "frame", rot=(0, 0, -14 * s), r=0.016)
        seat.rod((0.1 * s, -0.045, HEAD_LOW - 0.04), (0.1 * s, -0.045, HEAD_HIGH + 0.1), 0.011, "tube")
    seat.rbox((0, -0.035, hz), (0.27, 0.07, HEAD_HIGH - HEAD_LOW + 0.02), "frame", r=0.02)
    # Head box above it: a cross drum between two blocks, with a grab loop on top.
    bz = HEAD_HIGH + 0.075
    seat.rbox((0, -0.05, bz), (0.3, 0.11, 0.1), "frame", r=0.02)
    seat.rod((-0.19, -0.05, bz), (0.19, -0.05, bz), 0.04, "dark", segments=20)
    for s in (1.0, -1.0):
        seat.rbox((0.165 * s, -0.05, bz), (0.035, 0.13, 0.12), "frame", r=0.012)
        seat.rod((0.19 * s, -0.05, bz), (0.202 * s, -0.05, bz), 0.028, "tube", segments=16)
    seat.tube([(-0.11, -0.01, bz + 0.045), (-0.11, 0.045, bz + 0.075), (0.11, 0.045, bz + 0.075),
               (0.11, -0.01, bz + 0.045)], 0.009, "yellow")
    # Rear: pack between the rails, webbing, ribs.
    seat.rbox((0, -0.105, 0.3), (0.24, 0.07, 0.3), "dark", r=0.016)
    seat.rbox((0, -0.144, 0.34), (0.12, 0.012, 0.15), "frame", r=0.004)
    for i in range(3):
        seat.rbox((0, -0.066, 0.1 + 0.22 * i), (0.44, 0.012, 0.036), "yellow", r=0.003)
    for s in (1.0, -1.0):
        for i in range(6):
            seat.rbox((0.18 * s, -0.068, 0.15 + 0.065 * i), (0.07, 0.012, 0.03), "dark", r=0.004)
    # Tube frame: a rail up each side of the back, joined by a hoop over the head box.
    rail = [(0.265, -0.07, -0.02), (0.265, -0.07, 0.56), (0.225, -0.09, 0.74), (0.225, -0.09, HEAD_HIGH + 0.14),
            (0.0, -0.09, HEAD_HIGH + 0.185)]
    seat.tube(rail + [(-x, y, z) for x, y, z in reversed(rail[:-1])], 0.015, "tube")
    seat.rod((-0.24, -0.085, 0.66), (0.24, -0.085, 0.66), 0.011, "tube")
    seat.frame = Matrix.Identity(4)
    parts = [seat.to_object()]

    # Fixed part: swivel under the pan and the boom to the capsule's rear wall.
    base = Part("SeatBase", m)
    px, py, pz = SEAT_PIVOT
    base.cylinder((px, py, pz - 0.035), 0.125, 0.05, "dark", segments=28)
    base.cylinder((px, py, pz - 0.068), 0.15, 0.022, "frame", segments=28)
    base.rbox((0, py - 0.02, pz - 0.115), (0.22, 0.32, 0.075), "frame", r=0.014)
    base.to_object()
    boom = Part("SeatBoom", m)
    boom.rbox((0, -0.68, pz - 0.12), (0.15, 1.24, 0.085), "frame", r=0.012)
    boom.rbox((0, -0.70, pz - 0.074), (0.035, 1.0, 0.01), "strip", r=0.002)
    for i in range(4):
        boom.rbox((0, -0.35 - 0.25 * i, pz - 0.12), (0.17, 0.03, 0.10), "dark", r=0.006)
    boom.to_object()
    collar = Part("SeatCollar", m)
    collar.cylinder((px, py, pz + 0.002), 0.11, 0.03, "frame", segments=28)
    collar.rbox((0, mid_y, top - 0.108), (0.3, 0.3, 0.025), "dark", r=0.008)
    parts.append(collar.to_object())
    return parts


JUMP_FOLD_DEG = 78.0      # the jump seat's cushion as built: folded up against its frame


def build_jump_seat(m):
    """The fold-down jump seat directly behind the pilot's seat, for a passenger (after
    the sketch): a backrest frame of two tube loops joined by rungs, leaning back, a
    yellow back pad on it, and a slim yellow bucket cushion hinged at its foot, stowed
    folded up (JumpSeatCushion, origin on the hinge: turn it −JUMP_FOLD_DEG about x to
    seat someone). Hung off the pilot seat's frame, so it turns with it."""
    js = Part("JumpSeat", m)
    top = SEAT_TOP - 0.03
    half, high = 0.225, 0.64               # frame half width, height above the cushion
    y0 = -0.6                              # the frame's foot
    lean = 0.13                            # how far its top leans back

    def at(x, z):                          # a point on the frame's plane (z above `top`)
        return Vector((x, y0 - lean * z / high, top + z))

    def loop(inset):
        lo, hi, w, r = -0.1 + inset, high - inset, half - inset, 0.075
        return [at(-w, lo), at(-w, hi - r), at(-w + r, hi), at(w - r, hi), at(w, hi - r), at(w, lo), at(0, lo)]

    js.tube(loop(0.0), 0.014, "tube", closed=True)
    js.tube(loop(0.06), 0.011, "tube", closed=True)
    # Rungs between the two loops, slanted like a truss.
    for i in range(6):
        z = 0.0 + 0.095 * i
        for s in (1.0, -1.0):
            js.rod(at(half * s, z), at((half - 0.06) * s, z + 0.05), 0.007, "tube", 8)
    for i in range(4):
        x = -0.12 + 0.08 * i
        js.rod(at(x, high), at(x + 0.03, high - 0.06), 0.007, "tube", 8)
        js.rod(at(x, -0.1), at(x + 0.03, -0.04), 0.007, "tube", 8)
    for s in (1.0, -1.0):
        # Floor loop forward to the pilot seat's bucket, and a strut up to its back rail.
        js.tube([at(half * s, -0.1), (half * s, y0 + 0.16, top - 0.1), (0.21 * s, -0.12, top - 0.075)], 0.013, "tube")
        js.rod(at(half * s, 0.42), (0.262 * s, -0.2, top + 0.44), 0.011, "tube")
        js.rod(at(half * s, 0.0), (half * s, y0 + 0.05, top - 0.03), 0.012, "dark", 12)    # hinge lugs
    js.rod((-half, y0 + 0.16, top - 0.1), (half, y0 + 0.16, top - 0.1), 0.011, "tube")

    def pad(u, v):                         # back pad, hollowed, a channel down its middle
        z = 0.2 + v * 0.36
        return at(u * 0.15, z) + Vector((0, 0.03 + 0.03 * abs(u) ** 2.4 - 0.008 * bump(u, 0.0, 0.22), 0))

    trim = lambda u, v: "jump" if abs(u) > 0.16 else "jump_dark"  # noqa: E731
    js.surface(pad, 14, 12, 0.028, Vector((0, -1, 0)), trim)
    parts = [js.to_object()]

    # Cushion, built flat (hinge along x through the origin, front toward +y), then
    # folded up: a slim bucket with raised sides and a channel down the middle.
    seat = Part("JumpSeatCushion", m)

    def cushion(u, v):
        return Vector((u * 0.18, 0.03 + v * 0.36,
                       0.03 + 0.045 * abs(u) ** 2.6 - 0.008 * bump(u, 0.0, 0.2) - 0.05 * max(0.0, v - 0.82) ** 2 / 0.0324))

    seat.surface(cushion, 14, 12, 0.032, Vector((0, 0, -1)), trim)
    seat.rbox((0, 0.2, -0.008), (0.3, 0.3, 0.014), "jump_dark", r=0.005)
    seat.rod((-0.2, 0, 0), (0.2, 0, 0), 0.013, "tube", 12)
    for s in (1.0, -1.0):
        seat.bar((0.165 * s, 0.0, 0.0), (0.165 * s, 0.34, -0.004), (0.014, 0.02), "tube")
    seat.rbox((0, 0.385, 0.0), (0.12, 0.016, 0.03), "dark", r=0.005)      # pull tab on the front edge
    obj = seat.to_object(local=True)
    obj.matrix_world = Matrix.Translation((0, y0 + 0.05, top - 0.03)) @ Matrix.Rotation(math.radians(JUMP_FOLD_DEG), 4, "X")
    parts.append(obj)
    return parts


# ── armrest decks, controllers ───────────────────────────────────────────────

def build_ball(side, s, m):
    """Ball controller: the unit (Grip<side>: base block, cradle and the lever arm running
    back along the armrest) sits on the deck, and the ball (Ball<side>, its origin at the
    ball's centre) turns in the cradle; Godot turns only the ball. The hand lies over the
    ball, fingers in the grooved slot round the front, thumb on the inner cheek with its
    three buttons. Returns (unit, ball)."""
    grip = Part(f"Ball{side}", m)
    centre = Vector((0, 0, 0))
    faces = grip.sphere((0, 0, 0), BALL_R, "frame", segments=48, rings=24)
    verts = list({v for f in faces for v in f.verts})
    slot_faces = set()
    cheek_faces = set()
    for v in verts:
        d = v.co.normalized()
        az = math.atan2(d.x, d.y)                      # 0 = front, ± toward the cheeks
        el = math.asin(max(-1.0, min(1.0, d.z)))
        flat = 0.80
        if abs(d.x) > flat:                            # cheeks: flat discs on both sides
            v.co.x = math.copysign(BALL_R * flat, d.x)
            cheek_faces.update(v.link_faces)
            continue
        # Slot: a band round the front, its upper lip scalloped into four finger grooves.
        in_az = abs(az) < math.radians(118)
        lip = math.radians(34) + math.radians(7) * math.cos(az * 4.0 + math.pi)
        lo = math.radians(-16)
        if in_az and lo < el < lip:
            edge = min(el - lo, lip - el) / math.radians(9)
            side_edge = (math.radians(118) - abs(az)) / math.radians(14)
            depth = 0.26 * min(1.0, edge) * min(1.0, side_edge)
            v.co *= 1.0 - depth
            if depth > 0.12:
                slot_faces.update(v.link_faces)
    grip.slots += ["grip", "dark"]
    for f in slot_faces:
        f.material_index = grip.slots.index("grip")
    for f in cheek_faces:
        if all(abs(v.co.x) > BALL_R * 0.79 for v in f.verts):
            f.material_index = grip.slots.index("dark")
    grip.rod(centre + Vector((0, 0, BALL_R - 0.004)), centre + Vector((0, 0, BALL_R + 0.003)), 0.009, "yellow", 16)
    inner = -s
    for by, bz, br, mat in ((0.012, 0.012, 0.0085, "red"), (-0.008, 0.004, 0.0075, "tube"), (0.006, -0.011, 0.0075, "tube")):
        c = centre + Vector((inner * BALL_R * 0.80, by, bz))
        grip.rod(c - Vector((inner * 0.002, 0, 0)), c + Vector((inner * 0.004, 0, 0)), br, mat, 14)
        grip.rod(c - Vector((inner * 0.002, 0, 0)), c + Vector((inner * 0.0015, 0, 0)), br + 0.0025, "grip", 14)
    # Trunnions on the cheeks: the axis the ball turns on.
    for k in (1.0, -1.0):
        grip.rod((k * BALL_R * 0.78, 0, -0.012), (k * (BALL_R * 0.8 + 0.006), 0, -0.012), 0.008, "tube", 12)
    ball = grip.to_object(location=mirror(GRIP_PIVOT, s) + Vector((0, 0, BALL_UP)), chamfer=0.0, local=True)

    # Base block under the ball, with the cradle the ball turns in, and the lever arm
    # running back from it, stepping down and inward (after the sketch), with the slide
    # switch on its top.
    unit = Part(f"Grip{side}", m)
    unit.rod((0, 0, BASE_H - 0.002), (0, 0, BALL_UP - BALL_R + 0.004), 0.019, "grip", 16, radius_b=0.026)
    for k in (1.0, -1.0):
        unit.bar((k * (BALL_R * 0.8 + 0.009), 0, BASE_H - 0.004), (k * (BALL_R * 0.8 + 0.009), 0, BALL_UP - 0.006), (0.016, 0.008), "dark")
    unit.rbox((0, 0.004, BASE_H * 0.5 + 0.002), (0.094, 0.084, BASE_H), "dark", r=0.008)
    unit.rbox((0.047 * s, 0.03, BASE_H * 0.5), (0.004, 0.016, 0.012), "red", r=0.001)
    unit.bar((-0.006 * s, -0.03, 0.014), (-0.014 * s, -0.1, 0.01), (0.044, 0.02), "dark")
    unit.rbox((-0.014 * s, -0.15, 0.01), (0.05, 0.11, 0.018), "dark", r=0.006)
    unit.rbox((-0.014 * s, -0.135, 0.0215), (0.016, 0.034, 0.008), "tube", r=0.002)
    unit.rbox((-0.014 * s, -0.2, 0.011), (0.036, 0.02, 0.022), "frame", r=0.004)
    unit_obj = unit.to_object(location=mirror(GRIP_PIVOT, s), chamfer=0.0015, local=True)
    parent_keep(ball, unit_obj)
    return unit_obj, ball


def build_arms(m):
    parts = []
    for side, s in (("R", 1.0), ("L", -1.0)):
        arm = Part(f"Armrest{side}", m)
        # One deck: the forearm lies along its inner strip with the controller at the
        # front of it, the side console (switch panel / hatch lever) on the outer part.
        x0, x1 = DECK_X
        cx, w = (x0 + x1) * 0.5 * s, x1 - x0
        y0, y1 = DECK_Y
        arm.rbox((cx, (y0 + y1) * 0.5, DECK_TOP - 0.024), (w, y1 - y0, 0.048), "frame", r=0.014)
        arm.rbox((cx, (y0 + y1) * 0.5 - 0.01, DECK_TOP - 0.058), (w - 0.06, y1 - y0 - 0.08, 0.03), "dark", r=0.01)
        arm.rbox((GRIP_PIVOT.x * s, y0 + 0.14, DECK_TOP + 0.003), (0.085, 0.24, 0.014), "pad", r=0.006)     # forearm pad
        arm.rbox((GRIP_PIVOT.x * s, GRIP_PIVOT.y - 0.045, DECK_TOP + 0.001), (0.094, 0.3, 0.004), "dark", r=0.0015)  # lever track
        arm.rbox((x1 * s - 0.004 * s, (y0 + y1) * 0.5, DECK_TOP - 0.02), (0.006, y1 - y0 - 0.06, 0.012), "strip", r=0.002)
        for i in range(4):                                 # hazard ticks along the front edge
            arm.rbox(((x0 + 0.1 + 0.035 * i) * s, y1 - 0.006, DECK_TOP - 0.022), (0.02, 0.004, 0.03), "yellow", r=0.001)
        # Carried by a beam from the back frame and a post from the seat bucket.
        arm.bar((x0 * s + 0.03 * s, y0 + 0.03, DECK_TOP - 0.05), (0.262 * s, -0.085, DECK_TOP - 0.05), (0.04, 0.04), "frame")
        arm.rod((0.262 * s, -0.11, DECK_TOP - 0.05), (0.262 * s, -0.06, DECK_TOP - 0.05), 0.026, "dark", 16)
        arm.bar(((x0 + 0.045) * s, 0.16, DECK_TOP - 0.06), ((PAN_HALF + 0.012) * s, 0.16, SEAT_TOP - 0.03), (0.03, 0.05), "frame")
        parts.append(arm.to_object())

        grip, ball = build_ball(side, s, m)
        parts.append(grip)
        # Wrist target, riding on the ball: behind it and a little above its centre, the
        # hand rising over the ball's back and top in line with the forearm (so the wrist
        # is straight at rest), turned a little inward; the fingers curl down into the
        # slot. Local +Y = fingers, +Z = back of the hand.
        rise, turn = math.radians(14), math.radians(8)
        fingers = Vector((-s * math.sin(turn) * math.cos(rise), math.cos(turn) * math.cos(rise), math.sin(rise)))
        back = (Vector((0, 0, 1)) - fingers * fingers.z).normalized()
        wrist = mirror(GRIP_PIVOT, s) + Vector((0.006 * s, -0.078, BALL_UP + 0.022))
        empty(f"Hand{side}", frame_matrix(wrist, fingers.cross(back), fingers, back), ball)
    return parts


def face_matrix(s):
    """Frame on a deck's outer part: x right, y forward, z out of it."""
    return Matrix.Translation((CONSOLE_X * s, CONSOLE_Y, DECK_TOP + 0.001))


def build_console_fittings(m):
    parts = []
    mount = empty("SwitchPanelMount", face_matrix(-1.0))
    parts.append(mount)
    plate = Part("SwitchPanelPlate", m)
    plate.frame = face_matrix(-1.0)
    plate.rbox((0, 0, -0.002), (0.152, 0.104, 0.006), "grip", r=0.002)
    parts.append(plate.to_object())

    # Hatch control on the right deck, after a fighter's canopy handle: a striped lever
    # lying forward in a guarded quadrant. Lift the guard (it flips forward), then pull the
    # lever up and back to unlock and open; push it down to close and lock.
    face = face_matrix(1.0)
    base = Part("HatchLeverBase", m)
    base.frame = face
    base.rbox((0, 0.0, 0.003), (0.075, 0.13, 0.008), "grip", r=0.002)
    for k in (-1.0, 1.0):                       # quadrant cheeks either side of the lever
        base.rbox((0.031 * k, -0.02, 0.016), (0.005, 0.06, 0.03), "frame", r=0.002)
    for i in range(6):                          # hazard ticks along the base's edges
        if i % 2 == 0:
            for k in (-1.0, 1.0):
                base.rbox((0.0345 * k, -0.055 + 0.022 * i, 0.0075), (0.006, 0.02, 0.002), "yellow", r=0.0005)
    parts.append(base.to_object())

    handle = Part("HatchHandle", m)             # origin on its pivot, lying toward +y
    for k in (-1.0, 1.0):
        handle.box((0.02 * k, 0.025, 0.012), (0.007, 0.056, 0.009), "frame")
    handle.rod((-0.027, 0.0, 0.012), (0.027, 0.0, 0.012), 0.007, "dark", 14)
    n = 6
    for i in range(n):
        x = -0.03 + 0.06 * (i + 0.5) / n
        handle.rod((x - 0.005, 0.05, 0.016), (x + 0.005, 0.05, 0.016), 0.0095, "yellow" if i % 2 == 0 else "grip", 14)
    obj = handle.to_object(chamfer=0.001)
    obj.matrix_world = face @ Matrix.Translation((0, -0.03, 0.008))
    parts.append(obj)

    guard = Part("HatchGuard", m)               # origin on its hinge at the forward edge
    gl, gw, gh = 0.098, 0.074, 0.036
    for i in range(5):
        guard.box((0, -gl * (i + 0.5) / 5, gh), (gw, gl / 5, 0.004), "yellow" if i % 2 == 0 else "grip")
    for k in (-1.0, 1.0):
        guard.box((gw * 0.5 * k, -gl * 0.5, gh * 0.5), (0.004, gl, gh), "red")
    guard.box((0, -gl, gh * 0.5), (gw, 0.004, gh), "red")
    guard.rod((-gw * 0.5, 0, 0.004), (gw * 0.5, 0, 0.004), 0.004, "frame", 10)
    gobj = guard.to_object(chamfer=0.001)
    gobj.matrix_world = face @ Matrix.Translation((0, 0.05, 0.008))
    parts.append(gobj)
    return parts


# ── legs: strut, rail, pedals ────────────────────────────────────────────────

def build_pedals(m):
    parts = []
    rest = Part("Footrest", m)
    top = SEAT_TOP
    fy = PAN_BACK + PAN_DEPTH
    rail_z = PEDAL_PIVOT.z - 0.03
    # Centre strut from under the pan's front, down between the shins to the pedal rail:
    # the pedals slide along it (they sit near its rear end here, for short legs).
    rest.bar((0, fy - 0.12, top - 0.105), (0, fy - 0.01, top - 0.24), (0.06, 0.04), "frame")
    rest.bar((0, fy - 0.01, top - 0.24), (0, PEDAL_PIVOT.y - 0.07, rail_z + 0.01), (0.045, 0.034), "frame")
    rest.rod((-0.04, fy - 0.01, top - 0.24), (0.04, fy - 0.01, top - 0.24), 0.024, "dark", 16)
    rest.bar((0, PEDAL_PIVOT.y - 0.09, rail_z), (0, PEDAL_PIVOT.y + 0.33, rail_z + 0.0494), (0.05, 0.03), "frame")
    for s in (1.0, -1.0):
        x = PEDAL_PIVOT.x * s
        rest.bar((x, PEDAL_PIVOT.y - 0.09, rail_z + 0.002), (x, PEDAL_PIVOT.y + 0.33, rail_z + 0.0514), (0.028, 0.018), "tube")
        for i in range(7):
            y = PEDAL_PIVOT.y - 0.06 + 0.06 * i
            rest.rbox((x, y, rail_z + 0.016 + (y - PEDAL_PIVOT.y + 0.09) * RAIL_SLOPE), (0.034, 0.006, 0.006), "dark", r=0.001)
    for y in (PEDAL_PIVOT.y - 0.085, PEDAL_PIVOT.y + 0.325):
        z = rail_z + (y - PEDAL_PIVOT.y + 0.09) * RAIL_SLOPE
        rest.rod((-0.15, y, z), (0.15, y, z), 0.013, "tube", 14)
    parts.append(rest.to_object())

    fwd = Vector((0, math.cos(PEDAL_TILT), math.sin(PEDAL_TILT)))
    up = Vector((0, -math.sin(PEDAL_TILT), math.cos(PEDAL_TILT)))
    for side, s in (("R", 1.0), ("L", -1.0)):
        pedal = Part(f"Pedal{side}", m)
        pivot = mirror(PEDAL_PIVOT, s)
        # Carriage riding the rail, under the hinge.
        pedal.rbox((pivot.x, pivot.y + 0.01, pivot.z - 0.014), (0.07, 0.07, 0.03), "dark", r=0.006)
        pedal.frame = frame_matrix(pivot, Vector((1, 0, 0)), fwd, up)
        pedal.rbox((0, 0.14, 0.008), (0.12, 0.28, 0.014), "dark", r=0.005)
        for i in range(8):                                                     # tread ribs
            pedal.rbox((0, 0.03 + 0.034 * i, 0.017), (0.104, 0.012, 0.005), "grip", r=0.0015)
        pedal.rbox((0, 0.275, 0.026), (0.12, 0.012, 0.03), "frame", r=0.004)    # toe stop
        pedal.rbox((0, -0.012, 0.03), (0.12, 0.014, 0.05), "frame", r=0.005)    # heel cup
        for k in (-1.0, 1.0):
            pedal.rbox((0.062 * k, 0.135, 0.014), (0.005, 0.27, 0.024), "frame", r=0.002)
        pedal.rod((-0.066, 0, 0.0), (0.066, 0, 0.0), 0.012, "tube", 12)
        obj = pedal.to_object(location=pivot)
        parts.append(obj)
        # Ankle target: over the heel, the sole lying on the plate (local +Y = toes,
        # +Z = up out of the instep).
        ankle = pivot + fwd * 0.065 + up * 0.165
        empty(f"Foot{side}", frame_matrix(ankle, Vector((1, 0, 0)), fwd, up), obj)
    return parts


# ── monitors ─────────────────────────────────────────────────────────────────

def monitor(name, m, centre, right, normal, up, size):
    """Bezel (with a back shell) and the screen quad `Screen<name>` facing `normal`."""
    bezel = Part(f"Bezel{name}", m)
    bezel.frame = frame_matrix(centre, right, normal, -up)
    w, h = size[0] + 2 * BEZEL, size[1] + 2 * BEZEL
    bezel.rbox((0, -0.011, 0), (w, 0.018, h), "dark", r=0.006)
    bezel.rbox((0, -0.026, 0), (w * 0.82, 0.018, h * 0.78), "frame", r=0.007)
    # Raised rim so the screen sits in a recess; soft keys along the bottom.
    for sx in (-1.0, 1.0):
        bezel.box((sx * (w - BEZEL) * 0.5, 0.0, 0), (BEZEL, 0.006, h), "dark")
    for sz in (-1.0, 1.0):
        bezel.box((0, 0.0, sz * (h - BEZEL) * 0.5), (w, 0.006, BEZEL), "dark")
    keys = max(3, round(size[0] / 0.045))
    for i in range(keys):
        x = (i - (keys - 1) * 0.5) * size[0] / keys
        bezel.box((x, 0.003, (h - BEZEL) * 0.5), (size[0] / keys * 0.55, 0.004, BEZEL * 0.45), "frame")
    scr = mk.PartBuilder(f"Screen{name}", m)
    scr.quad((0, 0, 0), size[0], size[1], "screen")
    bmesh.ops.transform(scr.bm, matrix=frame_matrix(centre, right, normal, -up), verts=scr.bm.verts)
    return [bezel.to_object(chamfer=0.0015), scr.to_object()]


def build_monitors(m):
    parts = []
    normal = (EYE - MAIN_CENTRE).normalized()
    right = Vector((1, 0, 0))
    up = normal.cross(right)
    up = up if up.z > 0 else -up
    hw, hh = MAIN_SIZE[0] * 0.5, MAIN_SIZE[1] * 0.5
    parts += monitor("Centre", m, MAIN_CENTRE, right, normal, up, MAIN_SIZE)
    phi = math.radians(SUB_TURN_DEG)
    arms = Part("DisplayArms", m)
    for side, s in (("L", -1.0), ("R", 1.0)):
        outward = right * (s * math.cos(phi)) + normal * math.sin(phi)
        sub_normal = normal * math.cos(phi) - right * (s * math.sin(phi))
        sub_right = outward if s > 0 else -outward
        hinge = MAIN_CENTRE + right * (s * (hw + BEZEL)) - up * (hh - SUB_SIZE[1] * 0.5 - BEZEL)
        centre = hinge + outward * (SUB_SIZE[0] * 0.5 + 2 * BEZEL)
        parts += monitor("Left" if s < 0 else "Right", m, centre, sub_right, sub_normal, up, SUB_SIZE)
        for k in (-1.0, 1.0):                   # hinge barrels joining the wing to the main panel
            p = hinge + outward * BEZEL * 0.6 - normal * 0.012
            arms.rod(p + up * (k * SUB_SIZE[1] * 0.36 - 0.014), p + up * (k * SUB_SIZE[1] * 0.36 + 0.014), 0.009, "tube", 12)
        # Articulated arm: from under the deck's front, down to an elbow, up to a yoke on
        # the main panel's back. It runs outside the knees and under the screens.
        root = Vector(((DECK_X[0] + 0.03) * s, DECK_Y[1] - 0.05, DECK_TOP - 0.07))
        elbow = Vector(((DECK_X[0] + 0.02) * s, MAIN_CENTRE.y - 0.1, SEAT_TOP + 0.0))
        yoke = MAIN_CENTRE + right * (s * hw * 0.7) - up * (hh * 0.55) - normal * 0.045
        arms.bar(root, elbow, (0.028, 0.036), "frame")
        arms.bar(elbow, yoke, (0.026, 0.032), "frame")
        for p, r in ((root, 0.026), (elbow, 0.028), (yoke, 0.021)):
            arms.rod(p - right * 0.024, p + right * 0.024, r, "dark", 16)
    y0 = MAIN_CENTRE - up * (hh * 0.55) - normal * 0.045
    arms.rod(y0 - right * (hw * 0.7), y0 + right * (hw * 0.7), 0.012, "tube", 12)
    parts.append(arms.to_object())
    return parts


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "cockpit_linear_seat_v2.glb"
    if "--aperture" in argv:
        APERTURE[:] = [float(v) for v in argv[argv.index("--aperture") + 1].split(",")]

    mk.reset_scene()
    m = materials()
    build_shell(m, APERTURE)
    swing = (build_seat(m) + build_jump_seat(m) + build_arms(m) + build_console_fittings(m)
             + build_pedals(m) + build_monitors(m))
    pivot = empty("SeatSwing", Matrix.Translation(SEAT_PIVOT))
    for obj in swing:
        parent_keep(obj, pivot)

    for obj in bpy.data.objects:
        obj.select_set(False)
    if out != "-":
        mk.export_glb(os.path.abspath(out), skins=False)
        print(f"[build_cockpit_linear_seat_v2] exported {out}")


main()
