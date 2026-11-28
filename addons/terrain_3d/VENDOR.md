# Terrain3D vendor record

- Upstream: [TokisanGames/Terrain3D](https://github.com/TokisanGames/Terrain3D)
- Release: `v1.1.0-stable` (`629bbd6`)
- Source archive: `Terrain3D_v1.1.0-stable.zip`
- Archive SHA-256: `51B78BC758F5759CBC8EAAAB14E5CF4E8661717E265FDD760F5ABF945F15B243`
- License: MIT; see [LICENSE.txt](LICENSE.txt).
- Godot compatibility declared by upstream: 4.5–4.8+.

The checked-in `addons/terrain_3d` contents are copied from that release archive. The upstream release includes native libraries for Windows, Linux, macOS, Android, iOS, and Web. The project targets Godot 4.7.2 and the Mobile renderer; import/play verification is recorded in the First Steps terrain checkpoint plan.

Local change: the export cache reads the version from the active editor plugin. Command-line exports can run without any terrain node selected in the editor.
