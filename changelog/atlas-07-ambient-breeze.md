# Checkpoint 7 · Ambient breeze

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 6 receives player approval.

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

- [ ] Identify the foliage deformation inputs, scarf presentation and ahoge attachment. Determine which existing parameters can share a direction and phase without touching physics.
- [ ] Author mild tip motion with fixed roots and trunks. Check grass against the terrain edge and leaves against branches so motion reads as bending.
- [ ] Apply the breeze to scarf and ahoge presentation. Inspect idle, running, swimming and glide transitions for clipping or sudden pose changes.
- [ ] Replay identical input from the same spawn with ambient breeze on and off. Record positions, headings and velocities at matching physics ticks through a run, takeoff, apex and landing. Investigate any movement difference.

## Acceptance and evidence

Show a still-camera motion comparison with identifiable anchored roots and scarf/ahoge response. Include both trajectory traces and the measured difference at the same ticks.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
