# First Steps Terrain3D

`creek_terrain.tscn` is the playable valley terrain. `woodland_terrain_starter.tscn` is an independent flat starter for designers, and `terrain_swatches_preview.tscn` shows the four named paint slots under the valley starter lighting. The two scenes use separate Terrain3D data directories.

## Terrain data

- World axes: Godot Y-up, one Terrain3D vertex per meter.
- Region size: 64 m. Each dataset contains four editable regions over X/Z `−64…+64 m`.
- Valley spawn: `(0, 5, +34)`, facing north along `−Z`.
- Dry approach: `(0, +34)` → `(−5, +18)` → `(−10, +8)` → `(−15, 0)` → `(−18, −8)` in X/Z.
- Creek centerline turns through `(-22, -22)`, `(-14, -18)`, `(-8, -17)`, then exits southeast. Keep the later water shelf, pool and bank dressing within this bend; the trail ends on its northwest bank.
- `valley_data/` is reserved for the playable valley. `designer_starter_data/` has four material patches and is independent.

## Starting another independent level

Treat `woodland_terrain_starter.tscn` and `designer_starter_data/` as a template pair. Do not paint into the template directly. Before editing terrain for a new level:

1. Copy `woodland_terrain_starter.tscn` into the new level's terrain folder and rename the copy for that level.
2. Copy the entire `designer_starter_data/` directory, including all region `.res` files, into the same folder. Give the copy a level-specific name such as `creekside_data/`.
3. Open the copied terrain scene as text or in the Inspector and change `data_directory` to the copied folder's full `res://` path (for example, `res://levels/creekside/terrain/creekside_data`) before opening it for painting. Confirm that it points to the new folder, not `designer_starter_data/`.
4. Add the copied terrain scene to the new level and paint only that copy. Keep its `assets` and `material` references pointed at `woodland_terrain_assets.tres` and `woodland_terrain_material.tres` for the shared four-slot palette.

Duplicate the assets or material resources only when the level needs its own texture slots or shader settings. If you do, update the copied scene's resource paths and leave the shared palette unchanged. Each level should have its own copied region directory so edits cannot alter the reusable template or another level.

## Paint slots

Terrain3D asset IDs are stable and ordered left to right in the preview:

| ID | Name | Woodland source |
| --- | --- | --- |
| 0 | Meadow Grass | Moss Ground 01 |
| 1 | Warm Path | Woodland Path |
| 2 | Creek Earth | Valley Earth |
| 3 | Mossy Stone | Valley Moss |

The source maps are packed into `materials/*_albedo_height.png` and `materials/*_normal_roughness.png` for Terrain3D. DirectX normal maps are converted to OpenGL green-channel orientation. Texture import companions should keep VRAM compression enabled, normal-map processing disabled, and mipmaps enabled because Terrain3D samples the packed normal and roughness channels itself.

## Local grass and dirt relief

On the First Steps Valley root, **Relief Enabled** toggles surface displacement and its height-dependent shading and **Relief Tessellation Level** controls nearby mesh density (desktop default 6, finest vertex spacing 1.56 cm). The valley material uses displacement scale 0.42. Meadow Grass uses the cream flower paint as its relief mask. Warm Path uses the blue channel of its surface map for rounded stone tops and recessed grout. The woodland texture packer bakes both masks. The effect follows Chibi, stays at full strength within 3 m, and fades out by 6 m. Creek Earth and Mossy Stone use flat displacement. Ground contact and Scene Builder placement use the sculpted terrain. Android and iOS use the base mesh pending device profiling.

## Regenerating the first sculpt

Run from the project root with Godot 4.7.2 after enabling the Terrain3D plugin:

```powershell
godot --headless --path . --script res://tools/pack_woodland_terrain_textures.gd
godot --headless --path . --script res://tools/generate_terrain_data.gd -- --replace
```

The terrain tool refuses to overwrite existing regions unless `--replace` is supplied. Use the Terrain3D editor brushes for normal designer edits so the saved `.res` regions remain the source of truth. `Full / Editor` collision is enabled for placement raycasts and gameplay contact.
