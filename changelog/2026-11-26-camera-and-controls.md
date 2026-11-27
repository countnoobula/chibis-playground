# Camera and controls · 2026-11-26

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
