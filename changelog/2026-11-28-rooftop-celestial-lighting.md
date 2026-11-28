# Rooftop sun, moon and time of day

**Owner** Codex · **Status** Implemented, verified and user-approved on 2026-11-28.

## Player experience

Try Dawn, Day, Noon, Dusk and Night from the same spot in the Rooftop Gym. Look up to see a sun with a soft halo and a moon with a readable crescent or fuller lit face. Clouds can pass in front of both. Low sunlight casts long warm shadows, noon has shorter shadows, and night retains enough fill to read the course. At the same night time and camera angle, a full moon lights the roof more strongly than a crescent. A new moon contributes no direct moonlight.

Start with a developer preview on the existing `--debug-menu` route. Provide five preset buttons, a scrubbable time of day and a separate moon-phase control with familiar phase labels. Hold the chosen time until it is changed so phase and lighting comparisons are repeatable. Use independently adjustable lunar phase for this preview. Keep the authored rooftop light as the normal launch default while evaluating the looks.

## Dependencies and starting files

- [Rooftop sky shader](../levels/rooftop_gym/shaders/rooftop_sky.gdshader) and [rooftop controller](../levels/rooftop_gym/rooftop_gym_controller.gd). The existing cloud raymarch uses the authored sun direction for lighting. The weather checkpoint added a global clock and a quarter-resolution pass to avoid recurring radiance work.
- [Rooftop generator](../tools/build_parkour_scenes.gd) owns the sun, fill and environment defaults. [GameSettings](../settings/game_settings.gd) applies shadow quality. The [camera controller](../features/runner/chibi_camera_controller.gd) duplicates the dry environment for underwater fog and needs checking when ambient light changes during gameplay.
- Use Godot 4.7.2’s existing sky shader and directional lighting on Forward Mobile. No plugin dependency is planned. [Godot sky shader documentation](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html) · [Godot directional light documentation](https://docs.godotengine.org/en/4.7/classes/class_directionallight3d.html)

## Checkpoint 1 · Playable celestial lighting preview

- [x] Added five interpolated light and palette presets in [the rooftop lighting controller](../levels/rooftop_gym/rooftop_celestial_lighting.gd). The same directional light handles sunlight and moonlight with one shadow budget. The [camera controller](../features/runner/chibi_camera_controller.gd) applies ambient changes to its underwater environment copy.
- [x] Added sun and moon discs with halos aligned to their lighting directions. The [preview shader](../levels/rooftop_gym/shaders/rooftop_celestial_sky.gdshader) draws the discs at full resolution and reads cloud coverage from the existing quarter-resolution sky pass. Moon phase drives the lit shape and a continuous direct-light curve.
- [x] Added the [debug preview controls](../levels/rooftop_gym/rooftop_sky_preview.gd). Open with **L** or **Sky [L]**, choose a preset or scrub time and phase, and close to resume camera input. **Default** returns to the authored lighting.
- [x] Kept the original shader entry point for the authored sky. Both variants share the [cloud sampling code](../levels/rooftop_gym/shaders/rooftop_clouds.gdshaderinc). Only the preview variant draws celestial discs or reads time-of-day inputs. The sky material changes when entering the preview or returning to Default. Within the preview, scrubbing updates global shader inputs and leaves radiance static. The generated scene retained its authored defaults.
- [x] Captured all five presets and five moon phases from fixed views at both resolutions. Verified shadow direction, new-moon route visibility, phase energy, cloud occlusion, underwater ambient updates, and keyboard and touch preview input. Repeated the gameplay and title-to-rooftop checks. Benchmarked the authored and active paths and continuous scrubbing.

**Player acceptance.** The sun and moon are recognisable, clouds can cover them, and the five looks have distinct colour and shadow. Holding time still and changing phase visibly changes the moon and the light it casts on the roof. The course remains readable on a new-moon night.

## Performance · 2026-11-28

Measured on Apple M1 using Godot 4.7.2 Forward Mobile (Vulkan), High graphics, 100% 3D scale and 2× MSAA. The test launched through the title and atlas, then held fixed route and cloud-bank cameras. It excluded 1.1 seconds of warm-up per variant and pooled two 2.2-second windows with reversed variant order. The weather baseline used the previously optimised shader in the same scene. Continuous scrub advanced eight in-game hours per real second. Measurements cover steady-state GPU cost and include no physical-phone run.

| Output and view | Weather baseline | Authored after | Noon | Full moon | Continuous scrub |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1280 × 720 route | 4.707 / 5.727 | 4.652 / 5.401 | 5.107 / 8.381 | 4.726 / 5.702 | 4.642 / 5.579 |
| 1280 × 720 cloud banks | 4.655 / 5.308 | 4.592 / 5.167 | 4.741 / 5.377 | 4.619 / 5.326 | 4.488 / 5.268 |
| 844 × 390 route | 4.315 / 5.347 | 4.419 / 5.465 | 4.553 / 6.393 | 4.768 / 12.469 | 4.367 / 13.150 |
| 844 × 390 cloud banks | 4.419 / 5.764 | 4.538 / 5.762 | 4.588 / 5.564 | 4.711 / 5.745 | 4.654 / 5.642 |

Values are GPU milliseconds per frame as median / 95th percentile. The authored path stayed within 0.12 ms of baseline. The highest median increase in an active variant was 0.45 ms. Tail timings fluctuated between runs, particularly for the 844 × 390 route. Sampled median `Setup Sky` time was below 0.27 ms across all views, including during scrubbing.

## Verification · 2026-11-28

- Forward Mobile (Metal, Apple M1) passed keyboard and simulated touch checks, independently adjustable time and moon phase, and return to gameplay. At 1280 × 720 and 844 × 390, the default sky matched the previous weather shader in the sampled sky region. A same-time comparison confirmed clouds cover the dusk sun.
- At the fixed night time, measured direct-light energies were 0.000, 0.039, 0.181, 0.353, and 0.430 for new moon, crescent, quarter, gibbous and full moon. Waxing and waning quarter moons matched. The underwater camera copied preset ambient colours and returned to the dry environment on resurfacing.
- The gameplay suite passed 340 checks. Both Metal title-to-atlas-to-rooftop runs passed launch, pause and resume. The standalone capture harness emitted shutdown diagnostics also seen in the weather capture harness.

## Handoff and review

- **Review** The user accepted the playable lighting preview and approved a dedicated checkpoint commit on `origin/main` on 2026-11-28. This record is included in that commit.
