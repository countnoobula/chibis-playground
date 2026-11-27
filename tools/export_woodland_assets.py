"""Export the reusable Parkour woodland kit with Blender 5.3.

blender --background --python-exit-code 1 --python tools/export_woodland_assets.py

The default inputs are source_art and source_art/UnrealExtract in Chibi.
Use --source-root and --unreal-extract to point at a separate archive,
or --output-root to build the GLBs and manifest into a separate directory.
"""
import argparse
import filecmp
import json
import math
import re
import shutil
import struct
import sys
import tempfile
from array import array
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[1]
SOURCE_ART = PROJECT / "source_art"
OUTPUT = PROJECT / "assets/environment/woodland"
IMPORTER = "res://assets/environment/woodland/import_woodland.gd"
NATIVE_STATIC_SLOTS = {
    "SM_FirstSteps_RiverGravel": ("M_ValleyCreekGravel",),
    "SM_Forest_MossTerrain_Solid": ("MI_Forest_MossBank",),
}
OPENGL_NORMALS = {"T_ValleyFlora_N"}

FAMILIES = {
    "CloverBank": "CloverBank/CloverBank.blend",
    "ValleyFlora": "ValleyFlora/ValleyFlora.blend",
    "ValleyUnderstory": "ValleyUnderstory/Valley_Understory.blend",
    "ValleyCliffs": "ValleyCliffs/ValleyCliffs.blend",
    "ValleyLotus": "ValleyLotus/Valley_LotusStep.blend",
    "ValleyMushrooms": "ValleyMushrooms/Valley_AmberStep.blend",
    "ValleyRoot": "ValleyRoot/ValleyRoot.blend",
    "ValleyTrees": "ValleyTrees/Valley_ElderTree.blend",
    "FBX/Forest": "ForestKit.blend",
    "FBX/ForestFoliage": "ForestFoliage_V3.blend",
    "FBX/ForestV2": "ForestKit_V2.blend",
}
EXCLUDED = {
    "SM_Forest_AcornCottage", "SM_Forest_AcornCottage_V2", "SM_Forest_PetalLantern",
    "SM_Forest_RootAlcove", "SM_Forest_TwigBridge", "SM_Forest_TwigFence",
    "SM_Forest_SkyDome",
}
TEXTURE_FAMILIES = (
    "CloverBank", "ValleyFlora", "ValleyUnderstory", "ValleyCliffs", "ValleyGround",
    "ValleyLotus", "ValleyMushrooms", "ValleyRoot", "ValleyTrees", "Textures",
)
PALETTES = {
    "ValleyFlora": {"Lining": "#fbe2ee", "Pollen": "#edc651"},
    "ValleyUnderstory": {
        "MossBase": "#ffffff", "UnderNap": "#526632", "TipNap": "#719344",
        "Stem": "#7b943d", "Stalk": "#81983e", "Ivory": "#f8ecd1",
        "Gold": "#e8bd4a", "Clover": "#8caf54", "Leaf": "#8daa50",
        "Lining": "#efe2e9", "Violet": "#bc97dc", "Grass": "#96aa54",
        "Buff": "#be9d72", "Honey": "#bc9056", "Moss": "#78884b",
    },
    "ValleyLotus": {"Leaf": "#ffffff", "Petiole": "#788d46"},
}
FLORA_INSTANCES = {
    "MI_Bellflower_Lavender": ((0.39, 0.20, 0.72), (0.53, 0.31, 0.78), 0.46),
    "MI_Bellflower_Stem": ((0.10, 0.21, 0.044), (0.23, 0.31, 0.064), 0.34),
    "MI_CrossingStrawberry_Flesh": ((0.62, 0.028, 0.023), (0.72, 0.047, 0.025), 0.56),
    "MI_CrossingStrawberry_Leaf": ((0.064, 0.20, 0.062), (0.18, 0.30, 0.075), 0.71),
    "MI_CrossingStrawberry_Seed": ((0.78, 0.44, 0.116), (0.84, 0.50, 0.17), 0.71),
}
FLORA_SLOT_MATERIALS = {
    "Stem": "MI_Bellflower_Stem", "Stalk": "MI_Bellflower_Stem", "Vein": "MI_Bellflower_Stem",
    "Lavender": "MI_Bellflower_Lavender", "Flesh": "MI_CrossingStrawberry_Flesh",
    "Leaf": "MI_CrossingStrawberry_Leaf", "Seed": "MI_CrossingStrawberry_Seed",
}


