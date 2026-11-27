# Chibi changelog

## In progress

- **Chibi facial expressions** · Owner: Codex · Status: previews ready for review. Rendered smiling crescents, a wink, and two free-fall reactions on the current Godot model. Compared a tiny pout and a brave little smile with the earlier determined face.

Add each active target here with its owner, status, and a short description. Check the current project and reread this file before editing. Update your own entry and preserve edits from other agents. When work is verified, move it to the relevant section below with the date and the checks that ran.

## Woodland assets

### 2026-11-27

- Imported 69 reusable Parkour models and 62 shared textures, including grass, clover, flowers, moss, creek rocks, roots, lotus, and six baked FirstSteps trees. The [woodland manifest](assets/environment/woodland/manifest.json) records model sources, material slots, and local bounds.
- Preserved the editable sources and nine foliage presets in the sibling Parkour Art Archive. Verified that all six tree GLBs regenerate byte-for-byte and that the Chibi runner and audio exporter reads the archive.
- Verified a clean Godot 4.7.2 import, the plant silhouettes and tip movement in Forward Mobile, a dense planting sample, and the New Game route to the rooftop gym. The headless suite passed all 329 checks.

## In-game menus

### 2026-11-27

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

- Replaced the gameplay pause panel with the four Berry Journal spreads on desktop and [landscape mobile](concept_art/Menus/berry-journal-mobile-pause.png). Gear renders the actual scarf canopy, print, and weave alongside the animated runner wearing the Peach Scarf. Map shows the illustrated route to Lantern Cottage, and Journal counts strawberries collected in the current gym run.
- Wired the stitched mobile settings index, desktop Graphics presets, View Controls, and Resume. Dynamic journal text uses the reusable [Berry Journal font](scenes/menu/berry_journal_font.tres), backed by the bundled OFL-licensed Lora font.
- Entered through New Game and opened the journal with Escape or a simulated finger on the gear. Checked the four spreads, graphics presets, camera inversion, guide navigation, Resume, and pickup progress at 1280 × 720, 844 × 390, and 736 × 414 with Godot 4.7.2 Forward Mobile (Metal, Apple M1). The headless suite passed 294 checks at fixed 60 FPS. Phone checks used simulated touch.

## Main menu

### 2026-11-27

- Implemented the [mobile Berry Journal](concept_art/Menus/berry-journal-mobile-options.png) with a stitched category index, touch sliders, a touch controls guide, and a fixed Back button. Verified settings, navigation, and persistence at landscape phone sizes (844 × 390 and 736 × 414) with simulated touch on the Mobile renderer. Checked desktop navigation and ran the headless suite (254 passed).

- Replaced the title bar with [scarf ribbons](concept_art/Menus/desktop-scarf-ribbons.png) on desktop and a two-by-two grid of [picnic patches](concept_art/Menus/mobile-picnic-patches.png) on mobile. Each button sits directly on the scenery. The desktop preview flag is `-- --mobile-menu`.
- Checked keyboard and mouse navigation at 1280 × 720 and simulated finger taps and drags at 844 × 390 in Godot 4.7.2 Forward Mobile (Metal, Apple M1). Verified the berry, disabled Continue, New Game, Options, sliders, Back, and Quit. The headless suite passed 254/254 at fixed 60 FPS. Touch checks used the phone-sized desktop preview.
- Enabled Options on the title screen using the [approved Berry Journal spread](concept_art/Menus/berry-journal-title-options.png). Master, Music, and Sound Effects sliders, camera sensitivity and Invert Y, and four graphics presets apply immediately and persist across launches. View Controls shows gameplay bindings. Back and Escape restore Options focus on the title.
- Verified the keyboard and mouse round trip at 1280 × 720 and 900 × 600, audio bus levels, gameplay look input, separate-process persistence, and all four presets from one rooftop viewpoint on Godot 4.7.2 Forward Mobile (Metal, Apple M1). Headless suite passed 254/254 at fixed 60 FPS.
- Clicking the title strawberry now pulses it to about 110% and rocks it back to rest while all three strokes redraw together over 0.33 seconds. Verified single and repeated clicks, preserved menu focus, and resized hit targets on Godot 4.7.2 Forward Mobile (Metal). The headless suite passed 254/254 at fixed 60 FPS.
- Made the approved *Scarf in the Sky* title screen the game entry point. New Game opens the rooftop gym, Quit exits, and Continue and Options are disabled. The strawberry wiggles occasionally and replays its three painted accent strokes when clicked.
- Verified mouse, arrow-key, Enter, and mixed navigation, repeated berry clicks, and both game actions. Compared the title composition at 1280 × 720 and 900 × 600 on Godot 4.7.2 Forward Mobile (Metal, Apple M1). The headless suite passed 254/254 at fixed 60 FPS. An earlier unpaced run missed the rooftop full-flow mantle timing threshold once.

