"""Export the three runtime dive-gear meshes from the fitted Blender scene.

From Blender, open Chibi_Dive_Mask_Swimming.blend and run this script.
strip_runner_goggles() is also used by the character exporter.
"""

from bisect import bisect_right
import json
import math
import struct
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / "assets" / "characters"
GLB_MAGIC = b"glTF"
INDEX_TYPES = {5121: "B", 5123: "H", 5125: "I"}
REMOVED_MATERIALS = {"M_Chibi_CreamTrim", "M_Chibi_GoggleLens", "M_Chibi_ShortsLavender"}
GOGGLE_BAND_HEIGHT = 0.925


def strip_runner_goggles(path):
    """Remove the six goggle parts from the skin without rewriting animation or morph data."""
    path = Path(path)
    source = path.read_bytes()
    magic, version, total = struct.unpack_from("<4sII", source)
    json_size, json_type = struct.unpack_from("<I4s", source, 12)
    bin_size, bin_type = struct.unpack_from("<I4s", source, 20 + json_size)
    assert (magic, version, total, json_type, bin_type) == (GLB_MAGIC, 2, len(source), b"JSON", b"BIN\0")
    doc = json.loads(source[20:20 + json_size])
    data = bytearray(source[28 + json_size:28 + json_size + bin_size])

    def read_accessor(index, entry_type):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        layout = struct.Struct("<" + entry_type)
        stride = view.get("byteStride", layout.size)
        return [layout.unpack_from(data, start + i * stride) for i in range(accessor["count"])]

    removed = 0
    for mesh in doc["meshes"]:
        remaining = []
        for primitive in mesh["primitives"]:
            material = doc["materials"][primitive["material"]]["name"]
            if material not in REMOVED_MATERIALS:
                remaining.append(primitive)
                continue
            assert primitive.get("mode", 4) == 4
            accessor = doc["accessors"][primitive["indices"]]
            index_type = INDEX_TYPES[accessor["componentType"]]
            positions = read_accessor(primitive["attributes"]["POSITION"], "3f")
            indices = [i[0] for i in read_accessor(primitive["indices"], index_type)]
            keep = []
            for offset in range(0, len(indices), 3):
                triangle = indices[offset:offset + 3]
                if min(positions[i][1] for i in triangle) > GOGGLE_BAND_HEIGHT:
                    removed += 1
                else:
                    keep.extend(triangle)
            if not keep:
                continue
            if keep != indices:
                offset = len(data)
                payload = struct.pack(f"<{len(keep)}{index_type}", *keep)
                data.extend(payload)
                data.extend(b"\0" * (-len(data) % 4))
                doc["bufferViews"].append(dict(buffer=0, byteOffset=offset, byteLength=len(payload), target=34963))
                doc["accessors"].append(dict(bufferView=len(doc["bufferViews"]) - 1, componentType=accessor["componentType"],
                                             count=len(keep), type="SCALAR", min=[min(keep)], max=[max(keep)]))
                primitive["indices"] = len(doc["accessors"]) - 1
            remaining.append(primitive)
        mesh["primitives"] = remaining

    if removed == 0:
        return 0
    if removed != 6424:
        raise ValueError(f"Expected Chibi's six goggle parts, found {removed} triangles. Review the current character mesh.")
    doc["buffers"][0]["byteLength"] = len(data)
    header = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    header += b" " * (-len(header) % 4)
    result = (struct.pack("<4sII", GLB_MAGIC, 2, 28 + len(header) + len(data))
              + struct.pack("<I4s", len(header), b"JSON") + header
              + struct.pack("<I4s", len(data), b"BIN\0") + data)
    temporary = path.with_suffix(".glb.tmp")
    temporary.write_bytes(result)
    temporary.replace(path)
    return removed


