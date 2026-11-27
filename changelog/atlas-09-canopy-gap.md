# Checkpoint 9 · Canopy gap

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 8 receives player approval.

[Previous checkpoint](atlas-08-root-ledges.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

Chibi catches a rope at the canopy gap, releases onto a visible landing and rides a descending line onward.

## Starting context

Begin at the mantle shelf. Use the existing rope solver and shared line scene; keep anchor positions, equipment dressing and recovery geometry local to this route.

- [parkour_rope_swing.tscn](<../features/stations/parkour_rope_swing.tscn>)
- [rope_swing_solver.gd](<../features/stations/rope_swing_solver.gd>)
- [parkour_line.tscn](<../features/stations/parkour_line.tscn>)
- [rooftop_station_regressions.gd](<../tests/rooftop_station_regressions.gd>)

## Implementation checklist

- [ ] Place the rope anchor and catch volume. Tune entry speed and approach height from the real mantle exit. Check the catch at both the center and edge of the approach.
- [ ] Choose a release landing visible during the swing. Replay early, intended and late releases. Adjust anchor and landing geometry before changing shared swing behavior.
- [ ] Place the descending line from the landing. Confirm mounting, descent direction, dismount position, and clearance from branches and the camera.
- [ ] Provide a safe recovery below the gap and a retry before the catch. Drop early, recover, retry and finish the sequence without stale attachment state.

## Acceptance and evidence

Review the chain from the chase camera, including one intentional early drop. Save frames at catch, release and dismount and note recovery outcomes.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
