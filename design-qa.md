**Comparison Target**

- Source visual truth: `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-c70b1fb9-4cec-461a-8d56-dce0f7104e37.png`
- Rendered implementation: `/tmp/vorssaint-battery-implementation.png`
- Combined comparison: `/tmp/vorssaint-battery-qa-comparison-final.png`
- Viewport: macOS menu bar crop, 138 × 62 px per side.
- Density normalization: source 614 × 62 px at @2x; implementation 118 × 40 px for a 59 × 20 pt status-item image at @2x, composited into the same 138 × 62 px crop. CSS size is not applicable to this native AppKit view.
- State: 28%, plugged in but not charging, Low Power Mode yellow, light wallpaper/menu-bar appearance.

**Findings**

- No actionable P0/P1/P2 differences remain.
- Fonts and typography: implementation uses macOS system 11 pt regular; visible text is 44 × 16 px versus 45 × 16 px in the native reference.
- Spacing and layout rhythm: implementation icon is 52 × 24 px versus 51 × 24 px; text-to-icon gap and vertical baseline visually align.
- Colors and visual tokens: text, outline, and Low Power yellow use menu-bar translucency. Sampled dominant outline is RGB 101/120/141 versus 98/122/147; yellow is 245/205/73 versus 245/205/68.
- Image quality and asset fidelity: the icon is rendered from Apple's SF Symbol battery outline at @2x, with a continuous vector fill; no substitute raster or handcrafted icon is used.
- Copy and content: both sides show `28%`; no other app-specific copy is present.

**Evidence**

- Full-view comparison: `/tmp/vorssaint-battery-qa-comparison-final.png` contains implementation and native reference side by side at identical scale and state.
- A separate focused comparison was not needed because the complete target is already a focused 138 × 62 px status-item crop. The enlarged initial comparison is `/tmp/vorssaint-battery-reference-comparison.png`.

**Comparison History**

1. Initial P1 findings: custom text was 50 × 18 px versus native 46 × 16 px; the icon was 40 × 19 px versus native 51 × 24 px; fill snapped to 10% steps; colors and outline weight differed. Evidence: `/tmp/vorssaint-battery-reference-comparison.png`.
2. Fixes: switched to 11 pt regular text, an 18 pt native SF Symbol, exact 0...100 fill, rounded clipping, and native-sized charging bolt. The first revised comparison exposed a P2 translucency/color mismatch. Evidence: `/tmp/vorssaint-battery-qa-comparison.png`.
3. Final fix: matched the menu-bar text, secondary outline, and Low Power yellow translucency. Post-fix evidence: `/tmp/vorssaint-battery-qa-comparison-final.png`. Text height and fill width match; icon width differs by one antialiased pixel only.

**Implementation Checklist**

- [x] Native system font metrics
- [x] Native SF Symbol geometry
- [x] Continuous live battery fill
- [x] Charging-state bolt rendering
- [x] Menu-bar semantic/translucent colors
- [x] @2x side-by-side visual verification

**13% / Charge-Limit Iteration**

- Source visual truth: `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-b8053104-db65-48e4-a159-ffefe533b8c4.png`, `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-16d0bbe4-ab21-49db-9ca7-bde4baa9a625.png`, and `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-869cb3a7-c865-4fef-b1a9-52d0d31aa242.png`.
- Rendered implementation: `/tmp/vorssaint-battery-linear-13.png` and `/tmp/vorssaint-battery-plug-90.png` at @2x.
- Combined comparisons: `/tmp/vorssaint-battery-linear-13-comparison.png` and `/tmp/vorssaint-battery-plug-90-comparison-v2.png`.
- States: 13% Low Power Mode on a light menu bar; 90% connected to power but not charging on a dark menu bar.
- Initial P1 finding: clipping a full symbol used padded glyph bounds, reducing 13% to about 1 px and visually saturating 90% early. The fill now maps the real 19 pt battery interior directly and linearly: 13% and 90% render at 13% and 90% of that interior.
- Initial P1 finding: connected-but-not-charging reused a generic cable or plain battery state. The final render composes the native `powerplug.portrait.fill` symbol inside the live battery, matching the charge-limit reference.
- Typography and spacing remain unchanged from the verified native-size pass. The final side-by-side images show matching fill extent, icon dimensions, appearance-aware colors, and plug state; no actionable P0/P1/P2 differences remain.
- [x] Linear low- and high-end fill verification
- [x] Plugged-in, not-charging visual verification

