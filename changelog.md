# Chibi changelog

## In progress

### Roaming Atlas and First Steps Valley

**Owner** Codex · **Checkpoint** 5 of 11 · **Status** user-approved after Windows playtest · **Current tasks** 5/5 · **User-approved checkpoints** 5/11

#### 1. Art and tracker

- [x] Archive both concept PNGs
- [x] Compare both SHA-256 pairs
- [x] Update AGENTS.md
- [x] Add milestone tracker
- [x] Record design decisions

**Review.** Compare the overview and western extension at the cottage gate, river mouth, and fishing pier. Confirm how these views should join.

User-approved. [Verification and review decision](changelog/2026-11-27-atlas-art-and-tracker.md)

#### 2. Title and transition

- [x] Create illustrated Play ribbon and mobile patch
- [x] Replace Continue and New Game with Play; keep Options and Quit
- [x] Reflow desktop and touch layouts; update hit areas, focus order, and accessible names
- [x] Emit play_requested; let the main menu own the reversible 0.3-second crossfade
- [x] Verify focus restoration and consume the initiating input
- [x] Carry the saturated gingham rim, zoom, and strawberry marker to the focused title button

**Review.** Try Title → Play → Atlas → Back with mouse, keyboard/controller, and touch. First Steps Valley opens selected. Check Options, Quit, Escape/Cancel, held confirm, and double tap.

[Verification and captures](changelog/2026-11-27-title-and-transition.md) · User-approved.

#### 3. Working atlas

- [x] Paint one continuous map from the two concepts
- [x] Separate destination pins and fixed postcard panel
- [x] Implement drag, touch, and controller navigation
- [x] Wire Intro, First Steps Valley, and Rooftop Gym availability
- [x] Launch Rooftop Gym and update the documented route and flow test
- [x] Animate the drag hint finger along a gentle arc
- [x] Rename the backstory pin and give postcards italic opening lines and a single action
- [x] Add the future underwater destination to the western lake
- [x] Reveal the moving map through all four postcard corners
- [x] Inset the preview artwork in a scalloped postcard sticker
- [x] Separate the tagline from the story and anchor the action at bottom right
- [x] Configure destination content, scene availability, circular PNG art, and curved, text-sized pin ribbons from JSON
- [x] Apply the approved Lily-Root Hollow postcard and verify both atlas layouts

**Review.** Pan from forest to lake and back. Verify the shoreline joins, pins stay anchored, and selecting a destination updates its postcard. Show a short status and disable launch for pending scenes.

[Verification and in-game captures](changelog/2026-11-27-working-atlas.md) · User-approved.

#### 4. Terrain and designer defaults

- [x] Pin MIT-licensed Terrain3D 1.1.0 stable with its license
- [x] Verify clean Godot 4.7.2 Forward Mobile import
- [x] Integrate Scene Builder and prepare a First Steps collection of props and gameplay scenes
- [x] Verify editor placement, undo/redo, persistence and gameplay on Terrain3D
- [x] Create a reusable four-material woodland starter
- [x] Sculpt the trailhead and creek bend
- [x] Enable valley launch from the atlas
- [x] Verify player-centered relief on painted flowers and stepping stones

**Review.** Review the palette and creek bend from Chibi’s camera. Codex verifies painting and scene placement in an independent starter. The designer tests at final handoff.

[Implementation, captures and technical verification](changelog/atlas-04-terrain-and-designer-defaults.md) · User-approved.

#### 5. Water and caustics

- [x] Place the existing Chibi water body and profile
- [x] Sculpt wading shelf, dive pool, and sloping exit
- [x] Connect the terrain receiver to the shared caustic shader and water parameters
- [x] Exercise wading, swimming, diving, and exit
- [x] Capture repeatable views above and below water

**Review.** Compare the legibility of the bed with the Underwater concept. Check surface effects, the camera transition, moving light on terrain and rocks, and dry banks.

[Implementation plan, acceptance checks and handoff](changelog/atlas-05-water-and-caustics.md) · User-approved after swimming and caustics review.

#### 6. First dry crossing

- [ ] Vault a root
- [ ] Hop two boulders
- [ ] Cross a balance log
- [ ] Add safe section checkpoints, retry, and developer station starts
- [ ] Verify missed-jump recovery

**Review.** Cross dry, deliberately fall in, swim to shore, and retry. Judge the landing silhouettes and spacing from the chase camera.

[Implementation plan, acceptance checks and handoff](changelog/atlas-06-first-dry-crossing.md) · Planned.

#### 7. Ambient breeze

- [ ] Animate plant tips
- [ ] Animate scarf and ahoge
- [ ] Keep trunks and plant roots anchored
- [ ] Compare movement with breeze enabled and disabled

