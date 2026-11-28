# Chibi gameplay expressions

**Design proposal · 2026-11-28.** The player likes the twenty face/cloud pairs and Sad’s softer fade. The player approved the plan and requested checkpoint 1 on 2026-11-28. The current Chibi runner and rooftop gym are the first target. Coordinate character asset changes with the separate Jade and Shaun rig work.

## Expression casting

| Expression | Proposed cue | Availability at first release |
| --- | --- | --- |
| Neutral | Short pause or low-speed locomotion | Automatic, face only |
| Gentle neutral | Settled idle, listening “hmm,” or winding down | Automatic, face only |
| Open smile | First established stretch of enjoyable motion on a rope swing or zipline | Automatic, face only |
| Bright smile | Enter sustained high-flow sprint. Use separate enter and exit thresholds | Automatic, face only |
| Delighted | Idle giggle, in time with the existing sound cue | Automatic, face only. Cloud available for authored celebrations |
| Playful wink | Greeting or a cheeky success beat | On request |
| Soft determination | Settle onto a balance beam or start a controlled climb | Automatic, face only |
| Focused determination | Commit to a wall run | Automatic, face only |
| Tiny pout | Strain during mantle pull-up | Automatic, face only |
| Brave little smile | Secure a ledge after a frightening fall | Automatic recovery, face only |
| Surprised | Discover a reveal or unexpected object | On request |
| Little gasp | Enter the existing qualified deep-fall reaction | Automatic, face first |
| Wide-eyed gasp | Surprise reveal with a longer held beat | On request |
| Startled squeal | Sudden authored scare | On request |
| Free-fall squeal | Continue falling in the qualified flail long enough for the gasp to register | Automatic, face only |
| Sleepy | A long rest, bedtime, or emote | On request |
| Scared | Hesitation before an authored hazard | On request |
| Angry | A scripted frustration beat or emote, with peach-to-coral cloud | On request |
| Sad | A quiet disappointment, with the powder-blue fade into cream | On request |
| Crying | A deliberately authored emotional beat, with the dusk-blue cloud | On request |

## Checkpoint 1 · Reproduce the art and expose manual controls

- [x] Bring the review-only poses and cloud definitions into project-owned assets. Bind the runner’s actual face through its rig binder. Share independently poseable brows, lids and mouth shapes where useful. Check the twenty targets against the approved grid, especially the thin soft-determination brows, wink and open mouths.
- [x] Give each pose a stable ID. Expose a runner-local request with expression, duration or explicit hold, priority and output (face, cloud, or both). Return a handle for early release. Release only that request and clear transient requests on respawn or scene exit. Add an in-engine preview picker for all twenty, including the manual-only set.
- [x] Keep one writer for facial weights, coordinating existing blink and dive mouthpiece behavior with ChibiJuice. Cloud and face share the chosen ID when requested together. Independently requested channels can be released independently. Use the approved upright shallow 3D cloud, horizontal camera tracking, and previous heading at a directly overhead angle.
- Review evidence: twenty paired renders from the game rig, manual play and cancel demonstration, rear and overhead orbit, and close-ups with the dive mouthpiece and wink.

## Checkpoint 2 · Connect rooftop events and blend the poses

- [x] Resolve the automatic face from movement and interrupt from the currently visible pose. Explicit picker selections take priority.
- [x] Ease facial transitions across eyes, brows and mouth. Keep the mouth open from gasp to squeal and close it through a shared lip shape for the rescue smile.
- [x] Start the gasp on fall-flail entry and the squeal after 0.35 seconds of sustained flailing. A secured catch starts the brave smile. Landing or scarf deployment cancels the fall sequence.
- [x] Following player feedback, automatic movement uses face and body. Clouds remain available through the picker and explicit requests. A fall or landing may interrupt an ordinary authored face without taking ownership of a separately requested cloud.
- Review evidence: short rooftop clips of idle to giggle, run to wall run, mantle, short hop, long drop to catch, glide and landing. Check the release into locomotion, and that normal traversal leaves the route readable from behind.

## Checkpoint 3 · Verify interruptions and ship the reviewed tuning

- [x] Exercise all twenty manual IDs with face-only, cloud-only and linked output. Check cancel, repeat, replacement, respawn, scene reload, missing bindings and gear deployment. Exercise a late-arriving request during the fall sequence.
- [x] Compare equivalent inputs at 30 and 60 fps, near-vertical camera orbit, brief drops and flow-threshold crossings. Run the Godot test suite and smoke-test an exported rooftop build. Record renderer, captures and approved timings here.
- [x] The player reviewed and approved all three checkpoints.

- Starting files for the rig checkpoint include `features/runner/chibi_rig_binder.gd`, `features/runner/chibi_juice.gd`, `assets/characters/chibi_runner.glb` and `tools/export_parkour_assets.py`. Preserve the 36 animation clips and current skeleton on re-export. Update the runner scene generator if adding persistent scene nodes. Rooftop event selection starts in `features/runner/parkour_controller.gd`.

### Checkpoint 1 implementation · 2026-11-28

The runner creates `ExpressionDirector` on startup. It lazily attaches the manual face and cloud. The rooftop gym creates the emoji picker in its controller. This also covers regenerated gym scenes that use that controller. Face targets and cloud textures live under `features/runner/expressions/`. `ChibiJuice` owns the actual blend weights and the snorkel mouthpiece remains authoritative while biting.

