"""Export the approved low-poly scarf canopy and its packed print for Godot.

Run with Blender 5.3:
  blender --background --python tools/export_chibi_scarf.py
The approved concept blend is opened read-only and is never saved.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_BLEND = PROJECT_ROOT / "concept_art" / "Chibi" / "Parachute" / "Scarf" / "Chibi Scarf Parachute.blend"
OUTPUT_DIR = PROJECT_ROOT / "assets" / "characters"
CANOPY_PATH = OUTPUT_DIR / "chibi_scarf_canopy.glb"
PRINT_PATH = OUTPUT_DIR / "chibi_scarf_print.png"
WEAVE_PATH = OUTPUT_DIR / "chibi_scarf_weave.png"
LAYOUT_PATH = OUTPUT_DIR / "chibi_scarf_layout.tres"
CANOPY_OBJECT = "Scarf • two gathered ends"
ARMATURE_OBJECT = "Chibi • glide pose"
PRINT_IMAGE = "Strawberry Hollow • unbacked scarf print • 4096 px"
TRIANGLE_BUDGET = 3000
DECIMATE_RATIO = 0.05
PRINT_SIZE = 1024
WEAVE_SIZE = 256
PIN_RADIUS = 0.11


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


def make_pin_layout(obj, source_armature):
    hands = []
    for bone_name in ("hand_l", "hand_r"):
        bone_pose = source_armature.matrix_world @ source_armature.pose.bones[bone_name].matrix
        bone_inv = bone_pose.inverted()
        # On each mitt, select two separated cloth corners along the cross-grip axis.
        # This reproduces the concept's two real ends entering each hand ring.
        candidates = []
        for vertex in obj.data.vertices:
            point_world = obj.matrix_world @ vertex.co
            hand_local = bone_inv @ point_world
            if 0.045 <= hand_local.y <= 0.155 and abs(hand_local.z) <= 0.040:
                candidates.append((vertex.index, hand_local.copy(), point_world.copy()))
        if len(candidates) < 2:
            raise RuntimeError(f"Could not find the two gathered cloth corners at {bone_name}.")

        desired_offsets = (Vector((-0.045, 0.105, 0.0)), Vector((0.030, 0.105, 0.0)))
        chosen = []
        used = set()
        for desired in desired_offsets:
            ranked = sorted(candidates, key=lambda candidate: (candidate[1] - desired).length_squared)
            selected = next((item for item in ranked if item[0] not in used), ranked[0])
            chosen.append(selected)
            used.add(selected[0])
        for index, hand_local, point_world in chosen:
            hands.append({
                "bone": bone_name,
                "vertex": index,
                "source_point": point_world.copy(),
                "bone_local": hand_local.copy(),
            })
    return hands


def paint_pin_weights(obj, pins):
    attribute = obj.data.color_attributes.get("ScarfCornerPins")
    if attribute is not None:
        obj.data.color_attributes.remove(attribute)
    attribute = obj.data.color_attributes.new(
        name="ScarfCornerPins", type="FLOAT_COLOR", domain="POINT"
    )
    mesh_world = obj.matrix_world
    pin_points = [mesh_world.inverted() @ pin["source_point"] for pin in pins]
    pin_vertex_indices = {pin["vertex"]: i for i, pin in enumerate(pins)}
    radius_sq = PIN_RADIUS * PIN_RADIUS
    for vertex in obj.data.vertices:
        if vertex.index in pin_vertex_indices:
            exact = [0.0, 0.0, 0.0, 0.0]
            exact[pin_vertex_indices[vertex.index]] = 1.0
            attribute.data[vertex.index].color = exact
            continue
        point = vertex.co
        raw = []
        for pin_point in pin_points:
            dist_sq = (point - pin_point).length_squared
            # Soft neighboring weights preserve a smooth cloth transition.
            raw.append(math.exp(-dist_sq / max(2.0 * radius_sq, 1.0e-8)))
        total = sum(raw)
        if total > 1.0:
            raw = [weight / total for weight in raw]
        attribute.data[vertex.index].color = (raw[0], raw[1], raw[2], raw[3])
    if hasattr(obj.data.color_attributes, "active_color"):
        obj.data.color_attributes.active_color = attribute
    if hasattr(obj.data.color_attributes, "render_color_index"):
        obj.data.color_attributes.render_color_index = list(obj.data.color_attributes).index(attribute)

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

    mesh = source.data.copy()
    mesh.name = "Chibi Scarf Canopy (Mobile)"
    canopy = bpy.data.objects.new("Chibi Scarf Canopy", mesh)
    bpy.context.scene.collection.objects.link(canopy)
    canopy.matrix_world = source.matrix_world.copy()
    canopy.data.materials.clear()
    canopy.data.materials.append(make_runtime_material())

    bpy.context.view_layer.objects.active = canopy
    canopy.select_set(True)
    for selected in bpy.context.selected_objects:
        if selected != canopy:
            selected.select_set(False)

    # Apply the concept's thin shell before reducing the generated cloth tessellation.
    shell = canopy.modifiers.new("Mobile cloth shell", "SOLIDIFY")
    source_shell = next((modifier for modifier in source.modifiers if modifier.type == "SOLIDIFY"), None)
    shell.thickness = source_shell.thickness if source_shell else 0.003
    shell.offset = source_shell.offset if source_shell else 0.0
    shell.use_rim = True
    bpy.ops.object.modifier_apply(modifier=shell.name)

    # Collapse the high-resolution cloth simulation surface while preserving its UVs.
    decimate = canopy.modifiers.new("Mobile cloth reduction", "DECIMATE")
    decimate.ratio = DECIMATE_RATIO
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)

    canopy.data.calc_loop_triangles()
    triangles_before_pins = len(canopy.data.loop_triangles)
    if triangles_before_pins > TRIANGLE_BUDGET:
        retry = canopy.modifiers.new("Mobile cloth reduction (budget)", "DECIMATE")
        retry.ratio = TRIANGLE_BUDGET / float(triangles_before_pins)
        retry.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=retry.name)
        canopy.data.calc_loop_triangles()

    pins = make_pin_layout(canopy, armature)
    paint_pin_weights(canopy, pins)
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

    def resource_vector(values):
        return "Vector3(%s, %s, %s)" % tuple(f"{float(value):.9g}" for value in values)

    points = ", ".join(f"{value:.9g}" for pin in pins for value in godot_vector(pin["source_point"]))
    offsets = ", ".join(f"{value:.9g}" for pin in pins for value in godot_vector(pin["bone_local"]))
    bones = ", ".join(f'"{pin["bone"]}"' for pin in pins)
    resource_text = f'''[gd_resource type="Resource" script_class="ChibiScarfLayout" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/character/chibi_scarf_layout.gd" id="1_layout"]

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