## Concept art

### 2026-11-27

- Approved the Berry Journal in-game menu concept after reviewing all four spreads. [Gear](concept_art/Menus/berry-journal-gear.png), [Map](concept_art/Menus/berry-journal-map.png), [Journal](concept_art/Menus/berry-journal-v2.png), and [Options](concept_art/Menus/berry-journal-options.png).

### 2026-11-26

- Approved [Scarf in the Sky](concept_art/Menus/scarf-in-the-sky-v7.png) as the Strawberry Hollow main menu concept. The canopy uses the posed 3D scarf as a shape reference, with a continuous sheet, overlapping hems, and gathered hand grips.
- Turned the Scarf in the Sky canopy to match Chibi’s three-quarter glide. Visually checked the near underside and foreshortened far grip in `concept_art/Menus/scarf-in-the-sky-v6.png`.
- Restored the original woven fabric texture on the peach canopy. Visually checked the weave, open underside, and smooth silhouette in `concept_art/Menus/scarf-in-the-sky-v5.png`.
- Smoothed the Scarf in the Sky canopy into a single taut curve. Visually checked the open underside and sky gap on `concept_art/Menus/scarf-in-the-sky-v4.png`.
- Opened the scarf canopy in the Scarf in the Sky title-screen concept so its underside and the gap above Chibi are visible. Visually checked `concept_art/Menus/scarf-in-the-sky-v3.png` at full size.
- Updated five menu concepts with the petal lantern design. Revised the Scarf in the Sky mockup so Chibi holds a single billowing scarf canopy directly in her hands. Visually checked the revised artwork and saved it as versioned PNGs in `concept_art/Menus`.
- Generated and visually checked three Strawberry Hollow title screens and three pause-menu concepts. The six widescreen mockups and their prompts are in `concept_art/Menus`.
- Removed the dark rounded backing from the scarf’s strawberry print, packed the transparent 4096 × 4096 texture into the Blender file, and rerendered both views.
- Rendered Chibi gliding with her peach scarf, with two cloth corners gathered in each hand and the Strawberry Hollow print overhead. Verified the direct hand contact and fitted the existing goggles and strap to her head bone in the Blender scene.
- Shaped the hand-held parachute like a pink gingham picnic blanket with four inward-curled corners. Updated the posed render and close-up, and verified the four mesh folds, steering loops, and packed logo in Blender.
- Modeled and rendered Chibi’s hand-held cloth parachute, with blush and cream panels, mint trim, and two steering loops. Reopened the Blender scene and verified that the Strawberry Hollow logo from `icon.svg` is packed at 4096 × 4096. The posed render and canopy close-up are in `concept_art/Chibi/Parachute`.
- Saved the approved Selfie and refreshed ten related concepts with Chibi's goggles, Pip's sculpted fairy design, and the rounded First Steps woodland terrain. Kept the map and HUD labels and verified all eleven Godot 4.7.2 texture imports against their source PNGs.
- Refreshed ten concept images with Chibi's current short chestnut bob and single ahoge, including the Selfie, Scuba Mask, HUD, First Steps maps, and character moodboard scenes. Verified that all ten Godot 4.7.2 texture imports matched their source PNGs.

## Rooftop gym

### 2026-11-27

- Chibi checks capsule clearance before and during vaults, ledge moves, mantles, net climbs, and aerial rides. The vault clears all three bars with planted hands. Low net mounts stay above the deck, and blocked pool pull-ups keep Chibi swimming.
- Pole and beam mounts and trampoline bounces use physical top contact. Raised the first pole's starter step to 0.60 m. Rope catches check reach and clearance, and the swing has a visible handle with two tracked hand grips.
- Added a 2.35 m warm-white launch perch with a mint-trimmed ramp and a peach step-off marker beside the tunnel entrance. The rooftop builder includes the perch, and the ground lane stays clear for running and sliding.
- Added soft ivory and mint gust ribbons through the lane. Local wisps split around Chibi’s palm and shoes and sweep along the open scarf. Cleared the mast nearest the launch to give the chase camera a view of the canopy.
- Added an open-air wind tunnel on the dry deck southeast of spawn. Mint arrows mark the airflow, and ivory streamers, drifting streaks, and a quiet spatial wind loop follow the same 4.2-second gust cycle. The rooftop scene builder includes the lane.

