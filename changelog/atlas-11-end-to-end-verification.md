# Checkpoint 11 · End-to-end verification

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 10 receives player approval.

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

- [ ] Start from the configured title scene. Play the route through creek, dry crossing, root ledges, canopy and strong-wind finish. Exercise Back, section retry, replay and atlas return as a player.
- [ ] Launch from each developer station and retry after a miss. Check spawn heading, camera, water, attachment, glide and wind state. Record any failure with start and input sequence.
- [ ] Run the gameplay suite and menu-flow regression. Exercise atlas destinations from the JSON catalog and rerun the affected standalone checks referenced in earlier milestone records.
- [ ] Review title, atlas, postcards, pause and touch controls at 1280 × 720 desktop and 844 × 390 landscape. Distinguish simulated input from hardware results.
- [ ] Make fresh Windows and Android exports with the project presets. Launch Windows from the exported build; record Android export, installation and physical-device play separately. Record missing tooling or access explicitly.

## Acceptance and evidence

Attach the route results, desktop and phone captures, export identities and platform coverage. List remaining issues with reproduction steps. Leave final approval to the player. At final designer handoff, provide the verified starter, First Steps collection and checkpoint 4 evidence with a short paint → place → save → reopen → play exercise.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
