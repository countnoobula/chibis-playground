import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

extract=Path(__file__).resolve().parents[1]
source=extract.parent/"FBX/ForestFoliage"
meta=json.loads((extract/"Metadata/unreal_asset_metadata.json").read_text(encoding="utf8"))
dest=Path(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else extract/"Meshes"
dest.mkdir(parents=True,exist_ok=True)

def imported_meshes(operator, path):
    before=set(bpy.context.scene.objects)
    operator(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before and obj.type=="MESH"]

def recipe_material(name, color):
    material=bpy.data.materials.new(name)
    if material.node_tree is None:
        material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=(*color,1.0)
    shader.inputs["Roughness"].default_value=0.72
    return material

for tree in meta["proceduralTrees"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    name=Path(tree["outputFile"]).stem
    bark=recipe_material("MI_Forest_RootBark",(0.28,0.15,0.08))
    leaves=recipe_material("MI_Forest_StrawberryLeaf",(0.36,0.62,0.16))
    trunk=imported_meshes(bpy.ops.import_scene.gltf, extract/tree["dynamicTrunk"]["exportFile"])
    assert len(trunk)==1
    for obj in trunk:
        obj.name="Trunk"
        obj.data.materials.clear()
        obj.data.materials.append(bark)
    meshes=list(trunk)
    for component in tree["components"]:
        objects=imported_meshes(bpy.ops.import_scene.fbx,source/(component["mesh"]+".fbx"))
        assert len(objects)==1
        location=component["relativeLocationCm"]
        angles=component["relativeRotationDeg"]
        scale=component["relativeScale"]
        placement=(
            Matrix.Translation(Vector((location["x"],-location["y"],location["z"]))*0.01)
            @ Matrix.Rotation(math.radians(-angles["yaw"]),4,"Z")
            @ Matrix.Rotation(math.radians(-angles["pitch"]),4,"Y")
            @ Matrix.Rotation(math.radians(angles["roll"]),4,"X")
            @ Matrix.Diagonal((scale["x"],scale["y"],scale["z"],1))
        )
        for obj in objects:
            assert len(obj.data.materials)==2
            obj.name=component["component"]
            obj.matrix_world=placement@obj.matrix_world
            for slot in obj.material_slots:
                slot.material=leaves if "StrawberryLeaf" in slot.material.name else bark
            meshes.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
        triangulate=obj.modifiers.new(name="Export triangulation",type="TRIANGULATE")
        triangulate.keep_custom_normals=True
    bpy.context.view_layer.objects.active=trunk[0]
    bpy.ops.export_scene.gltf(
        filepath=str(dest/(name+".glb")), export_format="GLB", use_selection=True,
        export_normals=True, export_tangents=True, export_animations=False, export_apply=True,
        export_cameras=False, export_lights=False
    )
    print("VERIFY",name,[obj.name for obj in meshes],flush=True)

