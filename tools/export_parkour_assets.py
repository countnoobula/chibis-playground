"""Read-only export of ChibiRunner (all 36 animations verified non-static),
rooftop climbing stations, route JSON, and audio from Unreal Parkour SourceArt
into the Godot chibi project (in meters, Godot Y-up).

Usage:
    blender --background --python tools/export_parkour_assets.py
    blender --background --python tools/export_parkour_assets.py -- --source-root PATH --output-root PATH

The default source is the sibling Parkour-Art-Archive/SourceArt when present,
otherwise the original Unreal project SourceArt directory. Output defaults to
the Godot project root and is written beneath its assets/ directory.
"""

import argparse
import json
import math
import runpy
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix

GODOT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PARKOUR_SRC = Path(r"c:\Users\count\Documents\Unreal Projects\Parkour\SourceArt")
ARCHIVE_PARKOUR_SRC = GODOT_ROOT.parent / "Parkour-Art-Archive" / "SourceArt"
PARKOUR_SRC = ARCHIVE_PARKOUR_SRC if ARCHIVE_PARKOUR_SRC.is_dir() else DEFAULT_PARKOUR_SRC
OUTPUT_ROOT = GODOT_ROOT
ASSETS_DIR = OUTPUT_ROOT / "assets"


def configure_paths():
    """Read optional source/output roots passed after Blender's `--` separator."""
    global PARKOUR_SRC, OUTPUT_ROOT, ASSETS_DIR

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-root",
        type=Path,
        default=PARKOUR_SRC,
        help="Parkour SourceArt directory (defaults to the sibling archive when present).",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=GODOT_ROOT,
        help="Godot project or temporary output root; assets are written beneath its assets/ directory.",
    )
    blender_args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = parser.parse_args(blender_args)

    PARKOUR_SRC = args.source_root.expanduser().resolve()
    OUTPUT_ROOT = args.output_root.expanduser().resolve()
    ASSETS_DIR = OUTPUT_ROOT / "assets"

    if not PARKOUR_SRC.is_dir():
        parser.error(f"Source root does not exist or is not a directory: {PARKOUR_SRC}")
    required_input = PARKOUR_SRC / "ChibiRunner.blend"
    if not required_input.is_file():
        parser.error(f"Source root is missing required input: {required_input}")
    try:
        ASSETS_DIR.relative_to(PARKOUR_SRC)
    except ValueError:
        pass
    else:
        parser.error(f"Output assets directory must not be inside SourceArt: {ASSETS_DIR}")

# FBX clips that either do not exist in ChibiRunner.blend or are newer/animated versions
# (BeamIdle & BeamWalk inside ChibiRunner.blend are static 0-motion placeholders!).
FBX_ANIM_OVERRIDES = {
    "Anim_Chibi_BeamIdle": "FBX/ChibiRunner_BeamIdle.fbx",
    "Anim_Chibi_BeamWalk": "FBX/ChibiRunner_BeamWalk.fbx",
    "Anim_Chibi_Swim": "FBX/Anim_Chibi_Swim.fbx",
    "Anim_Chibi_SurfaceSwim": "FBX/Anim_Chibi_SurfaceSwim.fbx",
    "Anim_Chibi_TreadWater": "FBX/Anim_Chibi_TreadWater.fbx",
    "Anim_Chibi_BounceAir": "FBX/ChibiRunner_BounceAir.fbx",
    "Anim_Chibi_PolePerch": "FBX/ChibiRunner_PolePerch.fbx",
    "Anim_Chibi_ZipGlide": "FBX/ChibiRunner_ZipGlide.fbx",
    "Anim_Chibi_RopeSwing": "FBX/ChibiRunner_RopeSwing.fbx",
    "Anim_Chibi_RopeSwingFwd": "FBX/ChibiRunner_RopeSwingFwd.fbx",
    "Anim_Chibi_RopeSwingBack": "FBX/ChibiRunner_RopeSwingBack.fbx",
    "Anim_Chibi_SlothHang": "FBX/AS_Chibi_SlothHang.fbx",
    "Anim_Chibi_SlothCrawl": "FBX/AS_Chibi_SlothCrawl.fbx",
    "Anim_Chibi_SlothDrop": "FBX/AS_Chibi_SlothDrop.fbx",
}


def get_primary_bag(action):
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                return bag
    return None


def iter_action_fcurves(action):
    if hasattr(action, "fcurves"):
        for fc in action.fcurves:
            yield fc
        return
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                for fc in bag.fcurves:
                    yield fc


