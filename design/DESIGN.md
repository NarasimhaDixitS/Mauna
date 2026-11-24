# Mauna design rules

The rules any person or agent building Mauna's UI must follow. Values live in [`tokens.json`](tokens.json); the visual reference is [`design-system.html`](design-system.html).

Based on Emil Kowalski's design-engineering rules ([emilkowalski/skills](https://github.com/emilkowalski/skills): `emil-design-eng`, `apple-design`), adapted to a native SwiftUI menu bar app.

**The emotion is calm confidence.** Every decision should reinforce it.

## Principles (higher wins)

1. **The glyph says what you hear. The text says why.** Full / low / flat bars = sound state. Status line = cause ("Paused for Zoom"). Never go quiet without a visible reason.
2. **Part of macOS, with depth.** System font and materials. Keep native behaviour (keyboard, VoiceOver, menus, switches, segmented controls). Mauna's own surfaces (Quiet now, the glyph tile, the player card, Settings cards) get light from the top: a subtle accent gradient, a coloured shadow, a bright 0.5pt top edge. Built in `DesignSystem/Components.swift`.
3. **Motion only when it means something.** State, feedback or origin. Frequent actions are instant. Nothing loops.
4. **Handle edge cases invisibly.** Debounce, overrides, short sounds, overlapping rules — correct and unseen.

## Colour

- One accent (dusk indigo). It means "Mauna is acting now", plus the one primary button per view. Accent surfaces use the top-lit gradient (`LinearGradient.accentFill`), never a flat fill. A disabled primary button turns neutral, never pale lavender.
- Trigger badges are quiet at rest (tertiary symbol + word, no pill) and gain an accent pill only while that rule is in charge.
- Neutrals are macOS semantic colours. Never hard-code greys in Swift.
- No green for playing, no red for paused, no colour-coded trigger types. Triggers differ by glyph + word.
- Orange = needs setup. Red = something failed. Nothing else.

## Depth

- Ring + soft shadow, never a solid 1pt border.
- Separators are 0.5pt hairlines inside groups only.
- Translucent surfaces get a bright top edge. Never stack a translucent layer on another.
- Leave the system popover and Settings window material alone.

## Typography

- SwiftUI text styles only (`.headline`, `.body`, `.subheadline`…) so Dynamic Type works.
- Never add `.tracking()` to system text; SF handles tracking per size.
- Hierarchy = weight + size together. No second typeface.
- `.monospacedDigit()` for any number that changes; `.contentTransition(.numericText())` when it does.

## Motion

Decide in this order: **should it animate → why → easing → duration.**

| Moment | Decision |
| --- | --- |
| Quiet shortcut (⌃⌥Space) | No UI animation. State swaps instantly; the audio fade is the feedback. |
| Popover open/close | System default. Don't add anything. |
| Rule pauses/resumes | Glyph morphs on `.spring(response: 0.3, dampingFraction: 1)`; status text crossfades with a 2pt blur, 0.2 s. |
| Active rule row | Tint fades in 0.2 s. |
| Button press | Scale 0.97 on press (not release), 0.16 s ease-out. |
| Onboarding step | Same path forward and back, 0.3 s, stagger 40–80 ms. |
| Menu bar idle | Never animates. No equaliser loop. |

- Easing: ease-out `(0.23, 1, 0.32, 1)` for enter/press; ease-in-out `(0.77, 0, 0.175, 1)` for movement. **Never ease-in.**
- Never animate from scale 0; start at 0.95–0.97 with opacity.
- Exits are faster than entries.
- Springs start from the current value so state changes can interrupt each other without jumps.
- Bounce only after a gesture that carried momentum. Mauna has almost none.
- Reduce Motion: opacity crossfades only.

## Audio (the real animation)

- Fade out 1.2 s, fade in 1.8 s, equal-power curves.
- Every fade starts from the volume playing now; always end at the saved normal volume.
- Debounce 1.5 s; ignore shortcut presses < 300 ms apart; ignore sounds < 3 s.

## Checking the build

- Debug builds render the popover to a PNG: `MAUNA_SNAPSHOT=/path.png` (add `MAUNA_SNAPSHOT_DARK=1` for dark). Compare light and dark with `design-system.html` before handing over.

## Icon

- The wave, 5 bars on an 18pt canvas, drawn in code from the glyph tokens (`WaveGlyph.swift`). States: playing, ducked, paused, off (35% opacity).
- Menu bar: template `NSImage`, swaps instantly. In Mauna's own UI: `WaveGlyphView`, which morphs bar heights on the default spring (crossfade under Reduce Motion).
- Same glyph = same sound. "Quieted by you" and "Lowered for Xcode" share the low-bars glyph.

## Voice

- Short, plain, specific. Name the app, then the next step.
- Sentence case. No exclamation marks, emoji, "Oops", or error codes.
- "Lowered", not "ducked", in status text. Trigger names are always: In front · Using mic or sound · Running.
