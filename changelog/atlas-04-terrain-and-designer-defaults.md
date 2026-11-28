# Checkpoint 4 · Terrain and designer defaults

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Implemented, verified and player-approved. The user approved the checkpoint 4 plan on 2026-11-28.

[Previous checkpoint](2026-11-27-working-atlas.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

Chibi can enter First Steps Valley from the atlas, walk from the trailhead to a creek bend, and see the materials a designer will paint with in later sections.

## Starting context

The chosen integration is Terrain3D 1.1.0 stable, with stock brushes for this slice. Confirm the upstream tag, MIT license, bundled binaries and installed Godot 4.7.2 compatibility when starting. Desktop Forward Mobile is the first rendering target. The village and Rooftop Gym retain their own visual identities.

- [roaming_atlas.json](<../config/roaming_atlas.json>)
- [chibi_runner.tscn](<../features/runner/chibi_runner.tscn>)
- [manifest.json](<../assets/environment/woodland/manifest.json>)
- [First Puzzle.png](<../source_art/concept_art/Moodboard/First Puzzle.png>)
- [Environment Style.png](<../source_art/concept_art/Moodboard/Environment Style.png>)

## Implementation checklist

- [x] Inspect the Terrain3D distribution before vendoring it under addons/. Record the exact version and license alongside the plugin. Test an isolated terrain scene after a fresh import before wiring the game entry point.
- [x] Pin a tagged [Scene Builder release](https://github.com/sci-comp/scene-builder/releases), retain its MIT license, and verify a clean editor import alongside Terrain3D. Enable terrain collision in the editor and confirm placement hits the bank after resculpting it.
- [x] Check in a First Steps collection with a woodland rock and a reusable gameplay scene such as the existing balance beam. In a disposable starter, place and rotate the rock on a slope, undo and redo, then save and reopen. Verify the transforms and exercise the placed beam with Chibi. Record both plugin versions and the editor and gameplay results.
- [x] Create a woodland starter with four named paint slots: Meadow Grass for open ground, Warm Path for the trail, Creek Earth for wet banks and Mossy Stone for exposed rock. Compare swatches under the valley lighting with First Puzzle and Environment Style.
- [x] Use a separate terrain-data directory for the playable valley. Instantiate the runner, spawn on a stable trailhead, sculpt the approach and leave room for a shallow shelf, pool and exit at the bend. Inspect sightlines from Chibi’s chase camera.
- [x] Create a second designer instance, paint a patch of every material, save and reopen both scenes. Check that the patches survive and the original valley data is independent.
- [x] Set the existing first_steps entry’s scene path and enabled flag in the atlas JSON. Enter through Title → Play → First Steps Valley and confirm Rooftop Gym still opens.

## Acceptance and evidence

Capture the trailhead and bend at runner height, the four labeled swatches and the independent-instance result. Record renderer, plugin build, import diagnostics and terrain data locations. Codex performs the paint, placement, persistence and play checks. The user reviews the palette and creek composition. The designer exercises the completed workflow at final handoff.

## Handoff and change history

- **Next action** Review the dry approach and creek bend in the Windows checkpoint build. Address feedback before checkpoint 5.
- **2026-11-28 planning decision** Use Scene Builder for individual props and interactive scenes, and Terrain3D for terrain and repeated foliage.
- **Changes and verification** See the dated record below.
- **Review** Player review pending. Record feedback and the approval commit and push here when the checkpoint closes.

## 2026-11-28 · Implementation and verification

- Integrated [Terrain3D 1.1.0 stable](../addons/terrain_3d/VENDOR.md) and [Scene Builder 0.2.4](../addons/scene_builder/UPSTREAM.md). The vendor records identify the exact upstream revisions, licenses and local compatibility fixes. CLI exports can resolve the Terrain3D version without selecting terrain in the editor.
- [First Steps Valley](../levels/first_steps/first_steps_valley.tscn) has a separate playable atlas entry, chase camera, journal area and fall recovery. The trail descends from 5.00 m at the spawn to a dry creek with room for a shelf, dive pool and exit. The sampled bed is at −0.70 m and the sampled west and east banks are at 2.88 m and 3.19 m.
- The [starter guide](../levels/first_steps/terrain/README.md) covers paint slots, source textures and independent data directories. An isolated regeneration saved and reopened four regions per dataset. All four material IDs persisted. A starter edit preserved the valley control sample. The saved trail and creek margins retained fractional overlay blends of 0.800 and 0.737. The four updated playable region files were checked against the isolated output by hash.
- The [Scene Builder collection](../Data/scene_builder/README.md) contains a woodland moss boulder and a configurable balance beam. Regression checks confirmed that a 6 m in-memory sculpt changed the collision hit by 6 m. The boulder kept its transform, rotation and scale on a 20.84° slope through placement, undo, redo and reopening. The editor undo manager was also exercised separately. A tuned 9.5 m beam with 0.19 m radius retained its settings and matching preview, and Chibi walked along a placed beam. See the [placement test](../tests/test_scene_builder_terrain_placement.gd) and [collection test](../tests/test_scene_builder_collection.gd).
- Godot 4.7.2 on the Windows RTX 4070 Ti SUPER produced an invisible terrain surface and pipeline errors under Forward Mobile with Direct3D 12. Forward Mobile with Vulkan rendered the surface and is now the Windows project default. A repeatable input sequence from Title through the atlas moved Chibi 41.42 m from the trailhead to the bend with grounded endpoints.
- The [menu test](../tests/test_menu_level_flow.gd) exercises the valley launch and fall recovery, the two pending postcards, controller selection, Rooftop Gym and pause/resume. Desktop at 1280 × 720 and simulated landscape touch at 844 × 390 passed. The gameplay regression suite passed 340 checks. The designer's first hands-on trial is at the final handoff.

### Review build and captures

Open the local [Windows checkpoint build](../builds/first_steps_checkpoint_4/Chibi.exe) and select **Play → First Steps Valley → Play**. Follow the path under the root arch. The build includes its PCK and native Terrain3D DLL in the same directory. Builds are local Git-ignored outputs.

- [Trailhead at spawn](../source_art/LayoutReview/first-steps-trailhead.jpg) · [Creek bend after walking](../source_art/LayoutReview/first-steps-bend.jpg) · [Four material swatches](../source_art/LayoutReview/first-steps-swatches.jpg)
- The Windows executable launched on an isolated desktop. The exported Windows debug pack passed the title-to-bend walk with Vulkan Forward Mobile at 1280 × 720. Desktop and simulated-touch menu regression tests passed the safe respawn check. The clean import of the checkpoint snapshot completed with a script-reload warning and no errors.
- The review build uses the verified runner snapshot taken before concurrent facial-expression work. During verification the live workspace had unresolved expression and emoji preloads from that separate change. The isolated build lets the user play the checkpoint independently.
- Shoreline dressing and the dry channel are ready for review. Water, swimming and caustic integration belong to checkpoint 5. Overall approval remains at 3/11 pending the user's review of checkpoint 4.

### Approved review adjustment · Local terrain relief

- [x] Target Terrain3D’s detailed mesh at Chibi in the playable valley and prototype the lowest useful tessellation level. Test a radial fade from full visual relief within 3 m to zero at 6 m. Measure the cost of mesh subdivision as well as the visible effect.
- [x] Use Meadow Grass’s existing height channel for soft mossy clumps. Author a varying Warm Path height channel for packed soil and pebbles. Start around 1–2 cm of grass relief and 0.5–1 cm on dirt. Keep the relief anchored to world coordinates as the player moves.
- [x] Compare matched on/off captures and GPU frame times along the same grass-to-path walk on Windows Vulkan Forward Mobile. Check low-angle lighting, foot contact, the fade boundary and camera orbit while Chibi stands still. Preserve the sculpted collision and measure on hardware before selecting a mobile default.

### 2026-11-28 · Stronger grass and path relief

After the first review the player requested more pronounced relief. The [valley terrain material](../levels/first_steps/terrain/materials/creek_terrain_material.tres) initially used a global scale of 0.32, up from 0.10. Chibi anchors the detailed mesh. Grass and path height comes from the painted material textures, with full strength within 3 m and a smooth fade to neutral at 6 m. The shader skips terrain texture reads outside that radius. Subdivision and the buffer still have a GPU cost. Android and iOS use the base mesh pending device measurements.

On Windows Vulkan Forward Mobile, the finest tile at level 1 gave 112 near samples per test position. Vertical displacement on Warm Path at (0, 34) ranged from −18.8 to +21.3 mm and on Meadow Grass at (10, 34) from −46.4 to +41.4 mm. All 36,396 far samples at each position had one neutral value (−1.25 mm after 8-bit decoding). Chibi was grounded at both samples. The original spans were 12.5 mm and 27.5 mm respectively.

The [stronger Windows review build](../builds/first_steps_terrain_relief/Chibi.exe) uses the checkpoint runner snapshot. Its native title launched and the exported pack passed the 41.42 m walk from the title through the atlas to the creek bend with both endpoints grounded at 1280 × 720. Simulated touch menu navigation passed. In the shared workspace, the regression suite recorded 336 passes and four wall-catch or animation timing failures. The workspace menu check initially encountered unfinished mouth transition methods during concurrent facial-expression edits. A later workspace run passed the complete menu route without those errors.

#### Follow-up from the chase camera

The player found the first strengthened version hard to see. The [comparison from the trailhead](../source_art/LayoutReview/first-steps-relief-trailhead-comparison.png) records the base terrain and the 0.32 geometry-only prototype at the same gameplay camera. Fixed-view GPU medians on the RTX 4070 Ti SUPER were 2.81 ms with level 1 at zero strength and 2.92 ms at 0.32, over 20 warmed profiling windows per case. These two runs used the same mesh density. The subsequent review adds local height-dependent lighting as well as geometry.
#### Final Windows review build · Pronounced grass and dirt

- [Matched in-game captures with relief off and on](../source_art/LayoutReview/first-steps-raised-grass-path.png). Both columns use identical lighting, camera poses and crops. The top row shows Warm Path and the bottom row shows Meadow Grass. The normal chase camera now shows rounded grass clumps and shadowed stone edges.
- The level uses 0.125 m near mesh spacing at tessellation level 3 and a displacement scale of 0.42. A [valley-only shader adjustment](../levels/first_steps/terrain/materials/relief_surface_shader.gd) derives local lighting from the same painted height. Its bounded normal tilt and 3–6 m fade soften the edge shadows. Material gradients use the existing texture samples. The lighting adjustment and displacement are both disabled on Android and iOS pending hardware profiling.
- Windows Vulkan Forward Mobile at 1280 × 720. At each painted location the check read back 1,696 inner samples. Grass ranged from −6.09 to +5.44 cm and dirt from −2.47 to +2.80 cm. Beyond 6.1 m the buffer had no spatial variation across 36,396 samples per location. Chibi stayed grounded on both surfaces. The visual effect leaves collision and authoring raycasts on the saved sculpt.
- The [updated review build](../builds/first_steps_terrain_relief/Chibi.exe) passed the exported title-to-bend walk with both endpoints grounded. The checkpoint runner snapshot passed 340/340 regression checks at fixed 60 Hz and the desktop menu flow. The separate live-workspace suite result appears above.
- Current review decision is pending. Overall progress remains 3/11 user-approved. Commit and push follow checkpoint approval.
- Final walking profile on the RTX 4070 Ti SUPER. Off and on replays used the same 1,200 physics ticks and had identical final position and grounded checkpoints. Across 20 GPU profiling windows per replay, off/on means were 3.39/3.43 ms, medians 3.72/3.24 ms, and 95th percentiles 4.55/5.20 ms. The spread exceeds the difference in the means. These desktop figures do not establish a phone budget.
- Added a [low-angle ramp silhouette comparison](../source_art/LayoutReview/first-steps-relief-edge-profile.png) for player review. An orthographic camera views the trailhead path and grass against a pale background with distant scenery clipped. The dashed trace comes from the relief-off capture at the identical camera pose. Each close-up spans 1.48 m.

#### Review adjustment · Follow the painted shapes

The player wants the white flower petals on Meadow Grass and the individual stepping stones on Warm Path to carry the local relief. Inspect the source silhouettes, bake paint-aligned masks, and verify that the moving fine mesh can resolve them. Compare both materials at matched low cameras and check the normal atlas launch and walk. Preserve the 3–6 m visual fade and the sculpted collision. Implemented and verified, awaiting player review.

- The texture packer takes cream flower silhouettes directly from the Meadow Grass paint, removes tiny marks with tile-edge wrapping, and feathers their edges. It uses the blue surface channel for Warm Path, with a gradual bevel and variation across the stone crowns. The baked masks use existing alpha channels. The finest desktop mesh spacing is 1.56 cm, with the same 3 m full-strength zone and 6 m cutoff. Fine petal tips below the mesh resolution retain texture-level shading.
- [Matched earlier and revised material captures](../source_art/LayoutReview/first-steps-painted-shapes.png) and [paint versus measured mesh displacement](../source_art/LayoutReview/first-steps-paint-mesh-height.png). The height view reads interpolated vertical vertex displacement from the rendered terrain at the same camera pose. A desktop GPU readback compared 4,091 cream pixels with 174,280 green background pixels on the trailhead grass patch. Mean elevation differed by approximately 1.05 cm. In the path patch the highest and lowest painted-height sample groups differed by approximately 3.96 cm. Chibi was grounded in both patches.
- Comparable 600-tick walks at 1280 × 720, Windows Vulkan Forward Mobile, RTX 4070 Ti SUPER. Median GPU time over ten profiling windows per walk was 3.18 ms before and 3.34 ms with the revised relief. Both walks had the same endpoint. The [Windows review build](../builds/first_steps_painted_relief/Chibi.exe) uses the checkpoint runner snapshot. The exported pack passed Title → Play → First Steps Valley → Play and the 41.42 m walk to the bend, with grounded endpoints. Native Windows startup passed. Physical mobile profiling remains pending.
- The checkpoint snapshot passed 340/340 headless gameplay checks at fixed 60 Hz. The test process reported one resource still in use during shutdown. The exported route completed without that diagnostic.

- [Side view of the updated painted relief](../source_art/LayoutReview/first-steps-painted-side.png). Matched orthographic Vulkan captures span 76 cm across each panel. Relative to the traced relief-off silhouette, the highest flower crest rises about 1.3 cm, the tallest path crest about 2.4 cm, and the lowest visible grout falls about 1.1 cm in this view.

#### Flower height adjustment · 2026-11-28

The player approved Warm Path and asked for more pronounced flowers while preserving the ground around them. In [the terrain asset slots](../levels/first_steps/terrain/woodland_terrain_assets.tres), Meadow Grass uses native displacement scale 2.0 and offset −0.004519. The offset holds packed background alpha 128/255 at its previous elevation. The existing petal mask and paint blending still determine where relief applies.

[Matched 30° flower comparison](../source_art/LayoutReview/first-steps-flower-lift-30deg.png) · [Windows review build](../builds/first_steps_flower_lift/Chibi.exe). At the trailhead on Windows Vulkan Forward Mobile, the pale petals averaged 2.04 cm above nearby moss, up from 1.05 cm. All 36,086 ground samples clear of the flower mask matched their previous encoded heights. The Warm Path diagnostic PNG matched its previous SHA-256 hash. The exported pack passed the 41.42 m title-to-bend route with grounded endpoints. Checkpoint 4 remains open for player review.

Player approved checkpoint 4 on 2026-11-28 after reviewing Warm Path and the final flower lift. Checkpoint 5 is authorized.