def get_action_frame_range(action):
    lo, hi = 1e9, -1e9
    found = False
    for fc in iter_action_fcurves(action):
        if not fc.data_path.startswith("pose.bones["):
            continue
        for kp in fc.keyframe_points:
            found = True
            lo = min(lo, kp.co[0])
            hi = max(hi, kp.co[0])
    if not found:
        r = action.frame_range
        return r[0], max(r[1], r[0] + 1.0)
    return lo, max(hi, lo + 1.0)


def scale_action_locations(action, factor):
    for fc in iter_action_fcurves(action):
        if fc.data_path.startswith("pose.bones[") and fc.data_path.endswith(".location"):
            for kp in fc.keyframe_points:
                kp.co[1] *= factor
                kp.handle_left[1] *= factor
                kp.handle_right[1] *= factor


def convert_euler_action_to_quaternion(action):
    """Converts pose.bones[*].rotation_euler fcurves in a Blender 5.x action into
    pose.bones[*].rotation_quaternion so every action shares one unified QUATERNION mode."""
    bag = get_primary_bag(action)
    if bag is None:
        return

    euler_groups = {}
    for fc in list(bag.fcurves):
        if fc.data_path.startswith("pose.bones[") and fc.data_path.endswith(".rotation_euler"):
            euler_groups.setdefault(fc.data_path, {})[fc.array_index] = fc

    if not euler_groups:
        return

    for dp, axes in euler_groups.items():
        frames = sorted({kp.co[0] for fc in axes.values() for kp in fc.keyframe_points})
        if not frames:
            continue
        q_dp = dp.replace(".rotation_euler", ".rotation_quaternion")
        q_curves = [bag.fcurves.new(data_path=q_dp, index=i) for i in range(4)]
        prev_q = None
        for f in frames:
            ex = axes[0].evaluate(f) if 0 in axes else 0.0
            ey = axes[1].evaluate(f) if 1 in axes else 0.0
            ez = axes[2].evaluate(f) if 2 in axes else 0.0
            q = Euler((ex, ey, ez), "XYZ").to_quaternion()
            if prev_q is not None and prev_q.dot(q) < 0.0:
                q = -q
            prev_q = q
            for i in range(4):
                kp = q_curves[i].keyframe_points.insert(f, q[i], options={"FAST"})
                kp.interpolation = "LINEAR"
        for fc in axes.values():
            bag.fcurves.remove(fc)


def rectify_quaternion_hemispheres(action):
    """Ensure every pose bone rotation_quaternion track stays continuous (no q -> -q double-cover jumps)
    so slerp/crossfades never spin 360 deg or flip upside-down animations right-side-up."""
    bag = get_primary_bag(action)
    if bag is None:
        return
    quat_groups = {}
    for fc in bag.fcurves:
        if fc.data_path.startswith("pose.bones[") and fc.data_path.endswith(".rotation_quaternion"):
            quat_groups.setdefault(fc.data_path, {})[fc.array_index] = fc
    for dp, axes in quat_groups.items():
        if len(axes) < 4:
            continue
        count = min(len(axes[i].keyframe_points) for i in range(4))
        if count < 2:
            continue
        prev = [axes[i].keyframe_points[0].co[1] for i in range(4)]
        for k in range(1, count):
            curr = [axes[i].keyframe_points[k].co[1] for i in range(4)]
            dot = sum(prev[i] * curr[i] for i in range(4))
            if dot < 0.0:
                curr = [-c for c in curr]
                for i in range(4):
                    kp = axes[i].keyframe_points[k]
                    kp.co[1] = curr[i]
                    kp.handle_left[1] = -kp.handle_left[1]
                    kp.handle_right[1] = -kp.handle_right[1]
            prev = curr


def strip_object_fcurves(action):
    """Remove object-level location/rotation/scale curves imported from FBX so only pose.bones[*] animate."""
    bag = get_primary_bag(action)
    if bag is None:
        return
    for fc in list(bag.fcurves):
        if not fc.data_path.startswith("pose.bones["):
            bag.fcurves.remove(fc)


def bind_action_slot_to_armature(action, arm_obj):
    """Ensure Blender 5.3 Action Slot targets Armature cleanly."""
    if not hasattr(action, "slots") or not action.slots:
        return None
    slot = action.slots[0]
    try:
        slot.name_display = arm_obj.name
    except Exception:
        pass
    return slot