### 2026-11-26

- Added warm daylight, softer shadows, and a pastel sky. Reduced the contrast of the roof seams and softened obstacle edges.
- Added pastel caps and contact faces to warm white obstacles. Carried the palette through the climbing stations, aerial equipment, and pool.
- Updated the scene builder so the rooftop can be regenerated on its own with the same materials and route markings.
- Matched the Mint Street palette with a turquoise sky, a peach horizon, and low golden sunlight. Added lavender fill and a light haze near the far edge of the gym.
- Replaced the flat cloud mask with ray-marched cumulus banks. The banks and thin wisps drift overhead on a slow breeze.
- Replaced the fixed climbing panel with a warm-white masonry route, pastel-edged lips, a diagonal jump gap, and a top-out onto the deck. The generated rooftop uses the same wall scene.
- Removed the grid from the dynamic climbing wall and moved the pastel grip accents onto the grip meshes to fix overlapping surfaces. The Zone 3 spawn lines up with the starter grip.
- Rebuilt Zone 5 as an asymmetric swim training basin. A mint walk-in band leads to a shallow shelf and a wider deep end. Rounded porcelain coping follows the shoreline, and a peach cap marks the climb-out. The scene builder derives the deck opening from the basin outline.
- Added an 8 m climb tower east of Zone 5. Chibi can attach to all four faces, follow the sills and offset bricks, turn around each corner, and mantle onto the roof. The mint launch mark points toward the drop pool.
- Added a separate 3.6 m deep drop pool with a peach climb-out and a covered tunnel to Zone 5. The tunnel floor meets the existing basin bed, and the water volume ends at the underside of the cap. The gameplay camera shortens and lowers its follow arm in the tunnel.
- Added a rooftop drop readout for the air fall from the apex, the depth of the initial plunge, and the total vertical fall. The test jumps measured 7.30 m in the air and 1.05 m underwater.
- Replaced the tower's wraparound rails with separate collidable windowsills, ledges, and offset bricks. Pastel caps mark the holds. Close steps and wider gaps break up all four climbs, and paired corner bricks connect the faces at two heights.
- Extended the inner ends of the paired corner bricks on both lap courses to keep the next hold within a short hop. The spaces between the holds remain open.
- Brought the farther bricks closer to the offset window sills and lowered the top outboard holds enough to leave room under the roof lip.
- Beveled the tower’s warm-white masonry and wrapped each grip’s upper lip in a pastel tile. Layered the window reveals, softened the base with a mint trim band, and added warm fill on the shaded faces. A quiet breeze plays near the tower, with spatial hand, shoe, and cloth sounds on catches, braces, and transfers.

## Chibi movement and animation

### 2026-11-27

- Wall runs start from a running jump close to the wall with steering along it. Casual hops and ledge drops stay in normal air movement, and a wall kick can transfer to the opposite wall. Verified the rooftop corridor with the Mobile renderer at 60 physics ticks per second and passed all 330 headless checks.
- Releasing A or D when dropping from a shimmy gives Chibi 0.18 seconds of gentler sideways braking. Directional input can steer her as soon as she lets go.
- C, Ctrl, and touch Drop release Chibi while she shimmies or rounds a ledge corner. She carries her sideways motion into the fall and drops without sideways drift from a resting hang.
- Rebuilt the scarf canopy as a deeper continuous arch with a real thickened shell, a cream binding, a shaded underside, and a subtle weave. The canopy spreads across first, then fills out with air. The crown and edges respond more strongly to descent, banking, and tunnel wind while the four corners stay anchored in Chibi's hands.
- Chibi carries her speed from scarf glide into the first running step. The gait starts at touchdown with the leading reachable boot, a short landing compression, and a support that releases at toe-off. Near-stationary landings keep a soft two-foot settle.
- The canopy gathers while all four corners are still in Chibi’s hands. The throwing hand starts to swing back first as the fabric transfers to the collar, and the loose end trails into the running stride. Partial openings use a smaller gather. Jump can take Chibi into a fresh hop before the wrap finishes.
- The tunnel catches Chibi’s scarf as it opens. The canopy billows downwind and its hems flutter with the gust while all four corners stay in her hands. Chibi can steer across or against the airflow, and she keeps coasting as the load fades at the edge. The assisted carry earns no Flow.
- Deepened the headwind brace with bent knees and a stronger reach into the palm. At the gust peak her shoulders rock back, the supporting shoe stays planted, and the free boot trails downwind before the stride recovers.
- Chibi braces into the headwind with her right palm forward. At the gust peak she gives ground, keeps one shoe planted, and trails her free ankle downwind. Both scarf tails flutter with the gust.
- Tailwinds add up to 12% of current running speed. Flow scores the runner’s own effort. Slides stay low after button release, turn into the airflow, and carry momentum into a jump or through an exit. Sideways steering can take Chibi out of the lane.

