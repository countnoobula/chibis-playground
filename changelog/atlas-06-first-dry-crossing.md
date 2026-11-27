# Checkpoint 6 · First dry crossing

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 5 receives player approval.

[Previous checkpoint](atlas-05-water-and-caustics.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

A readable route across the same creek offers a root vault, two boulder hops and a balance log. A missed jump leads back into the tested swim route.

## Starting context

Build valley-specific shapes around the movement already exercised in Rooftop Gym. Use the actual runner capsule and chase camera to tune spacing. Preserve the approved swim entry and exit.

- [parkour_balance_beam.tscn](<../features/stations/parkour_balance_beam.tscn>)
- [balance_footing_regression.gd](<../tests/balance_footing_regression.gd>)
- [rooftop_ledge_vault_regressions.gd](<../tests/rooftop_ledge_vault_regressions.gd>)
- [rooftop_gym_controller.gd](<../levels/rooftop_gym/rooftop_gym_controller.gd>)

## Implementation checklist

- [ ] Start from the approved bank and establish a section start on dry level ground with a clear view of the root. Tune the vault lip and landing using the existing vault behavior.
- [ ] Place two rounded boulders with clear, stable landing tops. Test both slow approaches and full-speed jumps. Check the camera can see the second landing from the first.
- [ ] Use the shared balance beam behavior under the log dressing. Match the collision top to the visible wood and connect its exit to reachable dry ground.
- [ ] Place a section checkpoint and developer start. Retry after approaching, after landing and after falling in; check spawn heading, camera and runner state.
- [ ] Deliberately miss each hop and step off the log. Swim to shore, rejoin the route and complete it without a reset. Record any unreachable pocket or misleading collision.

## Acceptance and evidence

Play the dry sequence and recovery route from the normal entry. Save chase-camera views from takeoff and landing plus the section retry result.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
