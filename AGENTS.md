# Working on Chibi

## Work one target at a time

1. Start with the user’s target. Read this file and `changelog.md`, then inspect the current scenes, scripts, project settings, and assets relevant to the request.
2. Assume other Codex chats may have changed the project. Use Git status and diffs when available. In a folder without Git, read the affected files and record the current behavior before changing them. Treat the project on disk as the current baseline and preserve concurrent edits.
3. Plan the target first. Describe the intended player experience, the changes, and how to verify them. Resolve open choices with the user when they would materially change the result. Wait for the user’s approval before implementing.
4. Implement the approved target and verify it in the normal Godot entry point. Record the outcome and any remaining issue, then wait for the next target.

## Delegate with Luna Max

- When delegating, use GPT-6 Luna at Max reasoning effort. Give each agent the current target, the relevant project context, and clear ownership of the files or section it will edit.
- Coordinate edits to shared scenes, generators, and tests before agents write to them. Ask agents to report their changes, checks, and unresolved issues. Review the integrated result.

## Keep the changelog current

- Put the active target at the top of `changelog.md` under **In progress** with its owner and status. Track planning, implementation, and verification there.
- Reread the file before updating it. Keep edits from other agents and update the entry you own.
- Store the full record for each completed checkpoint or dated work item in its own Markdown file under `changelog/`. Link it directly from the completed checklist item and the short history index in `changelog.md`. Keep the root file focused on active work. In the linked file record changes, tests, outstanding issues, and review decisions; resolve evidence links relative to that file.
- For multi-checkpoint work, keep a tracker first under **In progress** with the owner, current checkpoint and status, tasks completed in that checkpoint, and checkpoints explicitly approved out of the total. Give each checkpoint its own task checkboxes and player-visible acceptance check.
- Link each checkpoint to its dated verification record as work lands. Record tests, relevant renderer, resolution, captures, open issues, and the review decision. Distinguish implemented, verified, and user-approved. Keep the overall checklist at the top until the target closes.
- Stop at every checkpoint for user review. Record requested adjustments under that checkpoint, repeat the affected checks, and advance only after user approval.
- Close each verified, user-approved checkpoint with a dedicated Git commit and push to the current tracking branch. Review the staged diff, include its changelog entry, preserve unrelated and concurrent work, and confirm the remote contains the commit. Report the commit and push result before advancing.

## Godot tools and verification

- Reuse the project’s existing tools where they meet the target. Consider Godot plugins or extensions when they solve a specific problem. In the plan, explain the benefit and check compatibility with the project’s Godot version and renderer, maintenance, and licensing.
- When changing generated scenes, update their generator and verify the playable scene. Regenerate only the affected scenes where the tooling supports it.
- Run the relevant automated checks and verify the affected flow in the game. For visual or motion work, compare equivalent views or repeatable gameplay inputs and record the renderer and test conditions.

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

Run this from the Godot project root using the installed Godot executable if `godot` is unavailable on PATH.

## Project structure

| Location | What belongs here |
| --- | --- |
| `features/water/` | Water volumes, profiles, shaders, and the playable rocky basin example. Place `water_body_3d.tscn` in a level and set its outline, depth, and profile. |
| `features/runner/` | The playable `chibi_runner.tscn`, movement and climbing, camera, animation, gear, swimming, and runner effects. |
| `features/stations/` | Placeable beam, pole, line, swing, and trampoline scenes, their behavior, and equipment paint defaults. Set station dimensions and line mode on each instance. |
| `features/items/` | Pickups shared across levels, including the strawberry. |
| `levels/rooftop_gym/` | The gym scene, course layout, spawns, palette, sky, pool, tower, wind tunnel, and rooftop-specific assemblies. |
| `ui/` and `settings/` | Title and journal scenes and artwork in `ui/menu/`, touch controls in `ui/hud/`, and persisted preferences in the GameSettings autoload. |
| `assets/` and `source_art/` | Shared runtime models, audio, fonts, and the self-contained woodland kit. Editable Blender masters and regeneration inputs live under the Godot-ignored `source_art/` root. |
| `addons/` | Vendored Godot integrations and editor plugins. Keep upstream files, version information, and licenses together. |

- Compose levels from feature scenes. Keep the geometry and tuning unique to a course in its level folder. A reusable feature should load without the rooftop scene.
- A level can assign a `RunnerWindField3D` to `runner.wind_field`. A climbable assembly can supply authored leap profiles, corners, and summit data through `get_climb_capability()`. Bind a level's `JournalLevelProgressProvider` with `runner.touch_hud.bind_journal_level_progress(provider)` to show its area and pickups in the journal.
- Keep woodland models, textures, manifest, shader, and post-import script together under `assets/environment/woodland/`. Regenerate with `tools/export_woodland_assets.py`. The kit has a runtime texture directory also named `source_art`; preserve it when copying or exporting the project.
- Move Godot resources together with existing `.uid` and `.import` companions. Update explicit loads, formatted asset paths, shader includes, autoloads, generators, exporters, and tests in the same change.
- `tools/build_parkour_scenes.gd` owns the runner, three particle scenes, and rooftop scene. Use its `-- --rooftop-only` option for course assembly changes. Edit a station's own scene or script for behavior shared by all instances.
- For moves, verify a clean import, run the gameplay suite and affected standalone checks, and run `tests/test_menu_level_flow.gd`. During the atlas preview checkpoint it exercises Title → Play → Atlas → Back and checks rooftop → pause → Resume by loading the gym directly. When the working selector ships, verify the full route through its Rooftop Gym pin. Exercise dynamically loaded art and shaders in a fresh export, and compare fixed-camera captures for rendering changes.
