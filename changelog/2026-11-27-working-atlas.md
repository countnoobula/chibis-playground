# Working Roaming Atlas · 2026-11-27

## Implementation plan and starting files

1. Derive a continuous playable map view from the two [approved concepts](2026-11-27-atlas-art-and-tracker.md). Preserve the creek-to-lake geography and the calm skyline, cottages and woods.
2. Compose the clipped pin layer, moving landscape and fixed postcard in [the atlas scene](../ui/menu/atlas_preview.tscn). Anchor the pins by their pointed tips. Clamp panning at both illustrated ends.
3. Implement pointer/touch drag and controller navigation. Exercise drag starting on a pin and repeated confirm across the title transition. Separate selection from launch.
4. Build the shared stamp, quote, divider and action in [the postcard](../ui/menu/atlas_postcard.tscn). Review both rounded card corners and the animated drag hint at desktop and landscape phone sizes.
5. Store destination records in [the atlas JSON](../config/roaming_atlas.json). Read title, optional map-label override, image, sticker, quote, description, state and destination scene from the same entry. Verify a new entry can be reached and edited without a menu-script change.
6. Verify Title → Play → Atlas → Rooftop Gym → Play → pause → Resume, test pending entries and return to the title. Re-run the input flow in a fresh export to exercise the packaged JSON and art.

**Handoff** The player approved checkpoint 3 on 2026-11-28 and requested a planning discussion before starting the [terrain checkpoint](atlas-04-terrain-and-designer-defaults.md).

## Map and destinations

The eastern opening view follows the creek through the woods behind the village. Dragging toward the right reveals the western shore, where the river opens into a lake beside the fishing pier. The world uses one continuous illustration so the river and roads retain their positions throughout the pan.

The four illustrated markers share the stitched teardrop and parchment ribbon from the approved overview. The backstory and lake ribbons render their titles in the menu font. Cream stitching (`#FFF0DA`) marks idle pins. Plum stitching (`#9C427E`) marks a hovered, focused, or selected pin. The fixed postcard describes the selected destination.

| Destination | Availability in checkpoint 3 |
| --- | --- |
| First Steps Valley | Selected on entry. Creek crossing planned for the terrain checkpoint. |
| Change can be scary... | Reserved for replaying Chibi’s backstory. |
| We fear what we cannot see... | The boat pin in the western lake previews a future underwater area. |
| Rooftop Gym | Play opens the developer course. |

## Player review

Start at Title, choose Play, pan to the fishing pier, and return to the forest. Select each pin and inspect its postcard. Choose Rooftop Gym → Play, pause, and resume the course.

## Verification

- Godot 4.7.2 on Windows, D3D12 Forward Mobile with an RTX 4070 Ti SUPER. Tested the configured title entry at 1280 × 720 and 844 × 390 landscape. Controller buttons and touch gestures were simulated.
- The menu-flow test covered both pan limits, dragging from an unselected pin without changing the postcard, destination selection, disabled launch actions, Cancel and restored title focus. A controller-only route reached Rooftop Gym and launched it through postcard Play. Pause and Resume returned control to Chibi.
- The gameplay suite passed all 340 checks. The Windows Desktop export preset produced a PCK whose menu flow also passed when launched with the Godot executable.
- Confirmed the original marker assets contain the exact idle and active thread colors. The archive retains the approved v7 concept used to extract the pins and creek postcard.
- Captures include the [opening creek postcard](../source_art/LayoutReview/working-atlas-desktop-first-steps.jpg), [western lakeshore](../source_art/LayoutReview/working-atlas-desktop-lake.jpg), [Rooftop Gym selection](../source_art/LayoutReview/working-atlas-desktop-rooftop.jpg), and [landscape phone preview](../source_art/LayoutReview/working-atlas-phone-rooftop.jpg).

## Player-requested refinements

The village postcard pairs **Change can be scary...** with *...but it doesn't always have to be.* The lake pin sits in open water west of the pier. Its postcard pairs **We fear what we cannot see...** with *...but beneath the surface lies a world of wonder.* The underwater illustration comes from the project's Underwater concept. The other two destinations also have a short italic line above their descriptions.

A pending destination has one disabled **Coming soon** action. Rooftop Gym has **Play**. The updated menu-flow test covers all four destinations and verifies that the backstory and lake titles, italic copy, and launch states match.

The postcard sits directly over the scrolling landscape. At both pan limits on desktop and simulated phone, hiding the landscape changed pixels at all four rounded corners while the interior paper sample stayed identical.

The photo sits inside a cream stamp with a perforated edge, a slight tilt, and a wider paper margin. The centered diamond rule separates the italic line from the description. The enabled and pending actions share the same lower-right anchor. Compare the [village postcard](../source_art/LayoutReview/working-atlas-desktop-change.jpg) and [lake postcard on a landscape phone](../source_art/LayoutReview/working-atlas-phone-lake.jpg).

The hand on the drag hint sweeps left and right on a shallow arc. Compared 12 rendered frames of the hint at desktop size. Changed pixels stayed inside the finger area, with the paper, text, and arrows stationary.

## 2026-11-28 · Editable destinations and curved pin lettering

- The [destination catalog](../config/roaming_atlas.json) now drives all four markers, their tab order and opening selection. Each record supplies its stable ID, map tip position, square portrait, optional map text, postcard illustration, two-part quote, description, enabled state and playable scene. See the [field reference](../config/README.md) for editing units and defaults. Reopen the atlas after editing.
- The scene loader and postcard resolve the same configured target. Pending destinations remain inspectable. Both export presets include the JSON.
- Each marker uses a 128 × 128 PNG in a circular mask, a shared teardrop, and a parchment ribbon sized from the lettering. The text follows the measured midpoint of the paper between its top and bottom edges. The layout leaves clearance at the badge and the notched tail, and grows vertically for wrapped labels.
- At default scale, a short test label produced an 86.5-pixel ribbon, the lake label used 290.5 pixels, and a long three-line label used 390 pixels of width. Reapplying the short label restored the original size. Verified the revised visuals at 1280 × 720 and 844 × 390 using the isolated Windows D3D12 renderer; the linked screenshots above show the revised pins.
- [Catalog regression](../tests/test_atlas_catalog.gd) passed with an additional JSON-only destination, changed map art, a separate map label, a new default, custom position, and a different scene. Checked unavailable and invalid scene targets. The desktop and simulated-touch menu flows passed, as did the menu route from the exported Windows Desktop PCK. Gameplay suite result: 340 passed, 0 failed.
- The root tracker now links to individual plans for the remaining checkpoints. Each future record lists the starting files, player intent, task checklist, evidence to collect and next action. Record subsequent implementation and review in that same file.

**Review decision** · Player approved the working atlas on 2026-11-28. Physical-device results and Android export verification remain open for the end-to-end checkpoint.

### 2026-11-28 · Lake postcard

The player selected Lily-Root Hollow for the underwater expansion. The lake sticker in the [destination catalog](../config/roaming_atlas.json) uses the [approved render](../ui/menu/art/atlas/postcards/lake-lily-root-hollow.png), verified by SHA-256 against the selected source. The lake still shows Coming soon.

The headless menu flow passed. Captured the selected pin using Godot 4.7.2 Forward Mobile on D3D12 at [1280 × 720 desktop](../source_art/LayoutReview/working-atlas-desktop-lake.jpg) and [844 × 390 simulated phone](../source_art/LayoutReview/working-atlas-phone-lake.jpg). Artwork and checkpoint 3 approved.
