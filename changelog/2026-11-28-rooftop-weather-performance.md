# Rooftop weather performance

**Owner** Codex · **Status** Implemented, verified and user-approved on 2026-11-28.

## Player experience

Keep the Rooftop Gym’s pastel cloud banks, lit edges, clear opening over the course and slow drift while improving frame time. This checkpoint focuses on clouds. Keep the tunnel and the rest of the scene fixed during comparisons.

## Starting point

- The original [rooftop sky shader](../levels/rooftop_gym/shaders/rooftop_sky.gdshader) used a half-resolution pass with up to 28 view samples per intersected cloud bank and two extra density samples for lighting each occupied step.
- The original sky shader used `TIME` for a 300-second drift. The rooftop has fixed ambient light and disables sky reflections. Godot 4.7.2 still prepares radiance for a visible sky, and `TIME` marks it dirty as the clock advances. The cubemap branch uses only the atmosphere, so the radiance cost is separate from the visible cloud march. [Mobile renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L1022-L1042) · [Sky renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/environment/sky.cpp#L937-L955)
- [GameSettings](../settings/game_settings.gd) owns the four graphics presets. [The scene builder](../tools/build_parkour_scenes.gd) owns the generated rooftop scene and supports `-- --rooftop-only`.
- Use the installed Godot 4.7.2 build, its profiler and the project's Mobile renderer. These cover the proposed measurement. No plugin dependency is planned.

## Checkpoint 1 · Profile and optimise the rooftop clouds

- [x] Entered through Title → Play → Atlas → Rooftop Gym → Play. Recorded before measurements for three fixed views at both output sizes with clouds on, clouds off, and the cloud march held at a fixed phase with static radiance.
- [x] Moved the 300-second drift clock to a global float driven by the [rooftop controller](../levels/rooftop_gym/rooftop_gym_controller.gd) and registered in [project.godot](../project.godot). The shader now draws the same static atmosphere for radiance while the visible clouds continue to drift. At 1280 × 720, median GPU time in the route view’s `Setup Sky` profiler stage fell from 1.91 to 0.10 ms. [Godot global shader parameter source](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/material_storage.cpp#L1731-L1747)
- [x] Compared the optimised half-resolution and quarter-resolution passes. Kept quarter resolution after the matched captures showed the same silhouette, palette and course opening with slightly softer cloud edges. Kept the existing density and lighting samples. [Godot sky shader documentation](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html)
- [x] Verified the existing generated scene with its external shader and controller. The change required no scene regeneration.
- [x] Repeated the timing runs with clouds on and off. Compared matched cloud phases and checked live drift, camera motion, all four presets, window resize, scene re-entry and pause/resume. Ran the gameplay and menu checks.

**Player acceptance.** The sky keeps its pastel depth, drift and course framing. A proposed change needs a repeatable GPU frame-time gain in the views it targets. Bring any visible tradeoff to user review.

## Benchmarks · 2026-11-28

Godot 4.7.2 Forward Mobile with Vulkan on an Apple M1 desktop host. Used High graphics, 100% 3D scale, 2× MSAA and uncapped presentation. The scene ran from the title entry point at 1280 × 720 and 844 × 390, with the latter using simulated touch layout. For each view and variant, discarded two warm-up seconds and pooled two four-second samples with the variant order reversed for the second run. Timed Godot’s viewport GPU and CPU render intervals and whole-frame intervals. Captures at both sizes confirmed the output dimensions. GPU timings come from the desktop GPU, and a physical phone remains untested.

Cells show GPU milliseconds per frame as median / 95th percentile. The clouds-off diagnostics preserve the atmosphere and each build's radiance behaviour. The original clouds-off run still refreshed radiance each frame. The optimised half-resolution column isolates the gain from changing the animation clock before applying quarter resolution.

| Output | View | Before, clouds on | Before, clouds off | After, clouds on | After, clouds off | After, half-resolution clouds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1280 × 720 | Route | 7.115 / 7.844 | 5.860 / 6.557 | 4.398 / 5.166 | 4.282 / 4.890 | 5.022 / 5.679 |
| 1280 × 720 | Cloud banks | 6.954 / 7.645 | 5.369 / 6.030 | 4.444 / 4.968 | 4.052 / 4.459 | 4.990 / 5.712 |
| 1280 × 720 | Roof-heavy | 4.961 / 5.534 | 4.894 / 5.538 | 3.175 / 3.682 | 3.151 / 3.699 | 3.226 / 3.697 |
| 844 × 390 | Route | 5.640 / 6.335 | 5.158 / 5.775 | 3.735 / 4.194 | 3.542 / 3.987 | 3.990 / 4.537 |
| 844 × 390 | Cloud banks | 5.570 / 6.171 | 4.947 / 5.506 | 3.588 / 3.993 | 3.228 / 3.650 | 3.859 / 4.330 |
| 844 × 390 | Roof-heavy | 4.237 / 4.745 | 4.241 / 4.768 | 2.668 / 3.090 | 2.634 / 3.010 | 2.655 / 3.059 |

With clouds on, median whole-frame time in the route view fell from 7.500 to 4.824 ms at 1280 × 720 and from 5.932 to 4.228 ms at 844 × 390. Median CPU render time for those same runs fell from 0.428 to 0.350 ms and from 0.625 to 0.518 ms.

## Verification · 2026-11-28

- Matched cloud-phase captures showed the baseline and optimised half-resolution images matching within the sampled sky crops at both sizes. Quarter resolution softened the thin cloud edges, with the most visible difference at 844 × 390.
- Godot 4.7.2 Forward Mobile (Metal, Apple M1) displayed live drift across a five-second hold, passed the camera sweep, resized to 844 × 390, rendered all four presets, and loaded the rooftop a second time through the title and atlas.
- The 60 FPS headless gameplay suite passed **340 checks**. The menu flow passed in graphical Metal runs at 1280 × 720 and 844 × 390, including desktop and simulated touch launch and pause/resume.

## Handoff and change history

- **Review** The user accepted the cloud optimisation and approved a dedicated checkpoint commit on `origin/main` on 2026-11-28. This record is included in that commit.
