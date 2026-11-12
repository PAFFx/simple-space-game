"""Turns the downloaded RX-93 ν Gundam model into a rigged suit plus separate weapons.

Run:  blender -b -P Tools/Blender/build_mobile_suit_nu.py -- <source.glb> <out_dir> [--preview <png prefix>]

The source is a single static mesh soup (Sketchfab export). Welding its duplicated
vertices restores 174 real parts; their order is stable, so parts are assigned to
bones and weapons by index (GROUPS). Rigid mech rig, like MSP-02: each part is
weighted 1.0 to one bone, bone names match MSP-02 so the Godot components work as is.

Outputs (Blender space Z up, front +Y, right +X; the exporter converts to Godot):
  mobile_suit_nu.glb     suit body with armature
  nu_beam_rifle.glb, nu_shield.glb, nu_hyper_bazooka.glb, nu_beam_saber.glb,
  nu_fin_funnels.glb     weapons, each placed where it sits on the suit at rest
                         (so an identity mount_transform puts it back)
"""

import json
import math
import os
import sys

import bmesh
import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import mesh_kit as mk  # noqa: E402

# Source frame: Z up, front -Y, centre line x = X0. Feet at Z0.
X0, Y0, Z0 = 0.105, -0.17, -0.14
SCALE = 6.5  # head top 3.11 → ~21.1 m, like MSP-02


def to_suit(p):
    """Source point → suit space (turned to face +Y, feet at 0, metres)."""
    x, y, z = p
    return mathutils.Vector((-(x - X0) * SCALE, -(y - Y0) * SCALE, (z - Z0) * SCALE))


def mirror(p):
    return (2.0 * X0 - p[0], p[1], p[2])


def ids(*ranges):
    out = []
    for r in ranges:
        out += list(range(r[0], r[1] + 1)) if isinstance(r, tuple) else [r]
    return out


# Part index → suit bone or weapon. Source -X is the model's right (R).
GROUPS = {
    "head": ids(0, 1, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14),
    "chest": ids(8, 15),
    "spine": ids(30),
    "pelvis": ids(21, 22, 25, 31, 32, 66, 67),
    "skirt_front.R": ids(28),
    "skirt_front.L": ids(26),
    "skirt_side.R": ids(24),
    "skirt_side.L": ids(23),
    "skirt_rear.R": ids(29),
    "skirt_rear.L": ids(27),
    "shoulder.R": ids(38, 40, 41, 69),
    "shoulder.L": ids(34, 36, 37, 68),
    "upper_arm.R": ids(39, 65),
    "upper_arm.L": ids(35, 64),
    "forearm.R": ids(19, 20, 33),
    "forearm.L": ids(16, 17, 18),
    "hand.R": ids((169, 173)),
    "hand.L": ids((123, 127)),
    "thigh.R": ids(42, 44, 45),
    "thigh.L": ids(53, 55, 56),
    "shin.R": ids(48, 52),
    "shin.L": ids(59, 63),
    # Movable thruster parts (Godot's ThrusterGuards turns them with their thrusters): the
    # backpack pods around the main nozzles, and the calf plates carrying their nozzles.
    "main_pod.R": ids(70, 75, 76, 78, 81),
    "main_pod.L": ids(71, 74, 79, 82, 83),
    "calf_guard.R": ids(47, 51),
    "calf_guard.L": ids(58, 62),
    "foot.R": ids(2, 43, 46, 49, 50),
    "foot.L": ids(3, 54, 57, 60, 61),
    "backpack": [i for i in range(70, 109) if i not in (70, 71, 74, 75, 76, 78, 79, 81, 82, 83,
            86, 87, 88, 94, 95, 99, 100, 106, 107, 108)],
    # Weapons
    "W:BeamRifle": ids((109, 122)),
    "W:Shield": ids((128, 138)),
    "W:HyperBazooka": ids(86, 87, 88, 94, 95, 99, 100, 106, 107),
    "W:BeamSaber": ids(108),
}
# Six fin funnels, five parts each in index order (tip, blade, tip, hinge block, blade).
for n in range(6):
    GROUPS[f"W:FinFunnel{n + 1}"] = list(range(139 + 5 * n, 144 + 5 * n))