### 2026-11-26

- A fresh Jump, Ctrl, or C folds the scarf while it is opening or fully open. Ordinary gravity resumes from Chibi's current velocity as her hands release into the fall and the wind wisps fade. The cancel consumes the press, and a new airtime re-arms glide.
- The canopy's last fold gathers toward Chibi's throwing shoulder. The long scarf end carries the toss into her running stride, lags slightly through a turn, and returns to the scarf's spring motion as she slows or stops.
- The scarf catches air during deployment, ripples more with descent speed, and lifts at the hem during turns while all four corners stay in Chibi's hands. Her shoulders follow the bank and her knees soften in flight. She tosses the loose cloth over one shoulder on dry touchdown and releases each hand into her next running stride. Two short ivory wind wisps follow her flight path and fade during the wrap.
- Fixed the running wind ribbon’s doubled world offset. Its leading edge follows Chibi through turns, the trail fades on stops, and respawns clear it immediately. Verified the rooftop route at 30 and 60 FPS with the Mobile renderer and passed all 238 headless checks.

- Added scarf glide. Press Jump during a clear descent to draw the peach scarf from Chibi's collar and open it overhead, with two cloth corners held in each hand. Camera-relative steering eases into a 2.4 m/s descent. On dry touchdown she tosses the scarf back around her neck while ground movement resumes. Water entry, trampoline bounces, and respawns hand control back to their existing poses.
- Planted Chibi's shoes on the rounded balance log. Each walking step follows travel distance, and both shoes hold contact during pivots. Slowed the beam walk from 2.45 to 1.70 m/s to fit her shorter stride.
- Underwater bubbles start at the submerged upper vent on the snorkel. One opaque strap follows the head through equip and stow, blending between lavender and sage. Verified from the side in the rooftop gym with the Mobile renderer and passed all 201 headless checks.
- Chibi pulls her forehead goggles down when swimming starts. They become a mint dive mask and seated snorkel. The gear stays fitted through dives, water-body handoffs, and pool mantles. She pushes it back up in the shallows after climbing or swimming out. Verified the transitions and visuals in the rooftop gym with the Mobile renderer, and passed all 197 headless checks.
- Synchronized the run and sprint cycles and tied the gait to actual movement. Preserved partial stick speed and aligned footsteps with foot contacts.
- Fixed repeated restarts on jumps, soft landings, and wall kicks. Timed vault and mantle poses to the movement path and kept the slide pose low until the standing capsule clears the gate.
- Smoothed wall-run entry and fixed stale station overlaps that could recapture Chibi after a respawn.
- Added directional traction and a weighted pivot for sharp turns. At full Flow, a 180° reversal went from 22 to 7 physics ticks and from 1.32 m to 0.22 m of carry, matching the recorded Unreal run. A 90° turn takes over in 5 ticks. Release braking still stops in 1.20 m.
- Tied the run and sprint cycle to distance traveled. The planted shoes follow the walkable surface with leg IK, and footsteps trigger when the rendered shoe reaches its contact point.
- Timed jump takeoff to the rise and running landing to floor contact. Running landings add a brief pelvis compression over the advancing stride and preserve forward speed. Standing soft landings, buffered jumps, and landing rolls retain their own transitions.
- Added reusable climbing on upright static walls tagged `climbable_wall`. The controller finds grips from physical geometry and sweeps Chibi’s capsule through reaches, leaps, and top-outs. Individual hand and foot targets drive her pose and follow changes to the wall layout.
- Chibi automatically grabs on a straight approach or a jump into the wall. Holding Up leaps the halfway gap, and left and right steer along available grips.
- Holding Up at the tower's summit pulls Chibi onto the roof when the landing is clear. An upward leap that catches the final hold can finish the climb after Up is released. The leap pose loads the shoulders before the push and settles through the lead hand before the trailing limbs.
- Left and Right alone carry Chibi across the tower with planted reaches and low hops to nearby holds. The takeoff moves through the weight shift, reaches carry speed through the handoff, and the lead hand settles into the catch. The rig interpolates contact poses between physics ticks, and the climbing camera follows the turn around corners.
- Chibi looks toward the next hold through reaches, hops, catches, and corners. Head and neck aim from the rig’s calibrated facing axes, and her idle gaze settles slightly above level. On the tower, a supporting shoe braces against an available foothold while the free leg steps, tucks during hops, and settles into a soft bend.
- After a short neutral hang, Chibi gives a small head tilt and moves her free feet at different rhythms. The motion blends out with steering while planted hands and shoes keep their targets.
- Expanded the tower hang with a breathing rhythm, alternating shoulder and hip shifts, timed glances at nearby holds, and uneven free-foot swings. The body eases out of the idle when direction input resumes, with planted wrists and shoes held at their anchors.
- Chibi shifts a shoulder and looks sideways as she settles onto a tower hold, including after a transfer. Longer hangs alternate side glances and a look up the route with independent ankle motion. Directional gaze takes over when she moves.
- Directional input alone now covers the tower’s longer gaps and short steps down. The tower tries planted reaches and short hops before widening the search for a reachable catch. Roof pulls remain available from Up at the summit.
- Added a depth-driven wade on Chibi’s existing rig. Her stride shortens as the water rises, and she guides herself with alternating side sweeps. When she stops with her feet on the bottom, the arms settle into a small balancing loop. An idle swimmer at the surface blends into treading.

