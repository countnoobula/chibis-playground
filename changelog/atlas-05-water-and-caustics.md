# Checkpoint 5 · Water and caustics

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 4 receives player approval.

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

- [ ] Run the rocky basin with the current water body/profile. Record water surface height, camera transition behavior and comparison views before editing valley terrain.
- [ ] Place the shared water body in the bend. Author its outline and depth, then sculpt a gentle entry shelf, a deeper pocket where Chibi can fully submerge and a low exit that she can walk up. Align the visible surface and swim volume.
- [ ] Trace the receiver setup in the basin. Feed the same caustic parameters into the terrain material while preserving its four paint layers. Check wet terrain, a submerged rock, an above-water rock and both banks.
- [ ] Walk in slowly, cross the wade/swim boundary, dive, surface, swim sideways out and re-enter. Repeat with the camera near the shore and under the surface.
- [ ] Compare fixed views under identical lighting. Record moving caustics in two frames and a dry-bank control. Run the water regressions through the gameplay suite.

## Acceptance and evidence

Review entry, dive and exit in one continuous traversal. Compare the shallow shelf and pool against the underwater concept, including bed visibility, highlights, camera changes and dry-bank shading.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