WEAPON_FILES = {
    "BeamRifle": "nu_beam_rifle.glb",
    "Shield": "nu_shield.glb",
    "HyperBazooka": "nu_hyper_bazooka.glb",
    "BeamSaber": "nu_beam_saber.glb",
    "FinFunnel": "nu_fin_funnels.glb",
}


def bones():
    """(name, head, tail, parent) in source coordinates, right side mirrored to left."""
    c = X0
    b = [
        ("root", (c, -0.17, Z0), (c, -0.17, 0.0), None),
        ("pelvis", (c, -0.17, 1.72), (c, -0.17, 1.95), "root"),
        ("spine", (c, -0.17, 1.95), (c, -0.17, 2.15), "pelvis"),
        ("chest", (c, -0.17, 2.15), (c, -0.17, 2.78), "spine"),
        ("neck", (c, -0.2, 2.78), (c, -0.2, 2.85), "chest"),
        ("head", (c, -0.2, 2.85), (c, -0.2, 3.1), "neck"),
        ("backpack", (c, 0.35, 2.3), (c, 0.35, 2.7), "chest"),
    ]
    right = [
        # The armor pivots on the arm joint but isn't the arm's parent, so it can follow the
        # arm part way (Godot's LimbFollowers) without dragging it along.
        ("shoulder", (-0.45, -0.08, 2.55), (-0.45, -0.08, 2.75), "chest"),
        ("upper_arm", (-0.45, -0.08, 2.55), (-0.52, -0.1, 2.25), "chest"),
        ("forearm", (-0.52, -0.1, 2.25), (-0.62, -0.2, 1.86), "upper_arm"),
        ("hand", (-0.62, -0.2, 1.86), (-0.67, -0.3, 1.6), "forearm"),
        ("skirt_front", (-0.1, -0.43, 2.2), (-0.1, -0.5, 1.6), "pelvis"),
        ("skirt_side", (-0.3, -0.2, 2.2), (-0.32, -0.2, 1.9), "pelvis"),
        ("skirt_rear", (-0.14, 0.1, 2.15), (-0.15, 0.2, 1.45), "pelvis"),
        ("thigh", (-0.18, -0.19, 1.75), (-0.3, -0.15, 1.2), "pelvis"),
        ("shin", (-0.3, -0.15, 1.2), (-0.49, -0.11, 0.42), "thigh"),
        ("foot", (-0.49, -0.11, 0.42), (-0.57, -0.45, 0.0), "shin"),
    ]
    for name, head, tail, parent in right:
        for side in ("R", "L"):
            h, t = (head, tail) if side == "R" else (mirror(head), mirror(tail))
            p = parent if parent in ("chest", "pelvis") else f"{parent}.{side}"
            b.append((f"{name}.{side}", h, t, p))
    return [(n, tuple(to_suit(h)), tuple(to_suit(t)), p) for n, h, t, p in b]


# Main nozzles: (group, nozzle part, pod housing part). The nozzle is the hexagonal cup
# with the yellow rim; CUP_RADIUS > 0 would also take housing faces around it that face
# the same way (0: the frame stays with the backpack).
# Not used for the ν: its pods move as a whole, so the two nozzles never cross.
NOZZLE_CUPS = []
CUP_RADIUS = 0.0
CUP_MIN_DOT = 0.2

# The pod housings are deeper than on the source: stretched POD_STRETCH m backward with
# their front still on the backpack, so the pods stay attached but their nozzles sit
# further out and can swing without hitting the body. The nozzle rings move back with
# them unstretched. The hyper bazooka, hanging between the pods, moves back too.
POD_STRETCH = 1.0
POD_GROUPS = ("main_pod.R", "main_pod.L")
POD_RINGS = (74, 75, 76, 83)
BAZOOKA_OFFSET = mathutils.Vector((0.0, -1.0, 0.0))


