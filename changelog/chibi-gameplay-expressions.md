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
| Brave little smile | Secure a ledge after a frightening fall | Automatic recovery, with cloud if the fall cloud was visible |
| Surprised | Discover a reveal or unexpected object | On request |
| Little gasp | Enter the existing qualified deep-fall reaction | Automatic, face first |
| Wide-eyed gasp | Surprise reveal with a longer held beat | On request |
| Startled squeal | Sudden authored scare | On request |
| Free-fall squeal | Continue falling in the qualified flail long enough for the gasp to register | Automatic, with cloud |
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

- [ ] Resolve the base from current movement; overlay a short event reaction or an explicitly held authored request. Proposed precedence: explicit override, urgent falling reaction, ordinary authored reaction, traversal, idle. Higher priority interrupts from the currently displayed pose. Drop stale events and return to the current valid base when finished. Equal-priority repeats of the same ID extend the hold without restarting.
- [ ] Start with 180–300 ms eased blends for idle and traversal, 80–120 ms for a startled reaction and 250–400 ms to settle. Let brows and lids lead a gasp by about two frames at 60 fps. Close the mouth through a compatible lip pose before changing open-mouth silhouettes. Layer natural blinks on available lids. Keep bite-valve contact when submerged.
- [ ] Begin the gasp on qualified fall-flail entry. Try a squeal after another 0.35 s of continuous flail. Cancel immediately at catch, landing or scarf deployment, even during anticipation; settle the visible face smoothly. Use previous fall context to distinguish a rescue catch from an ordinary grab. Only start traversal or flow expressions once the state has settled (~0.15 s). Tune by capture.
- [ ] Keep the cloud quiet for everyday movement. On strong or authored reactions let the face lead by ~0.1 s, ease the cloud in over ~0.15 s and out over ~0.2 s. When a visible cloud changes emotion, keep its anchor and shell, blend the palette and swap the glyph during a small scale dip to avoid doubled eyes. Smooth anchor motion separately from the body’s squash. Honor cancel and reset even during a cloud transition.
- Review evidence: short rooftop clips of idle to giggle, run to wall run, mantle, short hop, long drop to catch, glide and landing. Check the release into locomotion, and that normal traversal leaves the route readable from behind.

## Checkpoint 3 · Verify interruptions and ship the reviewed tuning

- [ ] Exercise all twenty manual IDs with face-only, cloud-only and linked output. Check cancel, repeat, replacement, respawn, scene reload, missing bindings and gear deployment. Exercise a late-arriving request during the fall sequence.
- [ ] Compare equivalent inputs at 30 and 60 fps, near-vertical camera orbit, brief drops and flow-threshold crossings. Run the Godot test suite and smoke-test an exported rooftop build. Record renderer, captures and approved timings here.
- [ ] Review each checkpoint with the player before advancing. Record implementation and verification separately from this proposal.

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
