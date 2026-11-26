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
- Move verified work to the relevant dated section. Record what changed and what was tested. Mark any open issue with the detail the next agent needs.

## Godot tools and verification

- Reuse the project’s existing tools where they meet the target. Consider Godot plugins or extensions when they solve a specific problem. In the plan, explain the benefit and check compatibility with the project’s Godot version and renderer, maintenance, and licensing.
- When changing generated scenes, update their generator and verify the playable scene. Regenerate only the affected scenes where the tooling supports it.
- Run the relevant automated checks and verify the affected flow in the game. For visual or motion work, compare equivalent views or repeatable gameplay inputs and record the renderer and test conditions.

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

Run this from the Godot project root using the installed Godot executable if `godot` is unavailable on PATH.