def snake(name):
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def srgb_to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def color_factor(html):
    return [srgb_to_linear(int(html[i:i + 2], 16) / 255) for i in (1, 3, 5)] + [1.0]


def from_linear(values):
    rgb = [
        12.92 * v if v <= 0.0031308 else 1.055 * math.pow(v, 1 / 2.4) - 0.055
        for v in values[:3]
    ]
    return "#" + "".join(f"{round(max(0, min(1, v)) * 255):02x}" for v in rgb)


def material_config(family, model, material, has_color):
    slot = material.name
    principled = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    color = from_linear(principled.inputs["Base Color"].default_value) if principled else "#ffffff"
    roughness = round(principled.inputs["Roughness"].default_value, 3) if principled else 0.72
    data = {
        "color": PALETTES.get(family, {}).get(slot, color),
        "roughness": roughness,
        "normal_strength": 0.65,
    }

    def maps(prefix, color_suffix="_BaseColor", normal_suffix="_NormalGL"):
        data["albedo"] = prefix + color_suffix
        data["normal"] = prefix + normal_suffix
        data["color"] = "#ffffff"

    def foliage(amount=0.022, tint=0.0):
        data.update(wind=amount, vertex_tint=tint, two_sided=True)

    if family == "CloverBank":
        is_clover = model == "SM_BankClover"
        prefix = "T_BotanicalLeafVeins" if is_clover else "T_BotanicalBladeVeins"
        data.update(
            color="#96b653" if is_clover else "#a5bc59",
            roughness=0.61 if is_clover else 0.72,
            specular=0.40 if is_clover else 0.35,
            detail=prefix,
            normal=prefix + "_N",
            normal_strength=0.32,
            unreal_material="M_BankClover" if is_clover else "M_BankSatinGrass",
        )
        foliage(0.023 if is_clover else 0.026, 0.42)
    elif family == "ValleyFlora":
        instance = FLORA_SLOT_MATERIALS.get(slot)
        if instance:
            base, backlight, roughness = FLORA_INSTANCES[instance]
            data.update(color=from_linear(base), backlight=from_linear(backlight), roughness=roughness)
            data["unreal_material"] = instance
        if slot == "M_ValleyFlora":
            maps("T_ValleyFlora", "_BC", "_N")
            data.update(roughness_map="T_ValleyFlora_R")
        elif slot == "Lavender" and model == "SM_Crossing_ArchingBellflowers":
            data.update(albedo="T_Bellflower_PetalFolds", unreal_material="MI_Bellflower_FlutedLavender")
        elif slot == "Leaf":
            data.update(detail="T_BotanicalLeafVeins", normal="T_BotanicalLeafVeins_N")
        foliage(0.024)
    elif family == "ValleyUnderstory":
        if slot == "M_CushionMoss":
            maps("T_CushionMoss")
            data.update(surface="T_CushionMoss_ORM")
        elif slot == "M_WoodlandBotanical":
            maps("T_WoodlandBotanical")
            data.update(surface="T_WoodlandBotanical_ORM")
            foliage(0.014)
        elif slot == "MossBase":
            maps("T_BirchPlush", "_Color", "_N")
        elif slot in ("UnderNap", "TipNap"):
            data.update(
                detail="T_BirchPlush_Nap", roughness=0.88, two_sided=True,
                cutout=0.49 if slot == "UnderNap" else 0.57,
            )
        elif model != "SM_Painted_Pebbles":
            if slot in ("Grass", "Leaf", "Clover"):
                prefix = "T_BotanicalBladeVeins" if slot == "Grass" else "T_BotanicalLeafVeins"
                data.update(detail=prefix, normal=prefix + "_N")
            foliage(0.018, 0.36 if slot in ("Grass", "Leaf", "Clover") else 0.0)
    elif slot in ("M_ValleyCreekstone", "M_ValleyMoss", "M_ValleyBoulderMoss", "M_ValleyRootBark"):
        prefix = "T_" + slot[2:]
        if family == "ValleyCliffs" and slot == "M_ValleyMoss":
            prefix = "T_ValleyBoulderMoss"
        maps(prefix)
        if prefix.endswith("BoulderMoss"):
            data.update(surface=prefix + "_Surface", height_map=prefix + "_Height", height_scale=1.6)
        else:
            data.update(roughness_map=prefix + "_Roughness")
    elif slot == "M_ValleyMossTips":
        foliage(0.0)
    elif slot in ("M_ElderBark", "M_HazelLeaf"):
        prefix = "T_" + slot[2:]
        maps(prefix)
        data.update(surface=prefix + "_ORM")
        if slot == "M_HazelLeaf":
            foliage(0.0)
    elif slot.startswith("M_AmberStep_"):
        maps("T_AmberStep")
        data.update(surface="T_AmberStep_ORM")
    elif slot.startswith("M_LotusBloom_"):
        data.update(color="#ffffff", vertex_tint=1.0, two_sided=True)
    elif family == "ValleyLotus" and slot == "Leaf":
        maps("T_LotusLeaf", "_Color", "_Normal")
        data.update(two_sided=True)
    elif slot in ("MI_Forest_RootBark", "MI_Forest_Birch"):
        data.update(albedo="T_Forest_BarkGrooves_D", normal="T_Forest_BarkGrooves_N")
    elif slot == "MI_Forest_MossBank":
        data.update(albedo="T_Forest_MossCarpet_D", normal="T_Forest_MossCarpet_N")
    elif slot == "M_ValleyCreekGravel":
        maps("T_ValleyPebbles", "_D", "_N")
        data["roughness"] = 0.88
    elif slot in ("MI_Forest_MossBoulder", "MI_Forest_RiverPebble"):
        data.update(albedo="T_Forest_CreekPebbles_D", normal="T_Forest_CreekPebbles_N")
    elif slot == "M_Forest_DewDrop":
        data.update(transparent=True)
    elif slot in (
        "MI_Forest_Clover", "MI_Forest_StrawberryLeaf", "MI_Forest_LavenderFlower",
        "MI_Forest_BlossomWhite", "MI_Forest_BlossomCenter", "MI_Forest_PinkPetal",
    ):
        movable = family != "UnrealExtract" and not any(word in model for word in ("Canopy", "RootArch"))
        foliage(0.016 if movable else 0.0)

    if not has_color:
        data.pop("vertex_tint", None)
    return data


