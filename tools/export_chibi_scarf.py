"""Bake the gameplay scarf canopy, hand pins, and approved cloth artwork for Godot.

Run with Blender 5.3:
  blender --background --python tools/export_chibi_scarf.py
The concept blend supplies the posed grips and artwork and is never saved.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_BLEND = (
    PROJECT_ROOT / "source_art" / "concept_art" / "Chibi" / "Parachute" / "Scarf"
    / "Chibi Scarf Parachute.blend"
)
OUTPUT_DIR = PROJECT_ROOT / "assets" / "characters"
CANOPY_PATH = OUTPUT_DIR / "chibi_scarf_canopy.glb"
PRINT_PATH = OUTPUT_DIR / "chibi_scarf_print.png"
WEAVE_PATH = OUTPUT_DIR / "chibi_scarf_weave.png"
LAYOUT_PATH = OUTPUT_DIR / "chibi_scarf_layout.tres"
CANOPY_OBJECT = "Scarf • two gathered ends"
ARMATURE_OBJECT = "Chibi • glide pose"
PRINT_IMAGE = "Strawberry Hollow • unbacked scarf print • 4096 px"
TRIANGLE_BUDGET = 3000
SPAN_STEPS = 30
DEPTH_STEPS = 22
PRINT_SIZE = 1024
WEAVE_SIZE = 256
PIN_RADIUS = 0.11
# Hand-local points in the concept rig's Blender coordinate system. The corner
# order matches the pin channels used by ChibiScarfGlider and the shader.
GRIP_OFFSETS = (
    ("hand_l", (-0.0485, 0.1070, 0.0169), (1, 1)),
    ("hand_l", (0.0201, 0.0924, -0.0033), (1, -1)),
    ("hand_r", (-0.0179, 0.0902, -0.0054), (-1, -1)),
    ("hand_r", (0.0459, 0.1073, 0.0225), (-1, 1)),
)


def godot_vector(value):
    """Convert a Blender Z-up point/vector to the GLB/Godot Y-up basis."""
    return [float(value.x), float(value.z), float(-value.y)]


def save_packed_print():
    image = bpy.data.images[PRINT_IMAGE].copy()
    image.name = "Chibi Scarf Strawberry Hollow Print"
    image.scale(PRINT_SIZE, PRINT_SIZE)
    image.file_format = "PNG"
    image.filepath_raw = str(PRINT_PATH)
    image.save()
    return image


def save_weave_lookup(material):
    ramp = next(node.color_ramp for node in material.node_tree.nodes if node.type == "VALTORGB")
    image = bpy.data.images.new("Chibi Scarf Peach Weave Lookup", width=WEAVE_SIZE, height=1, alpha=True)
    pixels = []
    for x in range(WEAVE_SIZE):
        color = ramp.evaluate(x / max(WEAVE_SIZE - 1, 1))
        pixels.extend(color)
    image.pixels = pixels
    image.file_format = "PNG"
    image.filepath_raw = str(WEAVE_PATH)
    image.save()
    return image


def make_runtime_material():
    material = bpy.data.materials.new("M_Chibi_ScarfPeach_Runtime")
    material.use_nodes = True
    material.diffuse_color = (0.97, 0.50, 0.39, 1.0)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = material.diffuse_color
    shader.inputs["Roughness"].default_value = 0.66
    shader.inputs["Metallic"].default_value = 0.0
    return material


def make_pin_layout(armature):
    pins = []
    for bone_name, offset, corner in GRIP_OFFSETS:
        hand_local = Vector(offset)
        pose = armature.matrix_world @ armature.pose.bones[bone_name].matrix
        col = SPAN_STEPS if corner[0] > 0 else 0
        row = DEPTH_STEPS if corner[1] > 0 else 0
        pins.append({
            "bone": bone_name,
            "vertex": row * (SPAN_STEPS + 1) + col,
            "source_point": pose @ hand_local,
            "bone_local": hand_local,
        })
    return pins


def canopy_point(u, v, grips):
    """A broad crown curves into both rims, then drapes into the four grips."""
    grip = grips[(1 if u >= 0.0 else -1, 1 if v >= 0.0 else -1)]
    gathered = abs(u) ** 2.25 * abs(v) ** 2.05
    crown = Vector((
        1.12 * u * (1.0 - 0.07 * v * v),
        0.63 * v + 0.025 * u * u,
        1.44 + 0.35 * (1.0 - u * u) + 0.18 * (1.0 - v * v) + 0.055 * v,
    ))
    point = crown.lerp(grip, gathered)
    # Keep the middle taut. Only the gathered quarters carry small sewn-in folds.
    folds = 0.033 * math.sin(math.pi * gathered) ** 2
    angle = math.atan2(1.0 - abs(v), 1.0 - abs(u))
    point.z += folds * math.sin(angle * 16.0 + 0.4 * v)
    return point


def make_canopy(pins):
    grips = {spec[2]: pin["source_point"] for spec, pin in zip(GRIP_OFFSETS, pins)}
    columns = SPAN_STEPS + 1
    outer = []
    inner = []
    for row in range(DEPTH_STEPS + 1):
        for col in range(SPAN_STEPS + 1):
            u, v = 2.0 * col / SPAN_STEPS - 1.0, 2.0 * row / DEPTH_STEPS - 1.0
            point = canopy_point(u, v, grips)
            tangent_u = canopy_point(min(1.0, u + 0.002), v, grips) - canopy_point(max(-1.0, u - 0.002), v, grips)
            tangent_v = canopy_point(u, min(1.0, v + 0.002), grips) - canopy_point(u, max(-1.0, v - 0.002), grips)
            normal = tangent_u.cross(tangent_v).normalized()
            edge = max(abs(u), abs(v)) ** 8
            gather = (abs(u) * abs(v)) ** 3
            thickness = 0.004 + (0.016 + 0.023 * edge) * (1.0 - gather)
            outer.append(point)
            inner.append(point - normal * thickness)

    surface_size = len(outer)
    faces = []
    for row in range(DEPTH_STEPS):
        for col in range(SPAN_STEPS):
            a = row * columns + col
            quad = (a, a + 1, a + columns + 1, a + columns)
            faces.append(quad)
            faces.append(tuple(surface_size + index for index in reversed(quad)))
    rim = (
        list(range(columns))
        + [row * columns + SPAN_STEPS for row in range(1, DEPTH_STEPS + 1)]
        + [DEPTH_STEPS * columns + col for col in range(SPAN_STEPS - 1, -1, -1)]
        + [row * columns for row in range(DEPTH_STEPS - 1, 0, -1)]
    )
    for a, b in zip(rim, rim[1:] + rim[:1]):
        faces.append((b, a, a + surface_size, b + surface_size))

    mesh = bpy.data.meshes.new("Chibi Scarf Canopy (Mobile)")
    mesh.from_pydata(outer + inner, [], faces)
    mesh.update()
    mesh.materials.append(make_runtime_material())
    uv = mesh.uv_layers.new(name="Canopy UV")
    for face in mesh.polygons:
        face.use_smooth = True
        for loop_index in face.loop_indices:
            index = mesh.loops[loop_index].vertex_index % surface_size
            row, col = divmod(index, columns)
            uv.data[loop_index].uv = (col / SPAN_STEPS, row / DEPTH_STEPS)

    attribute = mesh.color_attributes.new(name="ScarfCornerPins", type="FLOAT_COLOR", domain="POINT")
    pin_points = [pin["source_point"] for pin in pins]
    pin_vertex_indices = {pin["vertex"]: i for i, pin in enumerate(pins)}
    radius_sq = PIN_RADIUS * PIN_RADIUS
    for index, point in enumerate(outer):
        if index in pin_vertex_indices:
            exact = [0.0, 0.0, 0.0, 0.0]
            exact[pin_vertex_indices[index]] = 1.0
            weights = exact
        else:
            raw = [math.exp(-(point - pin).length_squared / (2.0 * radius_sq)) for pin in pin_points]
            total = max(1.0, sum(raw))
            weights = [value / total for value in raw]
        # Both sides travel with the same hand so the shell cannot split at a pinch.
        attribute.data[index].color = weights
        attribute.data[index + surface_size].color = weights
    mesh.color_attributes.active_color = attribute
    mesh.color_attributes.render_color_index = 0
    canopy = bpy.data.objects.new("Chibi Scarf Canopy", mesh)
    bpy.context.scene.collection.objects.link(canopy)
    return canopy


def export():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
    source = bpy.data.objects.get(CANOPY_OBJECT)
    armature = bpy.data.objects.get(ARMATURE_OBJECT)
    if source is None or armature is None:
        raise RuntimeError("The approved scarf mesh or posed armature is missing.")
    if source.type != "MESH":
        raise TypeError(f"{CANOPY_OBJECT} must remain a mesh.")
    bpy.context.view_layer.update()

    original_material = source.data.materials[0]
    save_packed_print()
    save_weave_lookup(original_material)

    pins = make_pin_layout(armature)
    canopy = make_canopy(pins)
    canopy.data.calc_loop_triangles()
    triangle_count = len(canopy.data.loop_triangles)
    if triangle_count > TRIANGLE_BUDGET:
        raise RuntimeError(f"Canopy exceeds the {TRIANGLE_BUDGET}-triangle mobile budget: {triangle_count}.")

    bpy.ops.object.select_all(action="DESELECT")
    canopy.select_set(True)
    bpy.context.view_layer.objects.active = canopy

    bpy.ops.export_scene.gltf(
        filepath=str(CANOPY_PATH),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=False,
        export_skins=False,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=True,
        export_cameras=False,
        export_lights=False,
    )

    points = ", ".join(f"{value:.9g}" for pin in pins for value in godot_vector(pin["source_point"]))
    offsets = ", ".join(f"{value:.9g}" for pin in pins for value in godot_vector(pin["bone_local"]))
    bones = ", ".join(f'"{pin["bone"]}"' for pin in pins)
    resource_text = f'''[gd_resource type="Resource" script_class="ChibiScarfLayout" load_steps=2 format=3]

[ext_resource type="Script" path="res://features/runner/chibi_scarf_layout.gd" id="1_layout"]

[resource]
script = ExtResource("1_layout")
source_pin_points = PackedVector3Array({points})
bone_local_offsets = PackedVector3Array({offsets})
pin_bones = PackedStringArray({bones})
'''
    LAYOUT_PATH.write_text(resource_text, encoding="utf-8")
    print(f"[Scarf] Wrote {CANOPY_PATH.name}: {len(canopy.data.vertices)} vertices, {triangle_count} triangles")
    print(f"[Scarf] Packed print at {PRINT_SIZE}²; four gathered corner pins written to {LAYOUT_PATH.name}")


if __name__ == "__main__":
    export()




