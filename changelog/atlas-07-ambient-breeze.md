# Checkpoint 7 · Ambient breeze

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** User-approved.

[Previous checkpoint](atlas-06-first-dry-crossing.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

Plants, Chibi’s scarf and her ahoge move in the summer breeze while the same steering and jump inputs produce the same movement.

## Starting context

Ambient wind is presentation only. Reserve runner redirection for explicitly authored strong-wind zones in checkpoint 10. Preserve scarf and glide behavior already in use.

- [foliage.gdshader](<../assets/environment/woodland/foliage.gdshader>)
- [chibi_scarf_glider.gd](<../features/runner/chibi_scarf_glider.gd>)
- [wind_field_3d.gd](<../features/runner/wind_field_3d.gd>)
- [scarf_glide_regressions.gd](<../tests/scarf_glide_regressions.gd>)

## Implementation checklist

- [x] Identify the foliage deformation inputs, scarf presentation and ahoge attachment. Determine which existing parameters can share a direction and phase without touching physics.
- [x] Author mild tip motion with fixed roots and trunks. Check grass against the terrain edge and leaves against branches so motion reads as bending.
- [x] Apply the breeze to scarf and ahoge presentation. Inspect idle, running, swimming and glide transitions for clipping or sudden pose changes.
- [x] Replay identical input from the same spawn with ambient breeze on and off. Record positions, headings and velocities at matching physics ticks through a run, takeoff, apex and landing. Investigate any movement difference.

## Acceptance and evidence

Show a still-camera motion comparison with identifiable anchored roots and scarf/ahoge response. Include both trajectory traces and the measured difference at the same ticks.

## Handoff and change history

### 2026-11-28 · Ambient breeze playtest

The valley instances its own breeze node. It scales local foliage material copies and applies a post-spring visual modifier to both scarf tails and the ahoge. The authored foliage height mask pins the roots. The modifier fades its scarf contribution during glide deployment. Designers can edit strength on AmbientBreeze; the debug build accepts **B** for a live comparison.

The standalone regression passed 38 assertions against the exported pack. Matched 60 Hz run, takeoff, apex and landing traces measured zero difference in position, heading and velocity to five decimal places; jump rise was 0.65 m. Tests sampled the applied skeleton pose and fixed root transforms. A separate packed probe toggled B, entered PoolSwim and deployed the scarf during descent. The scarf blend dropped below 0.00001 while the glider was active.

Verified on Windows Vulkan Forward Mobile at 1280 × 720. Captured a fixed camera beside the creek bellflowers with the same render timing in both runs. [Breeze off/on animation](../source_art/LayoutReview/first-steps-ambient-breeze.gif) · [Movement regression](../tests/test_first_steps_breeze.gd) · [Windows build](../builds/first_steps_checkpoint_7/Chibi.exe)

Review is deferred by the owner for this overnight run. Compare the strength at the trailhead and creek using B.

### Player review · 2026-11-28

The player approved the ambient breeze after reviewing its appearance in the Windows build.