## Camera and controls

### 2026-11-26

- The touch Jump button shows Drop while the scarf is active. Lifting the finger that opened the scarf leaves it open until the next press.
- The touch Jump button displays a parachute symbol whenever Chibi can deploy her scarf and dims while she glides. The symbol shares the same eligibility check as the Jump action, including floor and overhead clearance.
- Adjusted the camera framing, smoothed look and Flow changes, and reset camera history on teleports.
- Hid the state inspector on launch and kept the existing debug toggle.
- C and Ctrl now drop Chibi from the rope line and zipline. The rope line releases straight down. The zipline carries forward momentum and resets the pulley. Space keeps its jump-off on both lines.
- Added a floating lower-left joystick, right-side camera dragging, and translucent circular actions. Fingers keep their assigned controls until release, and action labels follow swimming, ledge, and line states.
- Added a shared pause menu with Resume, Touch Controls, and State Inspector. Escape opens it on desktop and a gear opens it on touch screens. Pause, focus loss, and overlay changes clear active touches.
- Angled the camera to show wall contacts. Added separate Leap and Drop actions for wall climbing, with touch labels for both.
- Mouse, right stick, and touch drag now orbit the climbing camera. The chosen angle stays through corners and carries into the normal view on a roof pull or dismount. The camera pulls in away from masonry and eases back to its normal distance as the view clears.
- Replaced visible touch action labels with the approved warm-white silhouettes for jumping, sliding, swimming, climbing, and dismounting.
- Added a contextual strawberry pickup and placed one practice item beside the rooftop vault lane. The button appears within reach of an unobstructed item. Tap it, press E, or use the existing gamepad pickup binding to collect the item.
- Reserved pickup input for items. Approaching a climbable wall or net mounts it, and jumping toward a reachable ledge catches it. Holding forward can carry a ledge catch into a mantle.

## Water

### 2026-11-26