def measure_rest_pose_diff(src_arm, dst_arm):
    """Compare world rest bone heads (meters) between an imported FBX armature and ChibiRunner.blend's armature."""
    ref_heads = {b.name: dst_arm.matrix_world @ b.head_local for b in dst_arm.data.bones}
    max_diff = 0.0
    for b in src_arm.data.bones:
        if b.name in ref_heads:
            src_h = src_arm.matrix_world @ b.head_local
            d = (src_h - ref_heads[b.name]).length * 0.01
            if d > max_diff:
                max_diff = d
    return max_diff


def retarget_action_between_armatures(src_arm, dst_arm, src_action, target_name):
    """Retarget an action from an FBX armature with a baked non-rest bind pose (such as
    Anim_Chibi_Swim/SurfaceSwim/TreadWater) onto dst_arm (in shared scene space) by matching
    world-space bone transforms on every frame and solving dst_arm's local pose basis algebraically."""
    start, end = get_action_frame_range(src_action)
    f_start = int(round(start))
    f_end = int(round(end))

    src_arm.animation_data_create()
    src_arm.animation_data.action = src_action
    if hasattr(src_arm.animation_data, "action_slot") and hasattr(src_action, "slots") and src_action.slots:
        src_arm.animation_data.action_slot = src_action.slots[0]

    new_act = bpy.data.actions.new(name=target_name)
    new_act.use_fake_user = True
    dst_arm.animation_data_create()
    dst_arm.animation_data.action = new_act

    # Precompute dst rest matrices (dst armature space) and parent-before-child bone traversal order
    dst_world_inv = dst_arm.matrix_world.inverted()
    rest_mats = {b.name: b.matrix_local.copy() for b in dst_arm.data.bones}
    rest_inv = {n: m.inverted() for n, m in rest_mats.items()}
    ordered_bones = []
    visited = set()

    def _visit(b):
        if b.name in visited:
            return
        if b.parent is not None:
            _visit(b.parent)
        visited.add(b.name)
        ordered_bones.append(b.name)

    for b in dst_arm.data.bones:
        _visit(b)

    # Reset dst_arm pose before baking
    for pb in dst_arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)

    src_bones = set(src_arm.pose.bones.keys())

    for frame in range(f_start, f_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()

        # Extract bone transforms expressed directly in dst_arm's armature space (scale-normalized)
        target_mats = {}
        for bn in ordered_bones:
            if bn not in src_bones:
                continue
            mw = dst_world_inv @ src_arm.matrix_world @ src_arm.pose.bones[bn].matrix
            t_dst, q_dst, _ = mw.decompose()
            target_mats[bn] = Matrix.Translation(t_dst) @ q_dst.normalized().to_matrix().to_4x4()

        # Solve each dst bone's matrix_basis relative to dst_arm's upright rest pose
        for bn in ordered_bones:
            if bn not in target_mats:
                continue
            dst_b = dst_arm.data.bones[bn]
            dst_pb = dst_arm.pose.bones[bn]
            M_i = target_mats[bn]
            if dst_b.parent is not None and dst_b.parent.name in target_mats:
                p_name = dst_b.parent.name
                M_p = target_mats[p_name]
                B_i = rest_inv[bn] @ rest_mats[p_name] @ M_p.inverted() @ M_i
            else:
                B_i = rest_inv[bn] @ M_i

            loc, quat, _ = B_i.decompose()
            quat.normalize()
            dst_pb.rotation_quaternion = quat
            dst_pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if bn in ("root", "pelvis") or loc.length > 0.05:
                dst_pb.location = loc
                dst_pb.keyframe_insert(data_path="location", frame=frame)

    # Verify retarget fidelity at mid-clip (convert cm -> m)
    mid_f = (f_start + f_end) // 2
    bpy.context.scene.frame_set(mid_f)
    bpy.context.view_layer.update()
    max_err_m = 0.0
    for bn in ("pelvis", "spine_01", "head", "hand_l", "hand_r", "foot_l", "foot_r"):
        if bn in src_arm.pose.bones and bn in dst_arm.pose.bones:
            src_p = (src_arm.matrix_world @ src_arm.pose.bones[bn].matrix).translation
            dst_p = (dst_arm.matrix_world @ dst_arm.pose.bones[bn].matrix).translation
            max_err_m = max(max_err_m, (src_p - dst_p).length * 0.01)
    print(f"[Export] Retargeted {target_name} ({f_start}..{f_end}): mid-clip max bone err = {max_err_m:.4f} m")

    # Clean up pose state on dst_arm
    dst_arm.animation_data.action = None
    for pb in dst_arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bind_action_slot_to_armature(new_act, dst_arm)
    return new_act


def measure_pose_motion(arm_obj, action):
    """Actually evaluate Armature pose bones across the action's frame range in Blender to verify motion."""
    arm_obj.animation_data.action = action
    if hasattr(arm_obj.animation_data, "action_slot") and hasattr(action, "slots") and action.slots:
        arm_obj.animation_data.action_slot = action.slots[0]
    start, end = get_action_frame_range(action)
    samples = [start, start + (end - start) * 0.25, start + (end - start) * 0.5, start + (end - start) * 0.75, end]
    bpy.context.scene.frame_set(int(round(samples[0])))
    bpy.context.view_layer.update()
    base_quats = {pb.name: pb.rotation_quaternion.copy() for pb in arm_obj.pose.bones}
    max_deg = 0.0
    for f in samples[1:]:
        bpy.context.scene.frame_set(int(round(f)))
        bpy.context.view_layer.update()
        for pb in arm_obj.pose.bones:
            ang = math.degrees(base_quats[pb.name].rotation_difference(pb.rotation_quaternion).angle)
            if ang > max_deg:
                max_deg = ang
    arm_obj.animation_data.action = None
    return max_deg


def export_chibi_runner():
    print("[Export] Loading ChibiRunner.blend (read-only)...")
    bpy.ops.wm.open_mainfile(filepath=str(PARKOUR_SRC / "ChibiRunner.blend"))

    arm = bpy.data.objects["Armature"]
    mesh = bpy.data.objects["SKM_ChibiRunner"]

    # Remove studio preview lights/cameras
    for obj in list(bpy.data.objects):
        if obj not in (arm, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)

    # Convert all existing ChibiRunner.blend Euler actions (except overridden ones) to Quaternion
    for act in list(bpy.data.actions):
        if act.name in FBX_ANIM_OVERRIDES:
            bpy.data.actions.remove(act)
        elif act.name.startswith("Anim_Chibi_"):
            convert_euler_action_to_quaternion(act)

    # Switch Armature pose bones to QUATERNION so blend + FBX actions evaluate identically!
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    # Import all 14 FBX override/extra animations
    existing_actions = set(bpy.data.actions.keys())
    for target_name, rel_fbx in FBX_ANIM_OVERRIDES.items():
        fbx_path = PARKOUR_SRC / rel_fbx
        if not fbx_path.exists():
            print(f"[Export][WARN] Missing FBX: {fbx_path}")
            continue
        before_objs = set(bpy.data.objects.keys())
        before_acts = set(bpy.data.actions.keys())
        bpy.ops.import_scene.fbx(
            filepath=str(fbx_path),
            use_anim=True,
            ignore_leaf_bones=True,
            automatic_bone_orientation=False,
        )
        new_objs = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before_objs]
        new_acts = [bpy.data.actions[n] for n in bpy.data.actions.keys() if n not in before_acts]

        src_arm = None
        picked = None
        for o in new_objs:
            if o.type == "ARMATURE" and o.animation_data and o.animation_data.action:
                src_arm = o
                picked = o.animation_data.action
                break
        if picked is None:
            for a in new_acts:
                if any(fc.data_path.startswith("pose.bones[") for fc in iter_action_fcurves(a)):
                    picked = a
                    break

        if picked is not None:
            rest_diff = measure_rest_pose_diff(src_arm, arm) if src_arm is not None else 0.0
            if src_arm is not None and rest_diff > 1e-4:
                print(f"[Export] {target_name} has baked non-rest pose (diff={rest_diff:.3f} m) -> retargeting onto Chibi rig...")
                picked = retarget_action_between_armatures(src_arm, arm, picked, target_name)
            else:
                strip_object_fcurves(picked)
                convert_euler_action_to_quaternion(picked)
                picked.name = target_name
                picked.use_fake_user = True
                bind_action_slot_to_armature(picked, arm)
                print(f"[Export] Imported & bound action {target_name} from {rel_fbx}")

        for o in new_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        for a in new_acts:
            if a != picked and a.name not in existing_actions:
                bpy.data.actions.remove(a)

    # Uniformly scale from centimetres to metres (0.01) WITHOUT rotating Armature,
    # preserving 100% exact local bone axes across both blend & FBX actions!
    # (ChibiModel is rotated 180 deg around Y inside VisualPivot in Godot so she faces -Z.)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    arm.scale = (0.01, 0.01, 0.01)
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    all_actions = sorted([a for a in bpy.data.actions if a.name.startswith("Anim_Chibi_")], key=lambda a: a.name)
    for act in all_actions:
        scale_action_locations(act, 0.01)
        rectify_quaternion_hemispheres(act)

    # Verify every single action actually drives Armature pose bones before pushing to NLA!
    arm.animation_data_create()
    for trk in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(trk)

    dead_anims = []
    for act in all_actions:
        deg = measure_pose_motion(arm, act)
        if deg < 1.0:
            dead_anims.append((act.name, deg))

        # Push onto NLA track with explicit Blender 5.3 action_slot assignment!
        trk = arm.animation_data.nla_tracks.new()
        trk.name = act.name
        start, end = get_action_frame_range(act)
        strip = trk.strips.new(act.name, int(round(start)), act)
        strip.action_frame_start = start
        strip.action_frame_end = end
        if hasattr(strip, "action_slot") and hasattr(act, "slots") and act.slots:
            strip.action_slot = act.slots[0]
        trk.mute = False

    if dead_anims:
        print(f"[Export][WARN] Low-motion actions detected: {dead_anims}")
    else:
        print(f"[Export] Verified ALL {len(all_actions)} actions have live bone motion!")

    out_dir = ASSETS_DIR / "characters"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_glb = out_dir / "chibi_runner.glb"

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm

    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_nla_strips_merged_animation_name="",
        export_morph=True,
        export_morph_normal=False,
        export_skins=True,
        export_materials="EXPORT",
    )
    gear_tools = runpy.run_path(str(GODOT_ROOT / "tools" / "export_chibi_dive_gear.py"))
    gear_tools["strip_runner_goggles"](out_glb)
    print(f"[Export] Wrote {out_glb} with {len(all_actions)} verified animations.")


