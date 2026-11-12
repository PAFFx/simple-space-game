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
GUARDS = [("main_pod.R", "backpack", POD_PIVOT), ("main_pod.L", "backpack", POD_PIVOT),
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
    if "--pod-pivot" in argv:
        global GUARDS
        piv = argv[argv.index("--pod-pivot") + 1]
        GUARDS = [(g, p, piv if g in POD_GROUPS else v) for g, p, v in GUARDS]
    move_pods(bm, groups, part)
    print_nozzles(bm, part)
    arm = mk.build_armature("Armature", bones() + guard_bones(bm, groups))
    suit, weapons = [], {}
    for group in list(GROUPS) + [g for g, _r, _h in NOZZLE_CUPS]:
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
