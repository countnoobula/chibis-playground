# Checkpoint 6 · First dry crossing

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** User-approved.

[Previous checkpoint](atlas-05-water-and-caustics.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

A readable route across the same creek offers a root vault, two boulder hops and a balance log. A missed jump leads back into the tested swim route.

## Starting context

Build valley-specific shapes around the movement already exercised in Rooftop Gym. Use the actual runner capsule and chase camera to tune spacing. Preserve the approved swim entry and exit.

- [parkour_balance_beam.tscn](<../features/stations/parkour_balance_beam.tscn>)
- [balance_footing_regression.gd](<../tests/balance_footing_regression.gd>)
- [rooftop_ledge_vault_regressions.gd](<../tests/rooftop_ledge_vault_regressions.gd>)
- [rooftop_gym_controller.gd](<../levels/rooftop_gym/rooftop_gym_controller.gd>)

## Implementation checklist

- [x] Start from the approved bank and establish a section start on dry level ground with a clear view of the root. Tune the vault lip and landing using the existing vault behavior.
- [x] Place two rounded boulders with clear, stable landing tops. Test both slow approaches and full-speed jumps. Check the camera can see the second landing from the first.
- [x] Use the shared balance beam behavior under the log dressing. Match the collision top to the visible wood and connect its exit to reachable dry ground.
- [x] Place a section checkpoint and developer start. Retry after approaching, after landing and after falling in; check spawn heading, camera and runner state.
- [x] Deliberately miss each hop and step off the log. Swim to shore, rejoin the route and complete it without a reset. Record any unreachable pocket or misleading collision.

## Acceptance and evidence

Play the dry sequence and recovery route from the normal entry. Save chase-camera views from takeoff and landing plus the section retry result.

## Handoff and change history

### 2026-11-28 · Course and checkpoint

- The dedicated checkpoint 5 commit reached origin/main as 6e7b2f8 before work on this crossing began. This checkpoint adds a placeable [dry crossing scene](../levels/first_steps/dry_crossing.tscn) under First Steps Valley and uses the approved terrain regions and creek volume.
- Follow the west bank, then face east along z = −16. The low root triggers the shared speed vault. A firm footing on its far side supports the transition from vault to jump. Two moss-topped boulders lead to the fallen log. Its eight-metre span uses the shared balance station to manage Chibi’s feet and speed.
- The physical checkpoint saves a marker facing the crossing. In the Windows debug build, **1** goes straight to that marker from anywhere in the valley. **R** or the HUD **Retry** button returns Chibi there once activated. The checkpoint camera looks down far enough to see the root and both boulder tops. The normal atlas launch still starts at the trailhead.
- Measured full-stick and 76% stick crossings at 60 physics ticks per second. Both entered SpeedVault, touched the two landing tops, entered BalanceBeam, and walked onto the far bank without activating the water volume. The full-speed run landed on the first rock at x = −13.59 m and on the second at x = −9.26 m.
- Exercised both missed hops and a walk off the water-facing end of the log using movement input. Each reached creek swimming and exited on the east bank without respawning. In a separate continuous run Chibi missed the first hop, swam back to the west bank, lined up again, vaulted, landed on both rocks and balanced to the east exit without using Retry. The checkpoint 5 wade, dive, rise, walk-out and re-entry regression also passed with the course present.

### Windows verification and handoff

- Ran the normal title → Play → atlas → First Steps Valley flow against the exported pack on Godot 4.7.2, Vulkan Forward Mobile, RTX 4070 Ti SUPER at 1280 × 720. Confirmed the atlas still opens at the trailhead, then exercised the **1** shortcut with a keyboard event. Checked landscape HUD placement at 844 × 390 on Windows using simulated mobile mode.
- Captured takeoff, boulder landing and balance using the player’s chase camera at 60 physics ticks per second. West-bank root approach, boulder-to-log transition and the exit bank are visible from the playtest camera. [Gameplay captures](../source_art/LayoutReview/first-steps-dry-crossing.jpg)
- The standalone dry crossing regression passed 29 checks both headlessly and against the Windows pack. It covers the continuous 54.9 m trailhead approach, physical checkpoint activation, actual vault and boulder contacts, balance, three missed routes, and repeated section starts. [Crossing regression](../tests/test_first_steps_dry_crossing.gd)
- The dedicated retry HUD test passed 10 checks covering activation, keyboard R, touch, heading, camera, pause/resume and developer station start. The isolated gameplay suite passed all 353 checks. The final scene also passed the 13-check checkpoint 5 creek traversal. Accelerated headless probes can retain audio resources at shutdown; the final GPU traversal runs exited cleanly. [Retry HUD test](../tests/test_first_steps_retry_hud.gd)
- The native Windows debug export launched successfully. Pack SHA-256 is ECD8A9EF77472E72ADD1608D266D1C3EA6520B04D9A63A86EEC6988076F09115. Verified the executable, pack and Terrain3D DLL in the archive against their local copies by hash. [Windows playtest ZIP](../builds/first_steps_dry_crossing/Chibi-First-Steps-Dry-Crossing-Windows.zip)
- **Next action** Player review of root timing, jump spacing, log balance and swim recovery. Update this record with the decision. The owner requested overnight advancement through checkpoint 11 with a separate commit and push at each verified milestone. Player reviews remain pending.

### Player review · 2026-11-28

The player approved the dry crossing after playing the Windows build.