Later events can hold an expression until released, or pass a duration in seconds. Higher priority takes precedence in each requested channel; the most recent wins ties. Automatic facial behavior resumes when the last manual face request releases.

```gdscript
var handle := player.expression_director.request_expression(&"sad", 0.0, 10, &"both")
# At the end of the dialogue beat:
player.expression_director.release_expression(handle)
# A separate cloud-only reaction expires automatically:
player.expression_director.request_expression(&"surprised", 1.2, 10, &"cloud")
```

Manual control defaults to Both and Hold. F opens the picker while the mouse is captured. The face-only and cloud-only modes and the 2.5-second duration can be selected before choosing an emoji. Auto releases the picker's own request.

Godot 4.7.2 on Windows, Forward Mobile. Captured [twenty live runner poses](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-one/Rooftop expressions.png>), [picker](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-one/picker.png>), [upright cloud at 72 degrees](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-one/orbit1.png>), and [wink with the dive mouthpiece engaged](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-one/wink-gear1.png>). The dive capture exercises the deployed gear pose on the rooftop. Desktop native-touch event injection opened the picker and selected Crying. The hold, timer, priority, independent channels, Auto, direct closed-to-open replacement and respawn checks live in `tests/test_manual_expressions.gd`. The player approved checkpoint 1 and requested automatic rooftop reactions.
- Automated verification on Windows: 340 rooftop regression checks passed, 0 failed. The dedicated manual-expression test also passed. No automatic gameplay trigger mappings have been added in this checkpoint.

### Checkpoint 2 · Rooftop automatic reactions · 2026-11-28

Checkpoint 1 was approved, committed as `da64a20`, pushed and verified on `origin/main`. This checkpoint installs `features/runner/rooftop_reactions.gd` only for the rooftop gym. It reads the movement state after the physics controller updates and drives the face. Only explicit requests show a cloud. The emoji picker still takes precedence. The common fall and catch face meshes are prepared on gym entry so these transitions avoid rebuilding the skinned body during a drop. A regular authored cue with priority below 50 yields to a qualified falling reaction; a priority-100 picker selection remains held until released.

The Zone 2 review drop starts beside the outside corner of the existing flat ledge. Chibi then falls under normal gravity and her ordinary collision probe secures the catch. A shorter drop at the same ledge exercises an early catch before the squeal. The normal hop, ground landing and scarf deployment have separate checks. A rescue smile lasts about 0.6 s on the secured ledge, then blends back into the hanging expression.

Godot 4.7.2 on Windows, Forward Mobile. The recorded drop reaches gasp at physics tick 18, squeal at 38 and the ledge catch at 71. The short drop catches at tick 35 during the gasp. Both runs keep the cloud hidden. [Fall and catch clip](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-two/Drop and catch.mp4>) and [rooftop reaction reel](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-two/Rooftop reaction reel.mp4>). The player approved checkpoint 2 on 2026-11-28.

The automatic and manual expression checks passed. All 340 rooftop checks passed at a fixed 60 fps. In a separate variable-frame run, the full-speed mantle phase error measured 0.066 against a 0.065 limit. The dedicated accelerated expression tests also reported resources still in use at shutdown. Their normal-speed runs exited cleanly.

### Checkpoint 3 · Rooftop interruption review · 2026-11-28

Checkpoint 2 was approved and pushed to origin/main as 6969b33. The acceptance check for checkpoint 3 is a side-by-side early catch, late catch and scarf interruption, with equivalent inputs at both frame rates. Verify explicit face and cloud requests in the exported game and preserve concurrent work.

The mantle check in tests/run_tests.gd now samples the clip when the animation mixer applies a frame, compares against the interpolated body phase, and verifies it covered both lift-off and landing. The old check could read the previous mantle while the initial seek was queued. Both flow speeds measured 0.000 maximum phase error to three decimal places at 30 and 60 fps. The full suite passed 340/340 at 60 fps. At 30 fps it passed 324/340. The 16 remaining failures are outside the expression checks and also occurred before this test change. Several checks wait for both physics and rendering on each iteration, which changes their input schedule at 30 fps. A broader 30 fps movement audit remains open.

The Windows release executable and its exported pack both reached the configured entry point. The pack passed the title → atlas → rooftop → pause → resume check, all twenty linked picker choices and the automatic fall/landing/scarf checks. Both face geometry resources were present in the pack. The normal variable-frame suite also passed 340/340. The manual and automatic expression tests now let the real-time audio mixer drain on exit, including in accelerated runs. The rooftop landing check requires a squeal, ground contact and a settled expression.

The dedicated interruption check also passed against that same exported pack at 30 and 60 rendered fps, with the project running 60 physics ticks per second. It exercises separate face and cloud output across all twenty IDs, repeated and replaced holds, priority and Auto during a sustained fall, scene reload, missing rig binder, sprint thresholds, upright clouds with an overhead camera and mouthpiece deployment/restoration.

In the 30/60 rendered-fps comparison, the early grab occurred at 0.60 s, the longer fall reached its squeal at 0.65 s and caught at 1.20 s at both rates. The scarf interrupted the squeal within one physics tick of the corresponding run. No automatic clouds appeared. The review clip uses the Forward Mobile renderer and three synchronized 640 × 480 source views. [Side-by-side gameplay](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-three/early-late-scarf-comparison.mp4>) · [Looping preview](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/checkpoint-three/rooftop-interruptions.gif>). The player approved checkpoint 3 and requested publication to main on 2026-11-28.
