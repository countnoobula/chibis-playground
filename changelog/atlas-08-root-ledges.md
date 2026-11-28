# Checkpoint 8 · Root ledges

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** User-approved.

[Previous checkpoint](atlas-07-ambient-breeze.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

The next route section connects a pole entry to a climbable root face and a mantle onto a shelf.

## Starting context

The player starts from the approved creek crossing. Reuse shared pole behavior and the existing climb-capability contract. Root dressing, mantle geometry and camera clearance belong to the valley.

- [parkour_pole.tscn](<../features/stations/parkour_pole.tscn>)
- [rooftop_climb_tower.gd](<../levels/rooftop_gym/stations/rooftop_climb_tower.gd>)
- [tower_climb_checks.gd](<../tests/tower_climb_checks.gd>)
- [test_wall_climb_geometry.gd](<../tests/test_wall_climb_geometry.gd>)

## Implementation checklist

- [x] Align the pole approach with the previous landing. Put a developer start and safe retry point before commitment. Verify attachment, release and approach from either side.
- [x] Shape the root face and mark climbable surfaces. Fit the climb capability and handholds to the visible root. Check the transition from pole to face at normal camera distance.
- [x] Author the mantle shelf with enough capsule and head clearance through the full animation. Exercise ledges near side walls and steer the camera while hanging.
- [x] Drop from each transfer, retry and replay pole → climb → mantle. Check starting orientation, contact state, camera clearance and the onward route.

## Acceptance and evidence

Capture pole approach, root contact and mantle exit. Record a full chain from the checkpoint and a deliberate drop followed by a successful retry.

## Handoff and change history

### 2026-11-28 · Root ledges playtest

From the east bank, run toward the short pole, jump onto its cap, and jump toward the moss-striped root. Keep pressing forward to climb and mantle onto the shelf. In a debug build **2** starts at Root Ledges and **R** retries the current section. The physical checkpoint works when walking in from the creek. Its camera pitch is authored separately from the dry crossing so the upper shelf is visible on arrival.

The valley uses the shared pole and the runner's climb-capability contract. Six collision-backed grips follow the bark face. The shelf top is at 5.85 m. The complete run reached PolePerch, Climbing, MantleUp and grounded locomotion at x14.08. Both lateral approaches could mount the pole. Retrying separately during perch, climb and mantle restored locomotion at the section start. The packed retry HUD regression passed all 10 checks. The shared wall-geometry regression passed its assertions and reported a Godot resource-cleanup warning at process exit.

Godot 4.7.2 / Windows x64 / Vulkan Forward Mobile / 1280 × 720 / 60 Hz simulated input. The native executable launched and the configured title and atlas led to the playable valley. [Chase camera sequence](../source_art/LayoutReview/first-steps-root-ledges.jpg) · [Windows build](../builds/first_steps_checkpoint_8/Chibi.exe) · [Traversal regression](../tests/test_first_steps_root_ledges.gd)

Player review is deferred for the overnight run. Judge the approach camera, jump timing and grip readability.

The packaged traversal regression passed 26 checks, including a deliberate walk off the shelf, checkpoint retry and a second complete transfer.

### Player review · 2026-11-28

The player approved the root ledges after trying the pole-to-shelf route.