def move_pods(bm, groups, part):
    """Stretches the pod housings backward; moves the rings and the bazooka rigidly."""
    for group in POD_GROUPS:
        faces = [f for f in bm.faces if groups[f.index] == group]
        verts = {v for f in faces for v in f.verts}
        front = max(v.co.y for v in verts)
        depth = max(front - min(v.co.y for v in verts), 1e-3)
        k = (depth + POD_STRETCH) / depth
        rings = {}
        for f in faces:
            if part[f.index] in POD_RINGS:
                for v in f.verts:
                    rings.setdefault(part[f.index], set()).add(v)
        ring_verts = set().union(*rings.values()) if rings else set()
        for v in verts - ring_verts:
            v.co.y = front - (front - v.co.y) * k
        for rv in rings.values():
            c = sum((v.co for v in rv), mathutils.Vector()) / len(rv)
            shift = -(front - c.y) * (k - 1.0)
            for v in rv:
                v.co.y += shift
    for v in {v for f in bm.faces if groups[f.index] == "W:HyperBazooka" for v in f.verts}:
        v.co += BAZOOKA_OFFSET


def print_nozzles(bm, part):
    """Nozzle ring centres in Godot body coordinates, for build_rx93_scene.gd."""
    for pid in POD_RINGS:
        pts = [v.co for f in bm.faces if part[f.index] == pid for v in f.verts]
        c = sum(pts, mathutils.Vector()) / len(pts)
        print(f"[nu] nozzle part {pid}: godot ({c.x:.2f}, {c.z:.2f}, {-c.y:.2f})")


# Movable bones: (group, parent bone, pivot): "top_front" = top edge toward +Y (a plate
# hinged against the leg), "top_mid" = middle of the top (a pod hanging from the backpack),
# "centre" = the part's centre (a nozzle on a ball joint).
POD_PIVOT = "centre"
GUARDS = [("hatch", "chest", "bottom_front"),
          ("main_pod.R", "backpack", POD_PIVOT), ("main_pod.L", "backpack", POD_PIVOT),
          ("calf_guard.R", "shin.R", "top_front"), ("calf_guard.L", "shin.L", "top_front")] + \
         [(g, "backpack", "centre") for g, _r, _h in NOZZLE_CUPS]


def face_groups(bm, part):
    """Group name per face: by part (GROUPS), with the main nozzle cups cut out."""
    by_part = {i: g for g, ps in GROUPS.items() for i in ps}
    bm.faces.ensure_lookup_table()
    out = [by_part.get(part[f.index], "backpack") for f in bm.faces]
    for group, ring, housing in NOZZLE_CUPS:
        faces = [f for f in bm.faces if part[f.index] == ring]
        centre = sum((v.co for f in faces for v in f.verts), mathutils.Vector()) / sum(len(f.verts) for f in faces)
        normal = sum((f.normal * f.calc_area() for f in faces), mathutils.Vector()).normalized()
        for f in faces:
            out[f.index] = group
        for f in bm.faces:
            if part[f.index] == housing and (f.calc_center_median() - centre).length < CUP_RADIUS \
                    and f.normal.dot(normal) > CUP_MIN_DOT:
                out[f.index] = group
    return out


def guard_bones(bm, groups):
    """Bones for the movable thruster parts, placed from their geometry (suit space)."""
    out = []
    for group, parent, pivot in GUARDS:
        pts = [v.co for f in bm.faces if groups[f.index] == group for v in f.verts]
        lo = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        if pivot == "top_front":
            head = mathutils.Vector(((lo.x + hi.x) * 0.5, hi.y, hi.z))
        elif pivot == "bottom_front":
            head = mathutils.Vector(((lo.x + hi.x) * 0.5, hi.y, lo.z))
        elif pivot == "top_mid":
            head = mathutils.Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, hi.z))
        else:
            head = sum(pts, mathutils.Vector()) / len(pts)
        length = max(hi.z - lo.z, 0.3)
        print(f"[nu] hinge {group}: godot ({head.x:.3f}, {head.z:.3f}, {-head.y:.3f})")
        out.append((group, tuple(head), tuple(head - mathutils.Vector((0, 0, length))), parent))
    return out


