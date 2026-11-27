# Checkpoint 8 · Root ledges

**Owner** Codex lead for integration and evidence, with scoped Luna Max implementation. **Status** Planned. Start after checkpoint 7 receives player approval.

[Previous checkpoint](atlas-07-ambient-breeze.md) · [Milestone tracker](../changelog.md) · [Project instructions](../AGENTS.md)

## Player experience

The next route section connects a pole entry to a climbable root face and a mantle onto a shelf.

## Starting context

The player starts from the approved creek crossing. Reuse shared pole behavior and the existing climb-capability contract. Root dressing, mantle geometry and camera clearance belong to the valley.

- [parkour_pole.tscn](<../features/stations/parkour_pole.tscn>)
- [rooftop_climb_tower.gd](<../levels/rooftop_gym/stations/rooftop_climb_tower.gd>)
- [tower_climb_checks.gd](<../tests/tower_climb_checks.gd>)
- [test_wall_climb_geometry.gd](<../tests/test_wall_climb_geometry.gd>)

## Implementation checklist

- [ ] Align the pole approach with the previous landing. Put a developer start and safe retry point before commitment. Verify attachment, release and approach from either side.
- [ ] Shape the root face and mark climbable surfaces. Fit the climb capability and handholds to the visible root. Check the transition from pole to face at normal camera distance.
- [ ] Author the mantle shelf with enough capsule and head clearance through the full animation. Exercise ledges near side walls and steer the camera while hanging.
- [ ] Drop from each transfer, retry and replay pole → climb → mantle. Check starting orientation, contact state, camera clearance and the onward route.

## Acceptance and evidence

Capture pole approach, root contact and mantle exit. Record a full chain from the checkpoint and a deliberate drop followed by a successful retry.

## Handoff and change history

- **Next action** After the preceding checkpoint is approved, inspect the current working tree and run the first checklist step against that revision.
- **Changes and verification** Pending. Append dated implementation notes, files changed, test conditions, results and capture links here as work lands.
- **Review** Awaiting implementation and player review. Record feedback, rerun the affected checks, and record the approval commit and push when this checkpoint closes.
