# Title and transition · 2026-11-27

## Checkpoint plan and handoff

1. Replace Continue/New Game with illustrated Play, Options and Quit controls. Keep desktop ribbon and landscape phone patch layouts, accessible names, safe hit areas, and initial Play focus.
2. Route the title's Play signal through the main menu. Crossfade to the opening atlas view in about 0.3 seconds, consume the initiating input, and restore title Play focus after Back, Escape or controller Cancel.
3. Review hover and keyboard/controller focus on every button. Compare fixed views before/after label centering, strawberry clearance and border saturation. Check Options and Quit through their normal controls.
4. Repeat Play → Atlas → Back with mouse and simulated touch at both review sizes. Exercise held confirm and double tap. Record the renderer, evidence and decision below before building the pannable map.

**Handoff** User-approved and pushed to origin/main in commit `db02f70`. The [working atlas](2026-11-27-working-atlas.md) supersedes the static checkpoint 2 preview.

## Changes and verification

- Enlarged the title focus strawberry by 18% and moved it inward. Verified text clearance on all three ribbons and patches at 1280 × 720 and 844 × 390.

- Raised the title lettering and removed the focus-dependent caption inset. Verified identical button-local label bounds through a full focus cycle and clearance for the strawberry beside every label on desktop and simulated phone. Compared the same Options-focused view [before](../source_art/LayoutReview/title-labels-before.png) and [after](../source_art/LayoutReview/title-labels-after.png).

- Review adjustment: all three buttons use the same ribbon or patch with a softer idle border. Moving focus restores the full coral border, raises the button, and displays the strawberry beside its label. Cycled through all three with Tab, checked pointer hover, and repeated the menu-flow test on desktop and landscape touch. The title captures below show Options and Quit focused.

- Play opens the First Steps Valley atlas preview in 0.30 seconds. Back, Escape, and controller B restore title Play focus. The atlas fits inside the landscape window; its disabled launch shows “Coming soon.” Panning and destination selection belong to checkpoint 3.
- Verified the configured title entry on Godot 4.7.2, Windows D3D12 Forward Mobile (RTX 4070 Ti SUPER). The menu-flow test passed with mouse and simulated touch, including a double activation, controller A/B events, and the separate rooftop pause/resume check. Checked held Enter, Escape, Options and Quit. Controller and touch input were simulated. All 340 gameplay checks passed.
- Captures: [desktop title](../source_art/LayoutReview/atlas-transition-desktop-title.jpg), [desktop atlas](../source_art/LayoutReview/atlas-transition-desktop-atlas.jpg), [phone title](../source_art/LayoutReview/atlas-transition-phone-title.jpg), [phone atlas](../source_art/LayoutReview/atlas-transition-phone-atlas.jpg). Desktop was 1280 × 720 and landscape phone preview was 844 × 390.
- **User-approved.** The title transition and revised focus styling passed player review. Atlas UI work continues in checkpoint 3.
