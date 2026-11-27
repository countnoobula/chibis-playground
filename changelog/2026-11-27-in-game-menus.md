# In-game menus · 2026-11-27

- Inset the Gear tab’s top stitching and the Journal tab’s left stitching. Desktop and mobile now draw one seam per tab and recolor that same thread purple on hover or keyboard focus. Verified in-game captures and 298 headless checks.

- Adapted the stitched mobile tabs for desktop and retained the red embroidery on the active desktop tab. Moved the purple dashes inside the painted stitching and checked the corner spacing in desktop and landscape phone captures. All 298 headless checks passed.

- Inset tab dashes six artwork pixels from the cutout contour, preserving the cutout’s corner centers so the dashes stay parallel through the turns. Checked desktop and landscape mobile renders.

- Traced the dashed tab outlines along the painted shoulders and stopped both sides at the page binding. Checked each of the four tab contours at 1280 × 720 and 844 × 390 and verified that keyboard focus leaves the active tab alone.

- Added purple dashed hover and keyboard focus outlines that follow the rounded Gear slots and arched journal tabs. Confirmed hover and arrow navigation preserve selection in desktop and landscape mobile previews. The headless suite passed 298 checks.

- Updated the menus after the desktop and mobile audit. The mobile title art fills wide landscape windows, with safe-area patch positioning, clearer focus, and accessible image-button labels. Gear uses live item details and matching equipment previews. Map identifies the illustrated route as a field guide, Journal gives the rooftop strawberry a centered stamp, and the book cutouts have cleaner edges over the gameplay backdrop.
- Cleaned the in-game Options artwork, removed duplicate slider knobs, and fitted all four mobile graphics presets inside the page. View Controls uses a full-window input-blocking modal with larger bindings. State Inspector is available through `--debug-menu`.
- Verified the title-to-gym flow, menu navigation, settings, modal focus and input blocking, and Resume in Godot 4.7.2 Forward Mobile (Metal) at 1280 × 720 and 844 × 390. The headless suite passed 298 checks in both normal and developer runs. Mobile verification used simulated touch.

- Fitted the Gear outline to the painted rims of each desktop and mobile slot, with separate corner radii for the two spreads. Pointer selection shows a single outline and keyboard traversal keeps its own inset focus indicator.

- Removed the baked scarf outline and added a movable pink-purple Gear selection border. Hover and keyboard focus are separate. The top tabs use the active styling painted into each spread, with a separate inner focus ring. Verified mouse, keyboard, and simulated touch at 1280 × 720 and 844 × 390. The headless suite passed 294 checks.

- The Berry Journal now opens over a fresh HUD-free gameplay capture with a baked bokeh-style blur. The backdrop fills the window with aspect-preserving crop, and all eight transparent book spreads remain sharp. Verified fresh captures in two rooftop locations at 1280 × 720 and in the 844 × 390 landscape touch preview on Forward Mobile (Metal).

- Replaced the gameplay pause panel with the four Berry Journal spreads on desktop and [landscape mobile](../source_art/concept_art/Menus/berry-journal-mobile-pause.png). Gear renders the actual scarf canopy, print, and weave alongside the animated runner wearing the Peach Scarf. Map shows the illustrated route to Lantern Cottage, and Journal counts strawberries collected in the current gym run.
- Wired the stitched mobile settings index, desktop Graphics presets, View Controls, and Resume. Dynamic journal text uses the reusable [Berry Journal font](../ui/menu/berry_journal_font.tres), backed by the bundled OFL-licensed Lora font.
- Entered through New Game and opened the journal with Escape or a simulated finger on the gear. Checked the four spreads, graphics presets, camera inversion, guide navigation, Resume, and pickup progress at 1280 × 720, 844 × 390, and 736 × 414 with Godot 4.7.2 Forward Mobile (Metal, Apple M1). The headless suite passed 294 checks at fixed 60 FPS. Phone checks used simulated touch.