**Review.** Observe Chibi standing still. Repeat identical run and jump inputs and verify that direction, speed, and trajectory match.

[Implementation plan, acceptance checks and handoff](changelog/atlas-07-ambient-breeze.md) · Planned.

#### 8. Root ledges

- [ ] Place pole entry
- [ ] Author a climbable root face
- [ ] Tune mantle shelf and camera clearance
- [ ] Verify checkpoint and retry

**Review.** Complete pole → climb → mantle. Inspect handhold visibility, clearance, and safe reset.

[Implementation plan, acceptance checks and handoff](changelog/atlas-08-root-ledges.md) · Planned.

#### 9. Canopy gap

- [ ] Author rope catch and swing
- [ ] Tune the release landing
- [ ] Add the descending line
- [ ] Verify early-drop recovery and retry

**Review.** Catch, release, and ride the line. Deliberately release early and recover.

[Implementation plan, acceptance checks and handoff](changelog/atlas-09-canopy-gap.md) · Planned.

#### 10. Strong wind and finish

- [ ] Dress the woodland trampoline
- [ ] Author a strong-wind zone
- [ ] Signal its direction with foliage
- [ ] Tune the glide landing
- [ ] Wire finish, replay, and level select

**Review.** Read the wind before takeoff, bounce into it, steer through the glide, and exit the zone. Only an explicitly authored strong-wind zone may redirect Chibi.

[Implementation plan, acceptance checks and handoff](changelog/atlas-10-strong-wind-and-finish.md) · Planned.

#### 11. End-to-end verification

- [ ] Complete the valley from Title
- [ ] Check section retries and developer station starts
- [ ] Run gameplay and menu regressions
- [ ] Review desktop and touch layouts
- [ ] Verify exports and record device coverage

**Review.** Play to the overlook, retry a section, return to the atlas, and enter Rooftop Gym. Check 1280 × 720 desktop and 844 × 390 landscape touch. Record Windows launch, Android export, and physical-device results separately.

[Implementation plan, acceptance checks and handoff](changelog/atlas-11-end-to-end-verification.md) · Planned.

### Other active work


Add each active target here with its owner, status, and a short description. Check the current project and reread this file before editing. Update your own entry and preserve edits from other agents. When work is verified, move it to the relevant section below with the date and the checks that ran.

## Completed work

- [Rooftop cloud optimisation · 2026-11-28](changelog/2026-11-28-rooftop-weather-performance.md) · User-approved. Median GPU frame time with clouds fell 34–38% across six views on Apple M1.

- [Rooftop movement and rope polish · 2026-11-28](changelog/rooftop-30fps-movement.md) · Player-approved. All 370 checks passed at 30 fps, 60 fps and variable timing.

- [Chibi rooftop expressions · 2026-11-28](changelog/chibi-gameplay-expressions.md) · All three checkpoints approved, including automatic rooftop reactions and the exported emoji picker.

- [Title and transition · 2026-11-27](changelog/2026-11-27-title-and-transition.md)
- [Atlas art and tracker · 2026-11-27](changelog/2026-11-27-atlas-art-and-tracker.md)
- [Project structure · 2026-11-27](changelog/2026-11-27-project-structure.md)
- [Source art · 2026-11-27](changelog/2026-11-27-source-art.md)
- [Woodland assets · 2026-11-27](changelog/2026-11-27-woodland-assets.md)
- [In-game menus · 2026-11-27](changelog/2026-11-27-in-game-menus.md)
- [Main menu · 2026-11-27](changelog/2026-11-27-main-menu.md)
- [Concept art · 2026-11-27](changelog/2026-11-27-concept-art.md)
- [Concept art · 2026-11-26](changelog/2026-11-26-concept-art.md)
- [Rooftop gym · 2026-11-27](changelog/2026-11-27-rooftop-gym.md)
- [Rooftop gym · 2026-11-26](changelog/2026-11-26-rooftop-gym.md)
- [Chibi movement and animation · 2026-11-27](changelog/2026-11-27-chibi-movement-and-animation.md)
- [Chibi movement and animation · 2026-11-26](changelog/2026-11-26-chibi-movement-and-animation.md)
- [Camera and controls · 2026-11-26](changelog/2026-11-26-camera-and-controls.md)
- [Water · 2026-11-26](changelog/2026-11-26-water.md)
- [Builds and exports · 2026-11-26](changelog/2026-11-26-builds-and-exports.md)
- [Verification · 2026-11-27](changelog/2026-11-27-verification.md)
- [Verification · 2026-11-26](changelog/2026-11-26-verification.md)