def export_rooftop_stations():
    print("[Export] Loading RooftopClimbing.blend (read-only)...")
    bpy.ops.wm.open_mainfile(filepath=str(PARKOUR_SRC / "RooftopClimbing/RooftopClimbing.blend"))

    out_dir = ASSETS_DIR / "stations"
    out_dir.mkdir(parents=True, exist_ok=True)
    rot_z90 = Matrix.Rotation(math.pi / 2.0, 4, "Z")

    for col_name, out_name, undo_y in [
        ("SM_RooftopHolds", "rooftop_holds.glb", 0.0),
        ("SM_RooftopNet", "rooftop_net.glb", -250.0),
    ]:
        col = bpy.data.collections[col_name]
        bpy.ops.object.select_all(action="DESELECT")
        objs = list(col.objects)
        for o in objs:
            o.select_set(True)
            if undo_y != 0.0:
                o.location.y += undo_y
        bpy.context.view_layer.update()

        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        merged = bpy.context.active_object
        merged.name = col_name
        merged.matrix_world = Matrix.Scale(0.01, 4) @ rot_z90 @ merged.matrix_world
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

        out_glb = out_dir / out_name
        bpy.ops.export_scene.gltf(
            filepath=str(out_glb),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_materials="EXPORT",
        )
        print(f"[Export] Wrote {out_glb} (dims={[round(d, 3) for d in merged.dimensions]})")

    route_mod = runpy.run_path(str(PARKOUR_SRC / "RooftopClimbing/wall_route.py"))
    route_json = {
        "bands": [
            [[round(lat * 0.01, 4), round(z * 0.01, 4), 0.04] for (lat, z) in band]
            for band in route_mod["WALL_ROUTE"]
        ],
        "toe_chips": [
            [round(lat * 0.01, 4), round(z * 0.01, 4), 0.03]
            for (lat, z) in route_mod["TOE_CHIPS"]
        ],
    }
    json_path = out_dir / "wall_route.json"
    json_path.write_text(json.dumps(route_json, indent=2), encoding="utf-8")


def copy_audio():
    src_audio = PARKOUR_SRC / "Audio"
    dst_audio = ASSETS_DIR / "audio"
    dst_audio.mkdir(parents=True, exist_ok=True)
    for wav in sorted(src_audio.glob("*.wav")):
        shutil.copy2(wav, dst_audio / wav.name)


if __name__ == "__main__":
    configure_paths()
    export_chibi_runner()
    export_rooftop_stations()
    copy_audio()
    print("[Export] Done.")
