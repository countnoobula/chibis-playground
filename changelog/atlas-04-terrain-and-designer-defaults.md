# Checkpoint 4 · Terrain and designer defaults

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 3 receives player approval.

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

- [ ] Inspect the Terrain3D distribution before vendoring it under addons/. Record the exact version and license alongside the plugin. Test an isolated terrain scene after a fresh import before wiring the game entry point.
- [ ] Create a woodland starter with four named paint slots: Meadow Grass for open ground, Warm Path for the trail, Creek Earth for wet banks and Mossy Stone for exposed rock. Compare swatches under the valley lighting with First Puzzle and Environment Style.
- [ ] Use a separate terrain-data directory for the playable valley. Instantiate the runner, spawn on a stable trailhead, sculpt the approach and leave room for a shallow shelf, pool and exit at the bend. Inspect sightlines from Chibi’s chase camera.
- [ ] Create a second designer instance, paint a patch of every material, save and reopen both scenes. Check that the patches survive and the original valley data is independent.
- [ ] Set the existing first_steps entry’s scene path and enabled flag in the atlas JSON. Enter through Title → Play → First Steps Valley and confirm Rooftop Gym still opens.

## Acceptance and evidence

Capture the trailhead and bend at runner height, the four labeled swatches and the independent-instance result. Record renderer, plugin build, import diagnostics and terrain data locations. Ask the designer to paint, save, reopen and walk the bend before progressing.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