def load_parts(path):
    """Imports the source, welds it and returns (bmesh, materials, face → part index)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    sources = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bm = bmesh.new()
    materials = []
    for o in sources:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        start = len(bm.faces)
        bm.from_mesh(tmp)
        bm.faces.ensure_lookup_table()
        for f in bm.faces[start:]:
            f.material_index = len(materials)
        materials.append(o.data.materials[0])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.faces.ensure_lookup_table()
    part = [-1] * len(bm.faces)
    count = 0
    for f in bm.faces:
        if part[f.index] >= 0:
            continue
        stack = [f]
        part[f.index] = count
        while stack:
            g = stack.pop()
            for e in g.edges:
                for h in e.link_faces:
                    if part[h.index] < 0:
                        part[h.index] = count
                        stack.append(h)
        count += 1
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for v in bm.verts:
        v.co = to_suit(v.co)
    bm.normal_update()
    print(f"[nu] {count} parts")
    return bm, materials, part


def make_object(name, bm, materials, groups, group):
    b = bm.copy()
    b.faces.ensure_lookup_table()
    bmesh.ops.delete(b, geom=[f for f in b.faces if groups[f.index] != group], context="FACES")
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
    mesh = bpy.data.meshes.new(name)
    b.to_mesh(mesh)
    b.free()
    for m in materials:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bind(obj, armature, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = armature
    obj.parent = armature


# Taller belly: the chest below BELLY_TOP is stretched BELLY_SCALE times downward (the
# red door and the white abs grow), and everything from the pelvis down moves BELLY_DROP
# lower with it (Godot's scene builder lowers its lower-body positions to match). The
# upper body (chest above, head, arms, backpack) stays where it was.
BELLY_TOP = 15.9      # Godot height
BELLY_BOTTOM = 14.95
BELLY_SCALE = 1.8
BELLY_DROP = (BELLY_TOP - BELLY_BOTTOM) * (BELLY_SCALE - 1.0)
LOWER_PREFIXES = ("root", "pelvis", "spine", "skirt_", "thigh", "shin", "foot", "calf_guard")
# The navy column around the door (front of the chest, |x| <= COLUMN_HALF) stretches
# further, so its bottom edge (the door's, at COLUMN_BOTTOM) lands on the crotch armour's
# top (COLUMN_TO, after the drop), and slides along its own slope (z per y) so the door
# panel stays flat.
COLUMN_HALF = 0.5
COLUMN_BOTTOM = 15.34
COLUMN_TO = 14.40
COLUMN_SCALE = (BELLY_TOP - COLUMN_TO) / (BELLY_TOP - COLUMN_BOTTOM)
COLUMN_SLOPE = (-2.30 - -1.98) / (16.17 - 15.34)  # Godot z per y along the door panel


def _is_lower(group):
    return group.startswith(LOWER_PREFIXES)


def _belly_y(y):
    if y >= BELLY_TOP:
        return y
    if y >= BELLY_BOTTOM:
        return BELLY_TOP - (BELLY_TOP - y) * BELLY_SCALE
    return y - BELLY_DROP


def stretch_belly(bm, groups):
    """Applies the taller belly to the welded mesh (suit space: z up, -y = Godot +z)."""
    moved = set()
    for f in bm.faces:
        g = groups[f.index]
        for v in f.verts:
            if v.index in moved:
                continue
            if g == "chest" and abs(v.co.x) <= COLUMN_HALF and v.co.y > 1.25 and v.co.z < BELLY_TOP:
                y = v.co.z
                y_new = BELLY_TOP - (BELLY_TOP - y) * COLUMN_SCALE
                v.co.z = y_new
                v.co.y -= COLUMN_SLOPE * (y_new - y)  # Godot z += slope * dy
            elif g == "chest":
                v.co.z = _belly_y(v.co.z)
            elif _is_lower(g):
                v.co.z -= BELLY_DROP
            else:
                continue
            moved.add(v.index)
    print(f"[nu] belly: chest below {BELLY_TOP} x{BELLY_SCALE}, lower body {BELLY_DROP:.2f} m lower")


def stretch_bones(bone_list):
    out = []
    for name, head, tail, parent in bone_list:
        if _is_lower(name):
            head = (head[0], head[1], head[2] - BELLY_DROP)
            tail = (tail[0], tail[1], tail[2] - BELLY_DROP)
        elif name == "chest":
            head = (head[0], head[1], _belly_y(head[2]))
        out.append((name, head, tail, parent))
    return out


# Cockpit hatch, an airlock: the outer door is the red panel at the bottom of the chest
# (only the upright panel; the angled navy panel above stays), ~0.95 x 1.3 m; it slides up behind
# the chest front (Godot's CockpitHatch). Behind it a corridor (the airlock) runs from
# the door to the cockpit sphere (centre COCKPIT_CENTRE, Godot), where the cockpit's own
# inner door is. Keep COCKPIT_CENTRE in step with the RX-93 scene's CockpitMount, and the
# cockpit variant's --aperture with what this prints.
HATCH_PART = 15
HATCH_BOX = ((-0.52, 0.52), (14.30, 16.19), (-2.40, -1.50))  # x, y, z (Godot, stretched)
COCKPIT_CENTRE = (0.0, 16.6, -0.2)
AIRLOCK_MOUTH = 1.24              # distance of the corridor's inner end from the centre
AIRLOCK_HALF = (0.44, 0.56)       # corridor half width / height at the inner end, m


def _godot(v):
    return mathutils.Vector((v.x, v.z, -v.y))


def _suit(x, y, z):
    return mathutils.Vector((x, -z, y))


def split_hatch(bm, materials, part, groups):
    """Moves the door's faces to the "hatch" group and adds the airlock behind it."""
    (x0, x1), (y0, y1), (z0, z1) = HATCH_BOX
    door = []
    for f in bm.faces:
        if part[f.index] != HATCH_PART:
            continue
        c = _godot(f.calc_center_median())
        n = _godot(f.normal)
        if x0 < c.x < x1 and y0 < c.y < y1 and z0 < c.z < z1 and n.z < -0.3:
            groups[f.index] = "hatch"
            door.append(f)
    pts = [_godot(v.co) for f in door for v in f.verts]
    lo_x, hi_x = min(p.x for p in pts), max(p.x for p in pts)
    lo_y, hi_y = min(p.y for p in pts), max(p.y for p in pts)
    z_bottom = max(p.z for p in pts if p.y < lo_y + 0.1)
    z_top = max(p.z for p in pts if p.y > hi_y - 0.1)
    inset = 0.03
    ends = [(lo_x + inset, lo_y + inset, z_bottom + 0.04), (hi_x - inset, lo_y + inset, z_bottom + 0.04),
            (hi_x - inset, hi_y - inset, z_top + 0.04), (lo_x + inset, hi_y - inset, z_top + 0.04)]
    c = mathutils.Vector(COCKPIT_CENTRE)
    middle = sum((mathutils.Vector(e) for e in ends), mathutils.Vector()) / 4.0
    axis = (middle - c).normalized()
    right = mathutils.Vector((1, 0, 0))
    up = right.cross(axis).normalized() * -1.0
    if up.y < 0.0:
        up = -up
    hx, hy = AIRLOCK_HALF
    mouth_c = c + axis * AIRLOCK_MOUTH
    mouth = [mouth_c - right * hx - up * hy, mouth_c + right * hx - up * hy,
             mouth_c + right * hx + up * hy, mouth_c - right * hx + up * hy]
    wall = mk.make_material("MS_AirlockWall", (0.8, 0.82, 0.84), roughness=0.5)
    light = mk.make_material("MS_AirlockLight", (0.9, 0.95, 1.0), emission=(0.85, 0.92, 1.0), strength=4.0)
    materials.extend([wall, light])
    wall_i, light_i = len(materials) - 2, len(materials) - 1

    def add_quad(quad, mat_i, face_into, outward=False):
        """Quad facing `face_into` (or away from it when outward)."""
        verts = [bm.verts.new(_suit(*q)) for q in quad]
        f = bm.faces.new(verts)
        f.normal_update()
        mid = _godot(f.calc_center_median())
        if (_godot(f.normal).dot(face_into - mid) < 0.0) != outward:
            f.normal_flip()
        f.material_index = mat_i
        groups.append("chest")
        part.append(-1)

    for i in range(4):
        j = (i + 1) % 4
        end_i, end_j = mathutils.Vector(ends[i]), mathutils.Vector(ends[j])
        add_quad([mouth[i], mouth[j], end_j, end_i], wall_i, (middle + mouth_c) * 0.5)
    # Panel seams, hazard stripes at both ends and grab handles, so the corridor reads as
    # a built airlock. Wall points by (across u, along s from the mouth), lifted inward.
    seam = mk.make_material("MS_AirlockSeam", (0.08, 0.085, 0.09), roughness=0.6)
    yellow = mk.make_material("MS_AirlockYellow", (0.95, 0.68, 0.05), roughness=0.45)
    black = mk.make_material("MS_AirlockBlack", (0.02, 0.02, 0.02), roughness=0.6)
    materials.extend([seam, yellow, black])
    seam_i, yellow_i, black_i = len(materials) - 3, len(materials) - 2, len(materials) - 1
    centre_line = (middle + mouth_c) * 0.5

    def wall_point(i, u, t, lift=0.004):
        j = (i + 1) % 4
        near = mouth[i].lerp(mouth[j], u)
        far = mathutils.Vector(ends[i]).lerp(mathutils.Vector(ends[j]), u)
        p = near.lerp(far, t)
        axis_p = mouth_c.lerp(middle, t)
        return p + (axis_p - p).normalized() * lift

    def wall_quad(i, u0, u1, t0, t1, mat_i, lift=0.004):
        add_quad([wall_point(i, u0, t0, lift), wall_point(i, u1, t0, lift),
                  wall_point(i, u1, t1, lift), wall_point(i, u0, t1, lift)], mat_i, centre_line)

    length = (middle - mouth_c).length
    for i in range(4):
        for t in (0.25, 0.5, 0.75):
            wall_quad(i, 0.0, 1.0, t - 0.008 / length, t + 0.008 / length, seam_i)
        n = 10
        for k in range(n):
            mat_i = yellow_i if k % 2 == 0 else black_i
            for t0, t1 in ((0.0, 0.06), (0.94, 1.0)):
                wall_quad(i, k / n, (k + 1) / n, t0, t1, mat_i)

    def bar(p0, p1, size, mat_i):
        """Box from p0 to p1 with square cross-section `size`, faces outward."""
        d = (p1 - p0).normalized()
        a = d.cross(mathutils.Vector((1, 0, 0)))
        if a.length < 1e-3:
            a = d.cross(mathutils.Vector((0, 1, 0)))
        a = a.normalized() * size * 0.5
        b = d.cross(a).normalized() * size * 0.5
        ring0 = [p0 + a * sa + b * sb for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        ring1 = [p1 + a * sa + b * sb for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        centre = (p0 + p1) * 0.5
        for k in range(4):
            q = (k + 1) % 4
            add_quad([ring0[k], ring0[q], ring1[q], ring1[k]], mat_i, centre, True)
        add_quad(ring0, mat_i, centre, True)
        add_quad(ring1, mat_i, centre, True)

    # Grab handles on the side walls (walls 1 and 3), standing off them on two posts.
    for i in (1, 3):
        for t0, t1 in ((0.2, 0.42), (0.58, 0.8)):
            a0, a1 = wall_point(i, 0.5, t0, 0.0), wall_point(i, 0.5, t1, 0.0)
            b0, b1 = wall_point(i, 0.5, t0, 0.05), wall_point(i, 0.5, t1, 0.05)
            bar(b0, b1, 0.025, yellow_i)
            bar(a0, b0, 0.02, black_i)
            bar(a1, b1, 0.02, black_i)

    # Light strips along the side walls, a little in from them.
    for side in (-1.0, 1.0):
        a0 = mouth_c + right * (hx - 0.01) * side
        a1 = middle + right * (hi_x - inset - 0.01) * side
        strip = [a0 - up * 0.03, a1 - up * 0.03, a1 + up * 0.03, a0 + up * 0.03]
        add_quad(strip, light_i, (middle + mouth_c) * 0.5)
    bm.faces.ensure_lookup_table()
    el = math.degrees(math.asin(axis.y))
    dist = (middle - c).length
    print(f"[nu] hatch: {len(door)} door faces, {hi_x - lo_x:.2f} x {hi_y - lo_y:.2f} m; airlock axis "
          f"elevation {el:.1f} deg, door {dist:.2f} m from the centre; inner opening half angles "
          f"{math.degrees(math.atan(hx / AIRLOCK_MOUTH)):.1f} x {math.degrees(math.atan(hy / AIRLOCK_MOUTH)):.1f} deg")


def object_name(group):
    return "".join(w.capitalize() for w in group.replace(".", "_").split("_")) if not group.startswith("W:") \
        else group[2:]


def export(path, objects, skins):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_skins=skins, export_animations=False,
                              export_materials="EXPORT")


def preview(prefix, objects):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "OBJECT"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1100
    for i, o in enumerate(objects):
        o.color = (*_hsv((i * 0.137) % 1.0, 0.7, 0.95), 1.0)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 32.0
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    centre = mathutils.Vector((0.0, 0.0, 14.0))
    # Camera positions: the suit faces +Y, its right is +X.
    for name, d in (("front", (0, 1, 0)), ("back", (0, -1, 0)), ("right", (1, 0, 0)), ("left", (-1, 0, 0))):
        cam.location = centre + mathutils.Vector(d) * 40
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)


