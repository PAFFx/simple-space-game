"""Small hard-surface modelling kit shared by the procedural Blender build scripts.

Conventions (Blender space): Z up, model front faces +Y, model right is +X.
The glTF exporter converts to Godot space: front becomes -Z, up stays +Y.
"""

import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = (*color, 1.0)
    return mat


class PartBuilder:
    """Accumulates primitives into one bmesh, then emits a single mesh object."""

    def __init__(self, name, materials):
        self.name = name
        self.materials = materials  # dict: key -> bpy material
        self.slots = []
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _slot(self, key):
        if key not in self.slots:
            self.slots.append(key)
        return self.slots.index(key)

    def _finish_faces(self, faces, mat, matrix):
        idx = self._slot(mat)
        verts = {v for f in faces for v in f.verts}
        bmesh.ops.transform(self.bm, matrix=matrix, verts=list(verts))
        for f in faces:
            f.material_index = idx
        return faces

    @staticmethod
    def _matrix(center, rot):
        m = Matrix.Translation(Vector(center))
        if rot is not None:
            m = m @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        return m

    def tbox(self, center, bottom, top, height, mat, shift=(0.0, 0.0), rot=None):
        """Tapered box. bottom/top = (size_x, size_y); shift offsets the top face in XY."""
        h = height * 0.5
        bx, by = bottom[0] * 0.5, bottom[1] * 0.5
        tx, ty = top[0] * 0.5, top[1] * 0.5
        sx, sy = shift
        co = [
            (-bx, -by, -h), (bx, -by, -h), (bx, by, -h), (-bx, by, -h),
            (-tx + sx, -ty + sy, h), (tx + sx, -ty + sy, h), (tx + sx, ty + sy, h), (-tx + sx, ty + sy, h),
        ]
        v = [self.bm.verts.new(c) for c in co]
        quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        faces = [self.bm.faces.new([v[i] for i in q]) for q in quads]
        self._box_uvs(faces)
        return self._finish_faces(faces, mat, self._matrix(center, rot))

    def box(self, center, size, mat, rot=None):
        return self.tbox(center, (size[0], size[1]), (size[0], size[1]), size[2], mat, rot=rot)

    def cylinder(self, center, radius, depth, mat, rot=None, radius_top=None, segments=12):
        """Cylinder/cone along local Z, then rotated by rot (degrees XYZ)."""
        r2 = radius if radius_top is None else radius_top
        res = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segments,
            radius1=radius, radius2=r2, depth=depth, calc_uvs=True,
        )
        faces = list({f for v in res["verts"] for f in v.link_faces})
        return self._finish_faces(faces, mat, self._matrix(center, rot))

    def sphere(self, center, radius, mat, segments=16, rings=8):
        res = bmesh.ops.create_uvsphere(
            self.bm, u_segments=segments, v_segments=rings, radius=radius, calc_uvs=True,
        )
        faces = list({f for v in res["verts"] for f in v.link_faces})
        return self._finish_faces(faces, mat, self._matrix(center, None))

    def quad(self, center, width, height, mat, rot=None):
        """Single-sided UV-mapped quad facing local +Y (useful for display screens)."""
        w, h = width * 0.5, height * 0.5
        co = [(-w, 0, -h), (w, 0, -h), (w, 0, h), (-w, 0, h)]
        v = [self.bm.verts.new(c) for c in co]
        face = self.bm.faces.new(v)
        # Winding so the normal faces +Y.
        face.normal_update()
        if face.normal.y < 0:
            face.normal_flip()
        for loop in face.loops:
            p = loop.vert.co
            loop[self.uv].uv = (p.x / width + 0.5, p.z / height + 0.5)
        return self._finish_faces([face], mat, self._matrix(center, rot))

    def _box_uvs(self, faces):
        for f in faces:
            for i, loop in enumerate(f.loops):
                loop[self.uv].uv = ((0, 0), (1, 0), (1, 1), (0, 1))[i % 4]

    def to_object(self, location=(0, 0, 0), armature=None, bone=None, bevel=0.0, collection=None):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for key in self.slots:
            mesh.materials.append(self.materials[key])

        obj = bpy.data.objects.new(self.name, mesh)
        (collection or bpy.context.scene.collection).objects.link(obj)
        obj.location = location

        if bevel > 0.0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 1
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(35)

        if armature is not None and bone is not None:
            group = obj.vertex_groups.new(name=bone)
            group.add(range(len(mesh.vertices)), 1.0, "REPLACE")
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = armature
            obj.parent = armature
        return obj


def build_armature(name, bones):
    """bones: list of (name, head, tail, parent_name_or_None)."""
    data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in bones:
        eb = data.edit_bones.new(bone_name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent is not None:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def export_glb(filepath, skins=True):
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_skins=skins,
        export_animations=False,
        export_materials="EXPORT",
    )