**Live Menu-Bar Legibility Iteration**

- Source visual truth: `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-9c0480f7-1889-4305-be8e-bed3db58a892.png` (402 × 30 px at 1×).
- Rendered implementation: `/tmp/vorssaint-menu-bar-live-final-v8.png` (2560 × 1440 px desktop capture at 1×); matching 402 × 30 px menu-bar crop is included in `/tmp/vorssaint-weird-icon-before-after-final-v2.png`.
- Full-view comparison: `/tmp/vorssaint-weird-icon-before-after-final-v2.png`, with the reported state above and the revised live state below.
- Focused comparison: `/tmp/vorssaint-live-custom-vs-native-final-v2.png`, with the revised Vorssaint icon on the left and the live macOS battery on the right at the same display density and state.
- State: 90%, connected to power but not charging, dark translucent menu bar.
- Initial P1 finding: the plug cutout and faint outer outline visually merged the 90% fill into a standalone bow-tie shape; battery text and fill also peaked around RGB 230 while the native text reached RGB 255.
- Fixes: use full-opacity native `textColor` for the percentage and fill, resolve the outline alpha only inside the active drawing context, and widen the transparent separation between the native plug and the live battery fill.
- Post-fix evidence: the focused live comparison shows the complete battery perimeter, distinct plug silhouette, two separated fill regions, and matched bright foreground. No actionable P0/P1/P2 differences remain.
- Fonts and typography: unchanged 11 pt macOS system regular; native foreground brightness restored.
- Spacing and layout rhythm: block width, percentage-to-icon gap, glyph size, and baseline remain unchanged.
- Colors and visual tokens: native dynamic `textColor` drives the value/fill; its draw-time alpha drives the appearance-aware outline.
- Image quality and asset fidelity: battery and plug remain Apple SF Symbols rendered at native density; no raster substitute or handcrafted icon was introduced.
- Copy and content: both compared states show the live `90%` value.

**Vertical Padding Iteration**

- Source visual truth: `/var/folders/x4/yrl59l7x0n3gqkxb2qzvsk940000gn/T/codex-clipboard-9b0ecbd5-d0e9-4406-80bd-71250c6f75d6.png` (164 × 30 px at 1×).
- Rendered implementation: `/tmp/vorssaint-padding-after-target.png` (150 × 30 px at 1×), captured from the installed `/Applications/Vorssaint.app` on macOS 26.4.1.
- Combined comparison: `/tmp/vorssaint-padding-before-after.png` (220 × 30 px), with the reported state on the left and the revised live state on the right.
- Viewport and state: native 30 px menu bar, 90% battery and 34° battery temperature. The power-source glyph changed during the live capture, but the shared attachment bounds and typography used for the padding measurement did not.
- Initial P2 finding: visible ink occupied `y = 5...21`, leaving 5 px above and 8 px below, so the group was visibly high.
- Fix: restore the shared macOS 26 attachment correction from a 0.25 pt to a 1.2 pt downward nudge for battery, metric, gauge, network, and disk blocks.
- Post-fix evidence: visible ink occupies `y = 6...22`, leaving 6 px above and 7 px below. That is the pixel-balanced placement for 17 px of ink in a 30 px bar.
- Full-view and focused evidence use the same combined image because the complete source is already a focused menu-bar crop.
- Fonts and typography, colors and visual tokens, image quality, horizontal spacing, and copy are unchanged from the prior passed live iteration.

final result: passed
