# Checkpoint 10 · Strong wind and finish

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Implemented and verified. Overnight checkpoint published for player review.

[Previous checkpoint](atlas-09-canopy-gap.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

A visible gust tells the player where the woodland trampoline will launch them. Chibi bounces, glides to the overlook and can replay or return to the atlas.

## Starting context

Keep ambient breeze behavior from checkpoint 7. Model the strong zone on the existing runner wind field and the rooftop wind tunnel. Only this authored field can apply movement force.

- [parkour_trampoline.tscn](<../features/stations/parkour_trampoline.tscn>)
- [wind_field_3d.gd](<../features/runner/wind_field_3d.gd>)
- [rooftop_wind_tunnel.gd](<../levels/rooftop_gym/stations/rooftop_wind_tunnel.gd>)
- [wind_assisted_glide_regressions.gd](<../tests/wind_assisted_glide_regressions.gd>)
- [wind_tunnel_regressions.gd](<../tests/wind_tunnel_regressions.gd>)
- [roaming_atlas.json](<../config/roaming_atlas.json>)

## Implementation checklist

- [x] Dress a shared trampoline so its bouncy surface, collision and landing footprint agree. Test the bounce with the strong zone off before setting the wind.
- [x] Define the field’s volume, direction and exit. Bind it through the runner wind query. Check entry, exit, respawn and a nearby ambient-only path for lingering influence.
- [x] Make foliage lean toward the landing and put the cue where it is visible before takeoff. Align the launch and use the actual scarf glide controls to tune distance and steering.
- [x] Reach the overlook, finish once and exercise replay and level select. Return to the atlas and select the gym; verify state and focus handoff.
- [x] Compare movement inside/outside the zone with matching inputs. Repeat early drop, overshoot and retry; run the existing glide and wind regressions.

## Acceptance and evidence

Show the cue before launch, the influence during glide and movement immediately after exit. Record an overlook finish, replay, return to the atlas and subsequent gym launch.

## Handoff and change history

### 2026-11-28 · Wind Overlook playtest

The east end of the zip line leads to a mushroom-colored trampoline. Look for reeds leaning toward the overlook. Run toward the cap, jump onto it, then tap Jump again as Chibi starts to fall after the bounce. Steer the scarf toward the mossy deck. In debug builds **4** starts at Wind Overlook and **R** retries the current section.

The shared trampoline accepts material overrides and retains its original gym defaults and bounce physics. The bounded valley wind points east at up to 8.2 m/s with a 0.55 m fade at its edges. Outside the field the query returns zero. At 60 Hz the same forward input from the checkpoint reached a 9.15 m apex in both runs. With the field active, Chibi touched down at x52.07; with the provider disabled, at x48.97. The finish waits for grounded feet over the deck. Replay loads the trailhead and Level Select opens the actual atlas with First Steps selected and Back focused. The desktop cursor is available on completion.

Regression testing found that the root wall and shelf share a coplanar summit surface. Adding another static body changed which collider the mantle query hit first. Marking the wall core as part of the summit made both contact results valid. Root Ledges then passed all 26 checks. The gameplay suite passed 370 checks, including the existing rooftop wind and glide regressions. The canopy regression passed 25 checks. The camera at the Wind Overlook checkpoint now frames both the runner and the trampoline clear of the previous zip support.

Godot 4.7.2 / Windows x64 / Vulkan Forward Mobile / 1280 × 720 / simulated input. [Launch, bounce, glide and finish](../source_art/LayoutReview/first-steps-wind-overlook.jpg) · [Windows build](../builds/first_steps_checkpoint_10/Chibi.exe) · [Wind traversal regression](../tests/test_first_steps_wind.gd)

Player review deferred for the overnight run. Try a lateral correction after takeoff, then compare Replay and Level Select.

The standalone wind and finish regression passed 53 checks against the Windows pack. A separate overshoot probe settled at x56 without completing, then walked back to the deck and triggered the finish at x53.98. The completion gate checks both the live grounded position and the trigger overlap, so a retry from midair cannot open a stale finish panel.
