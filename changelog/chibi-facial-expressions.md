# Chibi facial expressions

**Owner** Codex, concurrent facial-expression target. **Status** Previews ready for review, as recorded in the active tracker.

## Player experience and review plan

The current decision is how Chibi's face should read on the existing Godot model. The preview set covers smiling crescents, a wink, two free-fall reactions, and subtler expressions including a tiny pout, brave little smile and earlier determined face.

- [ ] Locate the original preview set and record its file or capture links here. The existing tracker identifies the variants but does not name the files.
- [ ] Compare equivalent framing, pose and light for each expression under consideration. Check how clearly it reads from the usual gameplay camera as well as in close-up.
- [ ] Record which variants the player approves or wants adjusted. If changes are requested, repeat the same comparison with the revised preview.
- [ ] If gameplay triggers are requested later, record their scope and acceptance criteria here before implementation.

## Change history and handoff

The previews listed above are reported in the pre-existing tracker. The atlas work did not modify expression assets. The next action is to connect the original captures and review decisions to this record with the owner. Runtime integration, test outcomes, and approval are unrecorded.

### 2026-11-28

- Rendered five additional expressions for review in Godot 4.7.2 using Forward Mobile on Windows. Sleepy yawns under heavy eyelids, scared has wide eyes and a wobbly mouth, angry has a stubborn pout, sad has a small frown, and crying adds tears beneath squeezed eyes.
- Reviewed the 780 × 820 portraits and assembled them into `Chibi five new emotions.png`. The expanded `Chibi complete expression grid 20.png` includes the fifteen earlier previews. Both are in the Codex visualization folder for the expression study.
- Refined the five mood previews after player feedback. Compared tilted poses, uneven lids and brows, a sideways pout and a wider crying mouth against the previous five in Godot 4.7.2 Forward Mobile. [Revised and previous portraits](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi five emotions - expression refinement.png>). Close-up art review pending.
- Refined the fifteen remaining portrait studies and combined them with the latest five moods. Verified all twenty labels and faces in the [complete portrait grid](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi expression collection - refined.png>). New portraits used the runner model in Godot 4.7.2 Forward Mobile at 780 × 820. Awaiting art review. Gameplay expressions and transition timing are outside this preview.
