# Checkpoint 5 · Water and caustics

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Implemented and verified on Windows. User-approved on 2026-11-28. Checkpoint 4 was approved on 2026-11-28.

[Previous checkpoint](atlas-04-terrain-and-designer-defaults.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

Chibi can walk from the dry trail into the creek, wade, swim, dive and climb back out while underwater light makes the bed legible.

## Starting context

Use the existing Chibi water system and its rocky basin as the behavioral baseline. The lake pin remains a future expansion. This checkpoint tests water at the First Steps creek.

- [rocky_basin.tscn](<../features/water/examples/rocky_basin.tscn>)
- [water_body_3d.tscn](<../features/water/water_body_3d.tscn>)
- [default_water_profile.tres](<../features/water/default_water_profile.tres>)
- [water_caustics.gdshaderinc](<../features/water/shaders/water_caustics.gdshaderinc>)
- [water_caustic_receiver.gdshader](<../features/water/shaders/water_caustic_receiver.gdshader>)
- [chibi_swim_controller.gd](<../features/runner/chibi_swim_controller.gd>)
- [water_regressions.gd](<../tests/water_regressions.gd>)
- [Underwater.png](<../source_art/concept_art/Moodboard/Underwater.png>)

## Implementation checklist

- [x] Run the rocky basin with the current water body/profile. Record water surface height, camera transition behavior and comparison views before editing valley terrain.
- [x] Place the shared water body in the bend. Author its outline and depth, then sculpt a gentle entry shelf, a deeper pocket where Chibi can fully submerge and a low exit that she can walk up. Align the visible surface and swim volume.
- [x] Trace the receiver setup in the basin. Feed the same caustic parameters into the terrain material while preserving its four paint layers. Check wet terrain, a submerged rock, an above-water rock and both banks.
- [x] Walk in slowly, cross the wade/swim boundary, dive, surface, swim sideways out and re-enter. Repeat with the camera near the shore and under the surface.
- [x] Compare fixed views under identical lighting. Record moving caustics in two frames and a dry-bank control. Run the water regressions through the gameplay suite.

## Acceptance and evidence

Review entry, dive and exit in one continuous traversal. Compare the shallow shelf and pool against the underwater concept, including bed visibility, highlights, camera changes and dry-bank shading.

## Handoff and change history

- **Next action** Approved checkpoint committed and pushed to origin/main as 6e7b2f8. Remote HEAD verified.

### 2026-11-28 · Creek integration

Checkpoint 4 is approved and pushed in 080cde3. The rocky basin comparison ran on Vulkan Forward Mobile, Windows RTX 4070 Ti SUPER at 1280 × 720. The shared profile placed the surface at y=0.72 m with a 2.90 m volume. A dive registered PoolSwim and put the chase camera inside the water at y=−0.95 m.

### 2026-11-28 · Creek composition and bathymetry

- **Implementation** Added `CreekWater` as a root child using the shared `water_body_3d.tscn` and default profile. Its surface is y=1.10 m, `max_depth` is 3.8 m, and the 18-point local outline follows the bend from the northwest inlet to the east-bank exit. Added two grouped receiver rocks at the pool margin and walk-out.
- **Terrain** Extended `tools/generate_terrain_data.gd` with a targeted `--valley-only` regeneration option. It preserves the independent designer starter dataset. The existing trail and four paint IDs remain intact. Sculpted a shallow wading shelf at `(-16,-16)`, a localized dive pool centered at `(-8.5,-17.5)`, and a rising walk-out from `(-2.5,-22)` to `(5.5,-17.3)`.
- **Files** `levels/first_steps/first_steps_valley.tscn`, `tools/generate_terrain_data.gd`, and the two affected west/south valley regions under `levels/first_steps/terrain/valley_data/`.
- **Verification** Godot 4.7.2.stable, Windows, headless. `generate_terrain_data.gd -- --replace --valley-only` saved four regions and passed save/reopen height, paint-overlay, starter-swatches, and dataset-independence checks. Measured bed heights: shelf `(-16,-16)=0.780 m`, swim entry `(-14,-18)=−0.200 m`, pool center `(-8.5,-17.5)=−1.880 m`, pool margin `(-8.5,-19)=−0.929 m`, ramp start `(-2.5,-22)=0.200 m`, boundary rock `(-5,-22.5)=0.752 m`. The level loaded for six headless frames with no scene or Jolt scale errors. `git diff --check` passed for the two owned text files.
- **Rock placement** `DivePocketRock` at `(-8.5,-0.697,-19)` has mesh AABB min y `−0.929 m` and max y `0.653 m`, seated on the pool bed and submerged 0.447 m below the surface. `ExitBoundaryRock` at `(-5,0.844,-22.5)` has mesh AABB min y `0.752 m` and max y `1.448 m`, seated at the wet/dry boundary and protruding 0.348 m above the surface. Both static bodies use uniform scale and separate sphere colliders.
- **Review state** Terrain generation and scene loading are verified, not user-approved. See the subsequent Windows verification for the completed swim and rendering checks.

### 2026-11-28 · Windows playtest build

- Built from approved checkpoint 4 plus the checkpoint 5 creek changes in isolation. Exported with Godot 4.7.2 Windows Desktop x86-64 debug, launched the native executable, and verified the copied pack and Terrain3D DLL by SHA-256. [Windows build](../builds/first_steps_creek_swim/Chibi-First-Steps-Creek-Windows.zip)
- From Title, Play opens the atlas and the First Steps Valley postcard launches the creek. The controller regression drives Chibi from the actual trailhead with movement input. It covers 57 m to reach the pool, detects the wading speed cap at 1.70 m/s, holds dive for a 0.71 m descent and rises to a capsule center of 1.06 m against a 1.10 m water surface. The east ramp supports a walk-out, dry locomotion, re-entry and a second walk-out. All 13 assertions passed against the exported pack. The isolated headless gameplay suite passed 353 checks. The shared working-tree suite, including concurrent checks, passed 356. The accelerated headless suite logged a retained Step_01 WAV playback at process shutdown. The packed traversal exited cleanly. [Traversal regression](../tests/test_first_steps_creek.gd)
- Captured the exported pack at 1280 × 720 on Windows, Vulkan Forward Mobile, RTX 4070 Ti SUPER. During the deeper visual dive, the normal chase camera registered the creek at y = −0.69 m. The bed remains visible beneath the swimmer. [Shore and underwater views](../source_art/LayoutReview/first-steps-creek-swimming.jpg)
- The valley registers its Terrain3D material and the two local rocks with the existing water body. Compared fixed views with the shared caustic strength at 0 and 0.62, then repeated 48 physics ticks later. At a two-level RGB threshold, 2,944 of 19,200 sampled bed pixels and 5,991 submerged rock pixels changed their caustic contribution. Both dry banks and the exposed cap of the exit rock had zero difference. [Caustic comparison](../source_art/LayoutReview/first-steps-caustics-comparison.jpg)
- Disabled automatic rendering of the 2 × 2 Terrain3D mouse-picking viewport in the playable valley. This cleared the Vulkan mip-level diagnostic. Re-exported, launched the native title and repeated the packed traversal and all five GPU probes with clean renderer logs. Final pack SHA-256 is 95AE93CAFF7CA2E302F868884B376C5D520BA2542B9498931DAFD5199FB9BAD7. All three files in the ZIP match the unpacked build by hash.
- Controls for this review are WASD to move, C to dive and Space to rise. Enter at the shallow shelf and follow the sloping east bank out. The player verified swimming and caustics and approved checkpoint 5 on 2026-11-28.
