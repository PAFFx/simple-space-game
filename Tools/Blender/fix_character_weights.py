"""Moves stray skin weights off one bone, in place, in a GLB (no Blender needed).

The Amate model's boots carry a few percent of weight (the soles much more) on the root
bone `hips_01`, which stays on the ground: harmless standing, but seated the soles are
left behind and the boots stretch. This gives each vertex's share on that bone to its
strongest other bone. Only the weight bytes change; nodes, names and materials stay.

Run:  python3 Tools/Blender/fix_character_weights.py <file.glb> [--mesh shoes] [--bone hips_01]
"""

import json
import struct
import sys

COMPONENT = {5121: ("B", 255.0), 5123: ("H", 65535.0), 5126: ("f", 1.0)}


def main():
    args = sys.argv[1:]
    path = args[0]
    mesh_key = args[args.index("--mesh") + 1] if "--mesh" in args else "shoes"
    bone = args[args.index("--bone") + 1] if "--bone" in args else "hips_01"
    data = bytearray(open(path, "rb").read())
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8

    def view(accessor_index):
        acc = gltf["accessors"][accessor_index]
        bv = gltf["bufferViews"][acc["bufferView"]]
        fmt, scale = COMPONENT[acc["componentType"]]
        size = struct.calcsize(fmt) * 4
        offset = bin_start + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return offset, bv.get("byteStride", size), acc["count"], fmt, scale

    moved = 0
    for node in gltf["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        mesh = gltf["meshes"][node["mesh"]]
        if mesh_key.lower() not in mesh.get("name", "").lower():
            continue
        joints = gltf["skins"][node["skin"]]["joints"]
        stray = next(i for i, j in enumerate(joints) if gltf["nodes"][j].get("name") == bone)
        for prim in mesh["primitives"]:
            j_off, j_stride, count, j_fmt, _ = view(prim["attributes"]["JOINTS_0"])
            w_off, w_stride, _, w_fmt, w_scale = view(prim["attributes"]["WEIGHTS_0"])
            for v in range(count):
                js = struct.unpack_from("<4" + j_fmt, data, j_off + v * j_stride)
                ws = list(struct.unpack_from("<4" + w_fmt, data, w_off + v * w_stride))
                others = [k for k in range(4) if js[k] != stray and ws[k] > 0]
                strays = [k for k in range(4) if js[k] == stray and ws[k] > 0]
                if not strays or not others:
                    continue
                best = max(others, key=lambda k: ws[k])
                for k in strays:
                    ws[best] += ws[k]
                    ws[k] = 0
                if w_fmt != "f":
                    ws = [min(int(w), int(w_scale)) for w in ws]
                struct.pack_into("<4" + w_fmt, data, w_off + v * w_stride, *ws)
                moved += 1
    open(path, "wb").write(data)
    print(f"[fix_character_weights] {moved} vertices of '{mesh_key}' moved off {bone}")


main()