def indexed_textures(source, output, required):
    index = {}
    for family in TEXTURE_FAMILIES:
        for entry in sorted((source / family).rglob("T_*.png")):
            index[entry.stem] = entry
    boulder_height = "T_ValleyBoulderMoss_Height"
    missing = required - index.keys() - {boulder_height}
    if missing:
        raise ValueError(f"Missing material maps: {sorted(missing)}")
    result = {}
    for stem, src in sorted(index.items()):
        if stem not in required and not (
            src.parent.name == "ValleyGround" and stem != "T_Valley_PathMask"
        ):
            continue
        collection = src.parent.parent.name if src.parent.name == "Textures" else src.parent.name
        relative = Path("textures") / snake(collection) / src.name
        dest = output / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists() or not filecmp.cmp(src, dest, shallow=False):
            shutil.copyfile(src, dest)
        result[stem] = {"path": relative.as_posix(), "source": src.relative_to(source).as_posix()}
        if stem.lower().endswith(("_n", "_normal", "_normalgl")):
            result[stem]["normal_y"] = "opengl" if stem.endswith("_NormalGL") or stem in OPENGL_NORMALS else "directx"
    if boulder_height in required:
        packed = index["T_ValleyBoulderMoss_Surface"]
        relative = Path("textures/valley_cliffs") / (boulder_height + ".png")
        original = bpy.data.images.load(str(packed))
        original.colorspace_settings.name = "Non-Color"
        width, height = original.size
        values = array("f", [0.0]) * (width * height * 4)
        original.pixels.foreach_get(values)
        blue = values[2::4]
        values[0::4] = blue
        values[1::4] = blue
        output_image = bpy.data.images.new(boulder_height, width, height, alpha=False, is_data=True)
        output_image.pixels.foreach_set(values)
        output_image.filepath_raw = str(output / relative)
        output_image.file_format = "PNG"
        output_image.save()
        result[boulder_height] = {
            "path": relative.as_posix(),
            "source": packed.relative_to(source).as_posix(),
            "channel": "blue",
        }
    return result


def configure_import(path):
    import_file = path.with_suffix(".glb.import")
    line = f'import_script/path="{IMPORTER}"'
    if import_file.exists():
        config = import_file.read_text(encoding="utf-8")
        updated = re.sub(r'^import_script/path=.*$', line, config, flags=re.MULTILINE)
        if updated == config:
            return
    else:
        updated = '[remap]\n\nimporter="scene"\ntype="PackedScene"\n\n[params]\n\n' + line + "\n"
    import_file.write_text(updated, encoding="utf-8", newline="\n")