- Added a reusable `WaterBody3D` scene and `WaterProfile` for level-authored shorelines, surface heights, depths, and water appearance. The shared renderer adds transparent teal water, warm caustics on the bed and rocks, a rippling underside, surface rings, and rising bubbles.
- Moved water selection, wading, and swimming into Chibi’s physics update. The camera blends its own depth haze when submerged. Adjacent and overlapping bodies hand off without resetting the swim, and dry respawns clear wet movement and camera state.
- Converted the rooftop basin, opened the deck under its deep floor, and moved the zone spawn to the dry approach. Added the separate rocky basin with an irregular shoreline, a sloped bank, and a different surface height.
- Passed 174 headless checks. Continuous runs verified wading, diving, submerging the gameplay camera, and resurfacing in both basins. The rooftop check also verified mantling out onto the coping.
- Captured both basins on the Windows D3D12 Mobile renderer at 1280×720. The three matched rooftop views measured 0.34–0.43 ms GPU time at the 95th percentile, compared with 0.34–0.67 ms before the change on the RTX 4070 Ti SUPER.
- Compared a softer sunlight pass with the original water lighting and restored the original caustics and surface shader based on playtest feedback. The reshaped rooftop and separate rocky basin both use the shared water system.
- Verified both basins above, at, and below the waterline with Windows D3D12 Mobile at 1280×720. Continuous inputs verified wading, diving, camera submersion, and surfacing in both basins. Chibi returned to land via the rocky bank and climbed out at the rooftop’s peach ledge.
- Passed all 179 headless checks, including the reshaped basin’s dry corner and deep-floor collision. Godot still reports audio resources in use on headless shutdown.
- Walking into a swim carries horizontal momentum into the first stroke. On the way out, buoyancy eases near a shallow bank and the swim pose blends upright as Chibi finds footing.
- Passed 182 headless checks. D3D12 Mobile replays at 30 and 60 FPS verified walk, wade, grounded idle, swim, tread, and a return to dry ground in the rooftop and rocky basins. In both levels, turning back just before the swim threshold kept Chibi grounded, and heading straight in still allowed diving and resurfacing.
- Tuned stroke cadence to travel speed, added a short glide on release, and blended rest into surface treading or quiet submerged sculling. Chibi banks and sweeps her hands through turns, then brakes before pushing off in a reversal.
- Added a dive tuck and kick, smoothed the brake at the waterline, and kept the submerged pose under enclosed water ceilings. Short taps and held dives have separate descent curves.
- Passed 187 headless checks. Matched D3D12 Mobile replays in the rooftop and rocky basins at 30 and 60 FPS covered stops, restarts, quarter turns, reversals, short and held dives, and resurfacing at rest and in motion. At full speed the release glide carried 0.36 m. The matched ascent overshot its buoyancy target by 0.014 m, down from 0.040 m. Both wade-to-swim round trips also passed.

## Builds and exports

### 2026-11-26

- Added `tools/build.ps1` and Godot export presets for Windows x64 and Android. The script builds both by default and accepts `-Target Windows` or `-Target Android`. The outputs are in `builds/windows` and `builds/android`.
- Enabled ETC2/ASTC texture imports for Android. The debug-signed APK includes ARM64 and x86_64 and passed signature verification.
- Installed and launched the APK on the Android emulator. The touch HUD appeared on startup, and the joystick, camera swipe, and jump button worked.
- Launched the Windows release and confirmed the native pause menu showed Touch Controls off. A gameplay probe using the exported Windows data pack confirmed mouse capture and verified forward movement and camera look with injected Godot input events.
- The integrated Godot headless suite passed all 254 checks.

## Verification

### 2026-11-27

- Passed 325 Godot 4.7.2 headless checks. Side-view rooftop replays at 30 and 60 FPS on Windows D3D12 Mobile confirmed left and right carry when A or D is released at the same time as C or Ctrl.
- Passed 323 Godot 4.7.2 headless checks. Side-view rooftop replays at 30 and 60 FPS on Windows D3D12 Mobile verified left and right shimmy releases, stationary drops, and a drop during a corner turn.
- Passed 318 integrated Godot 4.7.2 headless checks and the focused wall, tower climb, gap, drop-well, and tunnel camera checks. Replayed the rooftop traversal routes from gameplay and side views at 30 and 60 FPS on Windows D3D12 Mobile at 1280×720. The swing kept both wrists within 2.3 cm of their grips. Some standalone tower checks reported the existing resource cleanup warnings at shutdown.
- The canopy pass retained all 288 Godot headless checks. Verified the four exact grip anchors on the imported 2,848-triangle mesh and replayed opening, steering, and landing from the chase and side views on Windows D3D12 Mobile. Peak-wind replays at 30 and 60 FPS showed full cloth load, and the touch cancel returned to free fall.
- Passed 288 integrated Godot 4.7.2 headless checks, including eight new checks for gait entry, first-shoe contact, cloth transfer, partial wraps, and hopping during a wrap.
- Compared the same rooftop inputs before and after at 30 and 60 render FPS in gameplay and side views on Windows D3D12 Mobile at 1280×720. The replays covered the wind perch, gentle steering, a neutral landing, a turn, and a quick hop. At 40% stick, Chibi kept her 1.76 m/s approach speed and entered the gait on touchdown, removing a 14-tick pause. The largest sampled wrist movement in that replay dropped from 13.9 cm to 8.1 cm per frame at 60 FPS.
- Passed 280 integrated Godot 4.7.2 headless checks, including nine new checks for the walk-off launch, canopy pins, steering, Flow, side exit, touchdown, Drop, and respawn. Neutral glide measured 1.00 m/s of downwind carry in the lull and 3.00 m/s at the peak. The side-exit check retained 1.98 m/s of carry.
- Matched gameplay and side-view replays at 30 and 60 render FPS on Windows D3D12 Mobile at 1280×720. The replays reproduced the ramp launch, loaded steering, landing wrap, and 0.80 m/s peak blowback. Regenerated a rooftop scene to a temporary path and confirmed the builder placed the perch correctly.
- A separate forced headless shutdown reported a resource cleanup warning for the tower wind audio loop. The integrated suite and rendered replays exited cleanly.
- The wind tunnel passed all 17 focused checks and all 271 integrated Godot 4.7.2 headless checks. The live rig checks covered palm reach, shoe contact, trailing ankle position, and scarf reset on respawn.
- Matching gameplay and side-view replays on Windows D3D12 Mobile reproduced the same movement and slide transitions at 30 and 60 render FPS. Full upwind input measured 2.93 m/s forward in the lull and 0.80 m/s backward at the peak.

