# Checkpoint 11 · End-to-end verification

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Implemented and verified. Overnight checkpoint published for player review.

[Previous checkpoint](atlas-10-strong-wind-and-finish.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

A player can start at Title, complete the valley, replay a section and return through the atlas to Rooftop Gym in a packaged build.

## Starting context

Use the reviewed checkpoint records as the expected baseline. Record the tested revision, engine, renderer, resolution, input method and platform so another chat can reproduce each result.

- [project.godot](<../project.godot>)
- [export_presets.cfg](<../export_presets.cfg>)
- [run_tests.gd](<../tests/run_tests.gd>)
- [test_menu_level_flow.gd](<../tests/test_menu_level_flow.gd>)
- [roaming_atlas.json](<../config/roaming_atlas.json>)

## Implementation checklist

- [x] Start from the configured title scene. Play the route through creek, dry crossing, root ledges, canopy and strong-wind finish. Exercise Back, section retry, replay and atlas return as a player.
- [x] Launch from each developer station and retry after a miss. Check spawn heading, camera, water, attachment, glide and wind state. Record any failure with start and input sequence.
- [x] Run the gameplay suite and menu-flow regression. Exercise atlas destinations from the JSON catalog and rerun the affected standalone checks referenced in earlier milestone records.
- [x] Review title, atlas, postcards, pause and touch controls at 1280 × 720 desktop and 844 × 390 landscape. Distinguish simulated input from hardware results.
- [x] Make fresh Windows and Android exports with the project presets. Launch Windows from the exported build; record Android export, installation and physical-device play separately. Record missing tooling or access explicitly.

## Acceptance and evidence

Attach the route results, desktop and phone captures, export identities and platform coverage. List remaining issues with reproduction steps. Leave final approval to the player. At final designer handoff, provide the verified starter, First Steps collection and checkpoint 4 evidence with a short paint → place → save → reopen → play exercise.

## Handoff and change history

### 2026-11-28 · Final packaged playtest

**Review route.** Open the Windows build and choose **Play → First Steps Valley → Play**. The creek has both a shallow swimming entry and a route over the water. Run and jump to vault the root, hop the boulders and cross the balance log. Jump onto the pole and toward the moss-striped root, then hold forward to mantle. Jump to the swing, tap Jump to release toward the landing, and jump to catch the zip line. Bounce off the woodland trampoline, tap Jump while starting to descend to deploy the scarf, and steer onto the overlook. Replay returns to the trailhead. Level Select returns to First Steps in the atlas. The debug shortcuts are **1** Dry Crossing, **2** Root Ledges, **3** Canopy Gap and **4** Wind Overlook. **R** retries the last reached checkpoint. **B** toggles the ambient breeze for comparison.

**Route and regressions.** Tested with Godot 4.7.2, Windows x64 and 60 Hz simulated gameplay input. The core gameplay suite passed 370 checks, including the creek, rooftop parkour, scarf and wind regressions. Standalone results included dry crossing 29, section retry HUD 10, ambient breeze 38, root ledges 26, canopy gap 25 and wind/finish 53. After a missed creek jump, the east-bank swim recovery now reaches the Root Ledges checkpoint. The dry-crossing test verifies that real checkpoint before reseeding for the next deliberate miss. A few accelerated headless tests report audio resources still releasing on process exit; the packaged runs below completed.

**Menu and HUD.** Verified the configured Title, all four JSON destinations, unavailable launch states, Back and focus restoration, atlas panning, Rooftop Gym launch, pause and Resume in the exported pack at both 1280 × 720 and 844 × 390. Inputs were simulated mouse, controller and touch. [Desktop and landscape menu captures](../source_art/LayoutReview/first-steps-final-menu-review.jpg) · [Landscape touch HUD](../source_art/LayoutReview/first-steps-final-touch-hud.jpg)

**Windows export.** Native debug executable launched and the packaged resources were exercised with Vulkan Forward Mobile on an NVIDIA RTX 4070 Ti. The portable archive contains the executable, PCK and Terrain3D DLL; all three archive entries were compared by SHA-256 to their originals. [Run locally](../builds/first_steps_checkpoint_11/Chibi.exe) · [Portable Windows ZIP](../builds/first_steps_checkpoint_11/Chibi-First-Steps-Windows.zip)

**Designer handoff.** Copy the woodland starter scene and its terrain-data directory together, then point the copy at its own data. Paint Meadow Grass, Warm Path, Creek Earth and Mossy Stone. Use the First Steps Scene Builder collection to place a rock on the creek bank and a beam across it. Undo, redo, save and reopen before playing the crossing. The placement regression resculpted the disposable surface by 6 m, saved and reopened the rock on its slope, and verified terrain collision. The collection regression checked that Chibi could land on and walk the placed beam. The disposable regression now provides the camera and runtime collision mode that a bare starter lacks, and saves before binding a transient runner target. [Terrain starter guide](../levels/first_steps/terrain/README.md) · [Scene Builder collection](../Data/scene_builder/README.md)

**Player review.** The owner approved checkpoints 1–5 and requested overnight delivery of 6–11. Each overnight checkpoint has a separate commit and playtest record. Art direction, camera feel and difficulty remain open to the owner and designer. Intro, the underwater expansion and custom brushes remain future work.

**End-to-end evidence.** The [continuous journey](../tests/test_first_steps_full_journey.gd) passed 70/70 in the Windows export, including every dry-crossing state, both aerial sections, the overlook finish, atlas return and Rooftop Gym pause/resume. The standalone packaged creek route passed 13/13, including the dive and walk-out. [Station starts and retry](../tests/test_first_steps_station_starts.gd) passed 17/17 on desktop and 18/18 at 844 × 390 with simulated touch. This exposed a 3 cm spawn penetration at station 4 which rotated the runner 0.209 rad on startup. Raising the authored spawn to 4.78 m restored the intended heading, with zero measured yaw error after either key 4 or retry.

**Windows package.** The 64-bit debug executable started on a private Windows desktop using Vulkan Forward Mobile. The archive includes the executable, the resource pack and the Terrain3D DLL. All three ZIP entries matched their source files by SHA-256. [Windows executable](../builds/first_steps_checkpoint_11/Chibi.exe) · [Portable Windows ZIP](../builds/first_steps_checkpoint_11/Chibi-First-Steps-Windows.zip)

**Overnight commits.** Dry crossing 9a57a03, ambient breeze 25e6e80, root ledges d54f12c, canopy gap 1183b6b, wind and finish d29b973. Each reached origin/main before work advanced. The checkout retains concurrent character and wardrobe work outside the valley commit.

**Android package.** [ARM64 debug APK](../builds/first_steps_checkpoint_11/Chibi.apk), 218,938,845 bytes. The Android preset now advertises only the architecture supported by both Godot and the vendored Terrain3D build. APK inspection found Godot, the ARM64 Terrain3D library and the First Steps resources. APK Signature Scheme v2 and v3 verification passed. The package installed on the API 37 x86_64 emulator using ARM64 translation. Its Godot activity resumed and remained running for approximately 15 seconds without an app-specific load or crash error. The emulator check covered startup. Physical Android gameplay and performance remain untested; no physical device was attached.

| Artifact | SHA-256 |
| --- | --- |
| Windows ZIP | `F40CA9396ACE2A5D6B9CC5C5C5C39FC2B85C93E52EB088457ABA488346837EEC` |
| Android APK | `0E9D93411BC055EA3C5E6B3F92EF36576394958DD2A482A27D8C65E20E0313D8` |