def make_shared_strap(character_mesh, band_faces, wet_source, make_prop):
    """Fit the same ring mesh to the forehead, the mask, and the hair between them."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    def azimuth(point):
        return math.atan2(point.x, -point.y) % math.tau

    band_indices = sorted({i for face in band_faces for i in face.vertices})
    # The dry band's first 21 cross sections store the top outer corner first.
    dry_rail = [character_mesh.vertices[i].co for i in band_indices[:81:4]]
    dry_angles = [azimuth(point) for point in dry_rail]
    assert len(band_indices) == 330 and all(a < b for a, b in zip(dry_angles, dry_angles[1:]))

    ring_size = 16
    wet_vertices = [wet_source.matrix_world @ v.co for v in wet_source.data.vertices]
    assert len(wet_vertices) >= ring_size * 2 and len(wet_vertices) % ring_size == 0
    wet_rings = [wet_vertices[i:i + ring_size] for i in range(0, len(wet_vertices), ring_size)]
    wet_centers = [sum(ring, Vector((0, 0, 0))) / ring_size for ring in wet_rings]
    wet_angles = [azimuth(point) for point in wet_centers]
    hair_slot = character_mesh.materials.find("M_Chibi_Hair")
    assert hair_slot >= 0
    hair = BVHTree.FromPolygons(
        [v.co for v in character_mesh.vertices],
        [tuple(p.vertices) for p in character_mesh.polygons if p.material_index == hair_slot],
    )
    up = Vector((0, 0, 1))
    dry_vertices = []
    corrections = []
    for i, (center, angle) in enumerate(zip(wet_centers, wet_angles)):
        fraction = (angle - wet_angles[0]) / (wet_angles[-1] - wet_angles[0])
        dry_angle = dry_angles[0] + (dry_angles[-1] - dry_angles[0]) * fraction
        rail_index = max(1, min(len(dry_rail) - 1, bisect_right(dry_angles, dry_angle)))
        low, high = dry_angles[rail_index - 1:rail_index + 1]
        rail = dry_rail[rail_index - 1].lerp(dry_rail[rail_index], (dry_angle - low) / (high - low))
        outward = Vector((math.sin(dry_angle), -math.cos(dry_angle), 0))
        dry_center = rail - outward * .0065 - up * .0105
        for j in range(ring_size):
            phase = math.tau * j / ring_size
            width = math.copysign(abs(math.cos(phase)) ** .43, math.cos(phase)) * .0065
            height = math.copysign(abs(math.sin(phase)) ** .46, math.sin(phase)) * .0125
            dry_vertices.append(dry_center + outward * width + up * height)

        # Follow the forward arc at the ends; expand the rest enough to pass around the hair.
        end_weight = max(0.0, 1.0 - min(fraction, 1.0 - fraction) / .24) ** 2
        forward = Vector((0, -.047 * end_weight, 0))
        radial = Vector((center.x, center.y, 0)).normalized()
        allowance = 0.0
        for step in range(1, 10):
            amount = step / 10
            bridge = math.sin(math.pi * amount)
            mid = dry_center.lerp(center, amount) + bridge * forward
            for z_offset in (-.013, 0, .013):
                axis = mid + up * z_offset
                hit = hair.ray_cast(axis + radial, -radial)[0]
                if hit is not None:
                    needed = (hit - axis).dot(radial) + .0055
                    allowance = max(allowance, needed / bridge)
        # The two ends are tucked into their buckles.
        end_clearance = min(1.0, min(i, len(wet_rings) - 1 - i) / 12)
        corrections.append(forward + radial * (min(allowance, .052) * end_clearance))

    strip = wet_source.data.copy()
    strip.name = "Shared Head Strap"
    for vertex, coordinate in zip(strip.vertices, dry_vertices):
        vertex.co = coordinate
    strip.materials.clear()
    strip.materials.append(character_mesh.materials["M_Chibi_ShortsLavender"])
    strap = make_prop("HeadStrap", strip)
    strap.shape_key_add(name="Basis")
    diving = strap.shape_key_add(name="Diving")
    around_hair = strap.shape_key_add(name="AroundHair")
    for i, coordinate in enumerate(wet_vertices):
        diving.data[i].co = coordinate
        start = max(0, i // ring_size - 3)
        stop = min(len(corrections), i // ring_size + 4)
        smoothed = sum(corrections[start:stop], Vector((0, 0, 0))) / (stop - start)
        around_hair.data[i].co = dry_vertices[i] + smoothed
    return strap


def export_gear():
    import bpy
    import bmesh
    from mathutils import Matrix, Vector

    character = bpy.data.objects["SKM_ChibiRunner"]
    armature = bpy.data.objects["Armature"]
    armature.animation_data_clear()
    for bone in armature.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    for key in character.data.shape_keys.key_blocks:
        key.value = 0.0
    bpy.context.view_layer.update()
    graph = bpy.context.evaluated_depsgraph_get()
    group = bpy.data.collections.new("Game Gear Export")
    bpy.context.scene.collection.children.link(group)

    def make_prop(name, mesh):
        obj = bpy.data.objects.new(name, mesh)
        group.objects.link(obj)
        return obj

    mesh = character.data
    materials = [slot.name for slot in mesh.materials]
    goggles = [p for p in mesh.polygons if materials[p.material_index] in REMOVED_MATERIALS
               and min(mesh.vertices[i].co.z for i in p.vertices) > GOGGLE_BAND_HEIGHT]
    if len(goggles) != 6424:
        raise ValueError(f"Expected six goggle parts in the swim scene, found {len(goggles)} triangles.")
    band_faces = [p for p in goggles if materials[p.material_index] == "M_Chibi_ShortsLavender"]
    strap = make_shared_strap(mesh, band_faces, bpy.data.objects["Mask | Continuous Head Strap"], make_prop)
    goggles = [p for p in goggles if materials[p.material_index] != "M_Chibi_ShortsLavender"]
    indices = sorted({index for p in goggles for index in p.vertices})
    mapping = {old: new for new, old in enumerate(indices)}
    dry = bpy.data.meshes.new("ForeheadGoggles")
    dry.from_pydata([mesh.vertices[i].co for i in indices], [],
                    [tuple(mapping[i] for i in p.vertices) for p in goggles])
    for slot in mesh.materials:
        dry.materials.append(slot)
    for dst, src in zip(dry.polygons, goggles):
        dst.material_index = src.material_index
        dst.use_smooth = True
    dry.update()
    dry_obj = make_prop("ForeheadGoggles", dry)

    glass = bpy.data.materials.new("Gear Clear Lens")
    glass.use_nodes = True
    glass.surface_render_method = "BLENDED"
    glass.diffuse_color = (0.70, 0.94, 0.91, 0.065)
    glass_shader = glass.node_tree.nodes.get("Principled BSDF")
    glass_shader.inputs["Base Color"].default_value = glass.diffuse_color
    glass_shader.inputs["Alpha"].default_value = glass.diffuse_color[3]
    glass_shader.inputs["Roughness"].default_value = .235

    def join_gear(collection, name):
        parts = []
        for source in bpy.data.collections[collection].objects:
            if source.type != "MESH" or source.name == "Mask | Continuous Head Strap" or source.name.startswith("Mask | Strap Grip"):
                continue
            evaluated = source.evaluated_get(graph)
            data = bpy.data.meshes.new_from_object(evaluated)
            data.transform(source.matrix_world)
            obj = make_prop(source.name + " Export", data)
            parts.append(obj)
            if source.name == "Mask | Single Clear Lens":
                data.materials.clear()
                data.materials.append(glass)
            if len(data.polygons) < 180:
                continue
            bpy.context.view_layer.objects.active = obj
            decimate = obj.modifiers.new("Game mesh density", "DECIMATE")
            decimate.ratio = .25 if len(data.polygons) > 1300 else .54
            bpy.ops.object.modifier_apply(modifier=decimate.name)
        for obj in bpy.context.selected_objects:
            obj.select_set(False)
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        return obj

    diving = join_gear("Mask", "DivingMask")
    tube = join_gear("Snorkel | Detachable", "Snorkel")
    for obj in bpy.context.selected_objects:
        obj.select_set(False)

    for obj, origin in ((dry_obj, (0, -.236, 1.015)), (diving, (0, -.225, .754)), (tube, (.340, -.158, .786))):
        position = Vector(origin)
        obj.data.transform(Matrix.Translation(-position))
        obj.location = position
        used_materials = sorted({p.material_index for p in obj.data.polygons})
        saved_materials = [obj.data.materials[i] for i in used_materials]
        material_map = {old: index for index, old in enumerate(used_materials)}
        polygon_slots = [material_map[p.material_index] for p in obj.data.polygons]
        obj.data.materials.clear()
        for material in saved_materials:
            obj.data.materials.append(material)
        for poly, index in zip(obj.data.polygons, polygon_slots):
            poly.material_index = index

        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.calc_loop_triangles()
        print(f"{obj.name}: {len(obj.data.loop_triangles)} triangles")
        obj.select_set(True)

    # Follow the top vent through every pose and snorkel deployment.
    vent = bpy.data.objects["Snorkel | Vent Interior 3"].matrix_world.translation
    outlet = make_prop("SnorkelOutlet", None)
    outlet.parent = tube
    outlet.location = vent + Vector((0, -.012, .002)) - tube.location
    outlet.select_set(True)
    strap.select_set(True)

    bpy.ops.export_scene.gltf(filepath=str(ASSETS / "chibi_dive_gear.glb"), export_format="GLB",
                              use_selection=True, export_animations=False, export_apply=False, export_morph=True, export_yup=True)


if __name__ == "__main__":
    export_gear()
