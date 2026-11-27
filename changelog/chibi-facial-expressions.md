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
- Previewed a camera-facing 3D thought cloud with delighted and surprised emoji in the rooftop gym. Compared front and rear views and a rear view at the configured play distance in Godot Forward Mobile. [Thought bubble study](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi thought bubble rooftop study.png>). Awaiting visual review before connecting gameplay reactions.
- Revised the camera-facing thought bubble with a taller, rounded scalloped cloud, larger face, raised brows and rosy cheeks. Captured the old and new surprised bubbles at the same rooftop play distance, plus delighted from the front, in Godot 4.7.2 Forward Mobile. [Round thought bubble comparison](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi round thought bubbles.png>). Preview awaiting review.
- Widened the cream cloud around the same surprised emoji. Verified the [14°, 45°, and 72° rooftop previews](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi cloud padding from above.png>) at the same camera distance in Godot 4.7.2 Forward Mobile. The cloud overlaps part of the head at 72°. Art review pending.
- Revised the thought cloud preview to rotate around the vertical axis only. Reduced its depth and kept the emoji on the outward face. Verified [rear, side, 45° and 72° views](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi upright cloud orbit.png>) in the rooftop gym with Godot 4.7.2 Forward Mobile. Preview only, pending art review.
- Created twenty matching emoji for the approved upright cloud style. Rendered individual transparent 400 × 440 previews in Godot 4.7.2 Forward Mobile and checked the [paired expression grid](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi expressions and cloud emoji.png>) against the refined portraits. Art review pending before gameplay integration.
- Rendered Sad with an ice-blue to dusk-blue cloud and Angry with a peach to coral-red cloud. Both gradients run continuously across the padded upright cloud and color its trailing puffs. [Original and gradient comparison](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi cloud mood gradients.png>), Godot 4.7.2 Forward Mobile. Art review pending.
- Moved the full dusk-blue gradient to Crying. Sad now has pale-blue accents on two lower cloud puffs and the smallest trailing puff. [Side-by-side Godot preview](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Sad and crying cloud colors.png>).
- Replaced the corner accent on Sad with a continuous powder-blue rim around the cream cloud silhouette and both trailing puffs. Reviewed the [Godot comparison with Crying](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Powder rim and dusk blue.png>).
- Softened the Sad cloud by extending the powder-blue fade nearly three times farther into the main puffs and scaling the fade to fit the smaller trailing puffs. [Godot before-and-after preview](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Sad soft powder fade.png>).
- The player liked the softer Sad fade. Assembled the [complete twenty-expression grid with the updated cloud colors](<C:/Users/count/.codex/visualizations/2026/11/26/01a2195a-164a-74f3-b7e4-5e26d3c07124/Chibi complete cloud palette.png>) for review.
- The player liked the complete palette and requested the [gameplay and animation integration plan](chibi-gameplay-expressions.md). The twenty-pose library is planned for manual access, with selective rooftop triggers.
- Checkpoint 1 implements the twenty manual face/cloud pairs and rooftop picker. [Implementation and verification](chibi-gameplay-expressions.md).
