# Checkpoint 10 · Strong wind and finish

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 9 receives player approval.

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

- [ ] Dress a shared trampoline so its bouncy surface, collision and landing footprint agree. Test the bounce with the strong zone off before setting the wind.
- [ ] Define the field’s volume, direction and exit. Bind it through the runner wind query. Check entry, exit, respawn and a nearby ambient-only path for lingering influence.
- [ ] Make foliage lean toward the landing and put the cue where it is visible before takeoff. Align the launch and use the actual scarf glide controls to tune distance and steering.
- [ ] Reach the overlook, finish once and exercise replay and level select. Return to the atlas and select the gym; verify state and focus handoff.
- [ ] Compare movement inside/outside the zone with matching inputs. Repeat early drop, overshoot and retry; run the existing glide and wind regressions.

## Acceptance and evidence

Show the cue before launch, the influence during glide and movement immediately after exit. Record an overlook finish, replay, return to the atlas and subsequent gym launch.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
