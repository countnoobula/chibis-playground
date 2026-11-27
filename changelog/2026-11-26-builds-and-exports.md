# Builds and exports · 2026-11-26

- Added `tools/build.ps1` and Godot export presets for Windows x64 and Android. The script builds both by default and accepts `-Target Windows` or `-Target Android`. The outputs are in `builds/windows` and `builds/android`.
- Enabled ETC2/ASTC texture imports for Android. The debug-signed APK includes ARM64 and x86_64 and passed signature verification.
- Installed and launched the APK on the Android emulator. The touch HUD appeared on startup, and the joystick, camera swipe, and jump button worked.
- Launched the Windows release and confirmed the native pause menu showed Touch Controls off. A gameplay probe using the exported Windows data pack confirmed mouse capture and verified forward movement and camera look with injected Godot input events.
- The integrated Godot headless suite passed all 254 checks.