def configure_texture(path, normal_y):
    import_file = path.with_suffix(".png.import")
    config = (
        import_file.read_text(encoding="utf-8") if import_file.exists()
        else '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
    )
    updated = config
    options = {
        "mipmaps/generate": "true",
        "detect_3d/compress_to": "0",
    }
    if normal_y:
        options["compress/normal_map"] = "1"
        options["process/normal_map_invert_y"] = "true" if normal_y == "directx" else "false"
    for key, value in options.items():
        line = f"{key}={value}"
        pattern = rf"^{re.escape(key)}=.*$"
        updated, replaced = re.subn(pattern, line, updated, flags=re.MULTILINE)
        if not replaced:
            updated += line + "\n"
    if updated != config or not import_file.exists():
        import_file.write_text(updated, encoding="utf-8", newline="\n")


def obj_geometry(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    godot = [(point.x, point.z, -point.y) for point in points]
    low = [min(v[axis] for v in godot) for axis in range(3)]
    high = [max(v[axis] for v in godot) for axis in range(3)]
    return {
        "bounds_min": [round(v, 5) for v in low],
        "bounds_max": [round(v, 5) for v in high],
        "dimensions": [round(b - a, 5) for a, b in zip(low, high)],
    }


def fallback_material(name):
    material = bpy.data.materials.new(name)
    if material.node_tree is None:
        material.use_nodes = True
    return material


def read_native_glb(source_path, dest, family):
    """Preserve Unreal's vertex buffers, tangents and material IDs verbatim."""
    raw = source_path.read_bytes()
    magic, version, length, json_length, kind = struct.unpack_from("<4sIIII", raw)
    if (magic, version, length, kind) != (b"glTF", 2, len(raw), 0x4E4F534A):
        raise ValueError(f"Invalid Unreal GLB: {source_path}")
    doc = json.loads(raw[20:20 + json_length])
    used = {
        item["material"]
        for mesh in doc["meshes"] for item in mesh["primitives"] if "material" in item
    }
    known_slots = NATIVE_STATIC_SLOTS.get(source_path.stem, ())
    result = {}
    for index in sorted(used):
        record = doc["materials"][index]
        slot = known_slots[index] if index < len(known_slots) else record.get("name") or f"Material_{index}"
        forest_slots = ("MI_Forest_RootBark", "MI_Forest_StrawberryLeaf", "MI_Forest_MossBank")
        canonical = next((name for name in forest_slots if name in slot), slot)
        material = fallback_material(canonical)
        if "baseColorFactor" in record.get("pbrMetallicRoughness", {}):
            node = material.node_tree.nodes.get("Principled BSDF")
            node.inputs["Base Color"].default_value = record["pbrMetallicRoughness"]["baseColorFactor"]
        config = material_config(family, source_path.stem, material, False)
        key = f"Woodland_{index:02d}"
        record["name"] = key
        result[key] = {"source_slot": slot, **config}
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    tail = raw[20 + json_length:]
    header = struct.pack("<4sIIII", magic, version, 20 + len(payload) + len(tail), len(payload), kind)
    dest.write_bytes(header + payload + tail)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source_path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    return result, obj_geometry(meshes)


def export_model(source_path, dest, family):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if source_path.suffix.lower() == ".glb":
        return read_native_glb(source_path, dest, family)

    bpy.ops.import_scene.fbx(filepath=str(source_path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError(f"No geometry: {source_path}")
    dimensions = obj_geometry(meshes)
    result = {}
    processed = set()
    for obj in meshes:
        if not obj.data.materials:
            name = "MI_Forest_RootBark" if "RootWalkShell" in source_path.stem else source_path.stem
            obj.data.materials.append(fallback_material(name))
        for slot in obj.material_slots:
            material = slot.material
            if material in processed:
                continue
            processed.add(material)
            source_slot = material.name
            config = material_config(family, source_path.stem, material, bool(obj.data.color_attributes))
            key = f"Woodland_{len(result):02d}"
            if not obj.data.uv_layers and config.get("albedo"):
                config["triplanar"] = True
            result[key] = {"source_slot": source_slot, **config}
            material.name = key
            material.node_tree.nodes.clear()
            node = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
            output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
            material.node_tree.links.new(node.outputs[0], output.inputs["Surface"])
            node.inputs["Base Color"].default_value = color_factor(config["color"])
            node.inputs["Roughness"].default_value = config["roughness"]
            material.use_backface_culling = not config.get("two_sided", False)
    # The FBX importer already converts its centimetre or metre units. Bake scale only.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
        triangulate = obj.modifiers.new(name="Export triangulation", type="TRIANGULATE")
        triangulate.keep_custom_normals = True
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(
        filepath=str(dest), export_format="GLB", use_selection=True, export_yup=True,
        export_normals=True, export_tangents=True, export_vertex_color="ACTIVE",
        export_all_vertex_colors=False, export_animations=False, export_cameras=False,
        export_lights=False, export_apply=True,
    )
    return result, dimensions


def model_sources(source, extraction):
    for category, blend in FAMILIES.items():
        family = category.split("/")[-1]
        for path in sorted((source / category).glob("SM_*.fbx")):
            if path.stem in EXCLUDED:
                continue
            if path.stem == "SM_Valley_LotusBloom":
                yield path, family, "ValleyLotus/Valley_LotusBloom.blend"
            else:
                yield path, family, blend
    metadata_path = extraction / "Metadata/unreal_asset_metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    trees = metadata["proceduralTrees"]
    if len(trees) != 6:
        raise ValueError(f"Expected six procedural trees in {metadata_path}, found {len(trees)}")
    native_paths = [extraction / "Meshes" / (name + ".glb") for name in NATIVE_STATIC_SLOTS]
    native_paths.extend(extraction / tree["outputFile"] for tree in trees)
    for path in native_paths:
        if not path.is_file():
            raise FileNotFoundError(f"Missing Unreal woodland export: {path}")
        yield path, "UnrealExtract", None


def export_library(source, extraction, output):
    sources = list(model_sources(source, extraction))

    manifest = {
        "coordinates": "Godot Y-up, meters; bounds are local to the GLB scene.",
        "unreal_reference": [
            "UnrealExtract/" + path.relative_to(extraction).as_posix()
            for path in sorted((extraction / "Metadata").glob("*.json"))
        ],
        "ground_reference": {
            "moss_ground": {"repeat_m": 1.9435, "texture_prefix": "T_MossGround01_"},
            "woodland_path": {"repeat_m": 1.221, "texture_prefix": "T_WoodlandPath_"},
        },
        "models": {},
    }
    required = set()
    for path, family, blend in sources:
        model_name = path.stem.removeprefix("SM_").removeprefix("Forest_").removeprefix("Valley_")
        relative = Path("forest" if family.startswith("Forest") else snake(family)) / (snake(model_name) + ".glb")
        key = relative.as_posix()
        if key in manifest["models"]:
            raise ValueError(f"Duplicate Godot model path: {key}")
        dest = output / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        materials, dimensions = export_model(path, dest, family)
        for config in materials.values():
            required.update(
                config[k] for k in ("albedo", "normal", "detail", "roughness_map", "surface", "height_map")
                if k in config
            )
        manifest["models"][key] = {
            "source": path.relative_to(source).as_posix() if blend else (
                "UnrealExtract/" + path.relative_to(extraction).as_posix()
            ),
            "editable_source": blend,
            "materials": materials,
            **dimensions,
        }
        if path.stem == "SM_Valley_RootWalkShell":
            manifest["models"][key]["role"] = "collision reference"
    manifest["textures"] = indexed_textures(source, output, required)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=SOURCE_ART)
    parser.add_argument("--unreal-extract", type=Path, default=SOURCE_ART / "UnrealExtract")
    parser.add_argument("--output-root", type=Path, default=OUTPUT)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source = args.source_root.resolve()
    extraction = args.unreal_extract.resolve()
    output = args.output_root.resolve()
    if not all((source / family).is_dir() for family in FAMILIES):
        raise ValueError(f"Incomplete woodland source art: {source}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="woodland-export-", dir=output.parent) as scratch:
        staging = Path(scratch)
        # Godot should see the complete material catalog before it scans the GLBs.
        manifest = export_library(source, extraction, staging)
        files = sorted(staging.rglob("*"))
        for src in files:
            if src.is_file() and src.suffix != ".glb":
                dest = output / src.relative_to(staging)
                dest.parent.mkdir(parents=True, exist_ok=True)
                src.replace(dest)
        for texture in manifest["textures"].values():
            configure_texture(output / texture["path"], texture.get("normal_y"))
        for src in staging.rglob("*.glb"):
            dest = output / src.relative_to(staging)
            dest.parent.mkdir(parents=True, exist_ok=True)
            configure_import(dest)
            src.replace(dest)
    print(f"Wrote {len(manifest['models'])} models and {len(manifest['textures'])} maps to {output}")


if __name__ == "__main__":
    main()
