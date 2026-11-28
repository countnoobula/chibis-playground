# Scene Builder upstream

- Upstream: [sci-comp/scene-builder](https://github.com/sci-comp/scene-builder)
- Release: `v0.2.4`
- Commit: `6d1cff9ded165b40bbe925e4260dc5b76be28c92`
- License: MIT, retained as [LICENSE](LICENSE)

## Local integration changes

- Set `plugin.cfg`'s displayed version to `0.2.4` to match the pinned release.
- Updated the configuration resource and icon import source path for this project's flat `res://addons/scene_builder/` layout.
- Changed the helper class `SceneBuilderToolbox` from `Node` to `RefCounted`. It provides utility methods and has no scene-tree behavior; instances otherwise remain unparented and trigger an orphan-node leak on editor shutdown.
- Fixed Scene Builder placement undo/redo. The upstream handler removed placed items on undo but recorded no re-add action for redo; the shared placement action now records child insertion, scene ownership, world transform, and removal.
- Replaced the awaited initial filesystem reload with a one-shot filesystem signal and skip thumbnail UI setup when the editor has no non-headless 3D viewport. This prevents export/headless editor teardown from resuming the reload coroutine after the plugin has been destroyed while keeping thumbnail generation enabled in the normal editor.
