# Editing the Roaming Atlas

Edit [roaming_atlas.json](roaming_atlas.json) and reopen the atlas to see changes. To add a destination, copy an entry, give it a unique snake_case ID, and set the fields below.

| Field | Used by the game |
| --- | --- |
| `id` | Stable destination key for selection and game references. Keep the ID when renaming a destination. |
| `position` | Pin tip in atlas map pixels, as `[x, y]`. The map is 1550 × 720, with the origin at the upper left and the lake to the west. |
| `pin.image` | Path to a **128 × 128 PNG**. Center the landmark and allow the corners to be cropped. The atlas supplies the circular mask, teardrop, selection stitching and ribbon. |
| `pin.text` | Optional map label. The ribbon uses the postcard title when omitted. Its width follows the displayed lettering. Long labels wrap, and each baseline follows the contour of the paper. |
| `pin.scale` | Scale of the entire pin. The default is 0.75. |
| `sticker` | Project texture path for the larger postcard illustration. The UI crops it to fill the stamp. |
| `title`, `tagline` | First and second parts of the quote. The title heads the postcard and the tagline appears in italics. |
| `description` | Story or gameplay description below the divider. |
| `enabled`, `scene` | Set `enabled` to `true` and supply a playable Godot scene path to show **Play**. Use `false` and an empty scene path for a future location. An unavailable destination stays inspectable with **Coming soon**. |

The order of the `destinations` array sets the tab order. Directional navigation uses map positions. Set `default_destination` to the ID that should open first. Godot reports malformed entries in its output with the catalog path and entry number.