def _hsv(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, out_dir = argv[0], argv[1]
    preview_prefix = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
    bm, materials, part = load_parts(src)
    count = max(part) + 1
    assigned = [i for g in GROUPS.values() for i in g] + [r for _g, r, _h in NOZZLE_CUPS]
    missing = sorted(set(range(count)) - set(assigned))
    doubled = sorted({i for i in assigned if assigned.count(i) > 1})
    if missing or doubled:
        raise SystemExit(f"[nu] unassigned parts {missing}, assigned twice {doubled}")

    groups = face_groups(bm, part)
    bm.verts.ensure_lookup_table()
    stretch_belly(bm, groups)
    split_hatch(bm, materials, part, groups)
    if "--pod-pivot" in argv:
        global GUARDS
        piv = argv[argv.index("--pod-pivot") + 1]
        GUARDS = [(g, p, piv if g in POD_GROUPS else v) for g, p, v in GUARDS]
    move_pods(bm, groups, part)
    print_nozzles(bm, part)
    arm = mk.build_armature("Armature", stretch_bones(bones()) + guard_bones(bm, groups))
    suit, weapons = [], {}
    for group in list(GROUPS) + ["hatch"] + [g for g, _r, _h in NOZZLE_CUPS]:
        obj = make_object(object_name(group), bm, materials, groups, group)
        if group.startswith("W:"):
            kind = group[2:].rstrip("0123456789")
            weapons.setdefault(kind, []).append(obj)
        else:
            bind(obj, arm, group)
            suit.append(obj)
    bm.free()

    if preview_prefix:
        preview(preview_prefix, suit + [o for objs in weapons.values() for o in objs])
        return
    os.makedirs(out_dir, exist_ok=True)
    export(os.path.join(out_dir, "mobile_suit_nu.glb"), [arm] + suit, skins=True)
    for kind, objs in weapons.items():
        export(os.path.join(out_dir, WEAPON_FILES[kind]), objs, skins=False)
    print(f"[nu] exported to {out_dir}")


main()