### 2026-11-26

- All 254 headless checks passed. New Zone 3 tests cover a wall catch after a one-tick stick release and a deliberate steer away from beyond reach. Windows D3D12 Mobile rooftop replays at 30 and 60 FPS covered opening and fully open cancellations, simultaneous input, and a running touchdown while the scarf finished folding.
- The scarf-tail pass cleared all 19 focused glide checks, a second unteleported glide, and a same-position respawn during the follow-through. Side-view rooftop replays at 30 and 60 FPS on Windows D3D12 Mobile matched touchdown and covered a run, a turn, and a quick stop. The full suite returned 237 passes and one wall-catch failure that also reproduced with the scarf-tail modifier disabled.
- Scarf animation and wind polish passed all 238 integrated headless checks. Matching rooftop replays on Windows D3D12 Mobile at 30 and 60 FPS preserved the baseline path through a steering reversal, coast, and moving touchdown. Focused checks verified a partial-deployment landing, the return of both hands to gait, and immediate clearing of the wind wisps on midair respawn.
- Scarf glide passed all 234 integrated headless checks. Matching Windows D3D12 Mobile replays at 30 and 60 FPS used the touch Jump button after stepping off the climb tower, steered through a 7.74 m descent, landed, and returned to the running pose. The rendered checks showed the four hand-held corners, forehead goggles, and borderless Strawberry Hollow print.
- Passed all 233 integrated checks for the touch silhouette and pickup pass. The Windows D3D12 Mobile playtest verified the hidden and visible pickup states, collection, a forward-jump ledge catch and mantle, and a walk-on rope net mount. Corrected an indentation error in the concurrent scarf pose integration during verification.
- Focused balance-log checks passed at 30, 60, and 120 render FPS, with planted sole error within 2 cm. Verified mounts and step-offs onto both pads and recorded a side view with the Windows Mobile renderer. The integrated run passed 205 checks before concurrent scarf-glide cases were added. The later run passed 219 checks and returned three failures in the scarf-glide cases.
- The rooftop polish pass closed with 106 passing Godot 4.7.2 headless checks.
- The same three-vault and slide route cleared at 30 and 60 render FPS using the Mobile renderer on Windows.
- After the Mint Street pass, all 106 checks passed and the route cleared at 30 and 60 render FPS with the animated sky. Matched views and a fixed-camera 12-second capture verified the cloud drift. At 1280×720 on the RTX 4070 Ti SUPER, the Mobile renderer’s GPU render time increased from 0.427 ms to 0.698 ms at the 95th percentile.
- The movement pass verified playback and return to gait for all 33 active clips. The three legacy Rope clips remain imported and are bypassed by the Sloth clips. The three-vault and slide route cleared, and the climbing wall, net, trampoline, pole, balance beam, and rope swing passed station checks.
- All 121 checks passed at fixed 60 and 120 render FPS and in the standard headless run. At fixed 30 FPS, the new movement checks passed and the same seven legacy assertions failed as in the baseline. A physics-tick replay verified that buffered jumps take priority over soft landings at all three render rates. The Mobile renderer replayed the rooftop movement inputs at 30, 60, and 120 render FPS with 60 Hz physics. Planted shoe drift stayed within 2.5 cm at base speed and full Flow. The moving landing held 7.8 m/s through its blend.
- All 127 checks passed in standard headless mode and at fixed 60 FPS with the Mobile renderer. Six keyboard checks verified C, Ctrl, and Space on both rooftop lines, including release velocity, the regrab cooldown, and the zipline pulley reset.
- The mobile controls pass finished with 149 headless checks. Native touch events verified simultaneous movement, aim, and action, input cancellation, menu routing, and rope line and zipline dismounts. Windows Mobile renderer previews verified 16:9, wide-phone, and 4:3 tablet layouts and desktop mouse capture.
- Dynamic climbing passed 173 integrated headless checks alongside the current water changes and 27 geometry checks. The rendered rooftop run cleared the diagonal leap and top-out at 60 FPS. The supporting wrist stayed within 2.8 cm of its grip during reaches.
- The wall follow-up passed all climbing assertions and 27 geometry checks. A 60 FPS D3D12 Mobile replay verified the plain wall face, automatic grabs, both shimmy directions, and the automatic gap leap. The suite passed all 178 checks before the current basin edits and returned 177 passes with one rooftop basin-floor assertion during the concurrent water pass.
- The tower and tunnel pass passed 187 integrated checks and 68 focused checks. Verified all four mounts, two complete laps in opposite directions, summit top-out, drop and climb-out, bidirectional tunnel swimming, and underwater camera turns. Captured gameplay on the Windows D3D12 Mobile renderer at 1280×720.
- The spaced tower route passed 34 focused assertions, including Up-only climbs on all four faces, corner laps in both directions, lateral leaps, and blocked-summit recovery. The integrated suite passed all 201 checks. At 1280×720 and 60 FPS on Windows D3D12 Mobile, one continuous replay climbed with four reaches and seven leaps, topped out, and recorded a 7.30 m air fall and a 1.05 m plunge. The drop and underwater tunnel camera checks also passed. Godot reported resource cleanup warnings when the focused headless scripts exited.
- Passed all 205 integrated checks and 41 focused tower checks. Direction-only laps completed in both directions at both marked heights. At 60 and 120 FPS on Windows D3D12 Mobile, sampled sideways hops traveled 0.38–0.69 m, rose at most 0.12 m, and the ascent's near-still takeoff dropped from seven physics ticks to one. All four Up-only roof climbs passed, along with the drop and underwater camera checks. Focused scripts still reported resource cleanup warnings at exit.
- Passed all 234 integrated checks and 47 focused tower checks. D3D12 Mobile replays at 60 and 120 FPS showed roughly 35° of upward gaze through the ascent and 28–45° of knee flexion during sideways reaches and corners. The tests verified directional gaze through catches, stable shoe contacts on the ascent, and both full laps. The drop and underwater camera checks passed.
- Passed 238 integrated checks, 47 focused tower checks, and all 19 directional gap coverage checks. Directional input completed all 96 lateral out-and-back routes across the 12 courses and four faces, four full center descents, and eight ascents and descents from off-center starts. Both paired courses also cleared complete laps in both directions. At 60 and 120 FPS on Windows D3D12 Mobile, the free hang showed about 4° of head motion and 1.2 cm of free-foot travel with steady planted contacts. The drop and tunnel camera checks passed.
- The tower presentation pass cleared 238 integrated checks, 50 focused tower checks, all 19 gap coverage checks, and all 30 underwater camera checks. Replayed 96 lateral routes and four descents with directional input. Windows D3D12 Mobile replays at 30 and 60 FPS verified mouse, stick, and touch orbit, direction-only corner hops, camera clearance, automatic top-out, dismount, and a 7.30 m air fall with a 1.05 m plunge. The longer hanging idle turned Chibi’s head about 16° and moved her free foot about 5 cm while planted contacts stayed steady.
- The faster hanging idle passed all 54 focused tower checks and all 254 integrated checks. Windows D3D12 Mobile replays at 30 and 60 FPS measured 24–25° of lateral gaze within the first half-second at both a first catch and a regrip. Sampled wrist error stayed within 7 mm, planted shoe error was below 1 mm, and longer hangs looked to both sides and up. Directional gap coverage, drop-pool, and tunnel camera checks passed.
