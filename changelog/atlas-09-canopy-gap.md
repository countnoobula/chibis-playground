# Checkpoint 9 · Canopy gap

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Implemented and verified. Overnight checkpoint published for player review.

[Previous checkpoint](atlas-08-root-ledges.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

Chibi catches a rope at the canopy gap, releases onto a visible landing and rides a descending line onward.

## Starting context

Begin at the mantle shelf. Use the existing rope solver and shared line scene; keep anchor positions, equipment dressing and recovery geometry local to this route.

- [parkour_rope_swing.tscn](<../features/stations/parkour_rope_swing.tscn>)
- [rope_swing_solver.gd](<../features/stations/rope_swing_solver.gd>)
- [parkour_line.tscn](<../features/stations/parkour_line.tscn>)
- [rooftop_station_regressions.gd](<../tests/rooftop_station_regressions.gd>)

## Implementation checklist

- [x] Place the rope anchor and catch volume. Tune entry speed and approach height from the real mantle exit. Check the catch at both the center and edge of the approach.
- [x] Choose a release landing visible during the swing. Replay early, intended and late releases. Adjust anchor and landing geometry before changing shared swing behavior.
- [x] Place the descending line from the landing. Confirm mounting, descent direction, dismount position, and clearance from branches and the camera.
- [x] Provide a safe recovery below the gap and a retry before the catch. Drop early, recover, retry and finish the sequence without stale attachment state.

## Acceptance and evidence

Review the chain from the chase camera, including one intentional early drop. Save frames at catch, release and dismount and note recovery outcomes.

## Handoff and change history

### 2026-11-28 · Canopy gap playtest

From the mantle shelf, run east, jump to the hanging handle, then tap Jump as the rope swings toward the mossy platform. Jump again near the far edge to catch the descending line. Developer key **3** starts on the shelf; **R** retries there once the canopy checkpoint has been reached. The recovery surface under the course is dry terrain. The previous section's regression now tests a fall from the side of the root shelf before the next physical checkpoint.

The authored scene instances the shared swing and zip line. In the exported pack the intended release landed at x22.53 on the raised platform; the runner then caught the cable at x25.30 and dismounted at x31.65. The smallest sampled foot clearance above Terrain3D during the loaded descent was 0.55 m. Both ±0.45 m approaches caught the swing. Release sweeps at 4, 10, 16 and 22 attached ticks all reached the platform; a release at 28 ticks could carry the player directly into the line. The route also accepts a continuous arrival via the preceding root mantle.

Godot 4.7.2 / Windows x64 / Vulkan Forward Mobile / 1280 × 720 / simulated controls at 60 Hz. [Catch, release landing, zip and dismount](../source_art/LayoutReview/first-steps-canopy-gap.jpg) · [Windows build](../builds/first_steps_checkpoint_9/Chibi.exe)

Player review deferred for the overnight run. Judge sightlines, the release window and how clearly the landing reads from the shelf.

The packaged canopy regression passed 25 checks. A separate four-tick early release steered off the course to dry ground at (17.53, 2.99, -12.84), then retried at the shelf. The updated Root Ledges regression passed 26 checks.
