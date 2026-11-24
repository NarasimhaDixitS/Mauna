# Mauna build roadmap

How v1 gets built. Product scope comes from [`idea-spec.pdf`](idea-spec.pdf); UI rules come from [`../design/DESIGN.md`](../design/DESIGN.md) and [`../design/tokens.json`](../design/tokens.json).

## How each phase runs

1. Claude writes the Swift code and builds it from the terminal (`xcodebuild`) to catch compile errors.
2. You open `Mauna.xcodeproj` and press **⌘R**. Mauna runs on your own Mac, in the real menu bar. There is no simulator for macOS.
3. You go through the phase's "Try it" list and report anything that feels off.
4. When it's good, commit and push. One commit per phase.

The rule engine is plain Swift with unit tests, so edge cases (debounce, overlapping rules, "never resume what you paused") are tested without playing music.

## v1 phases

| # | Phase | Build | Try it |
|---|---|---|---|
| 0 | Foundation | Xcode project (XcodeGen `project.yml`), no Dock icon (`LSUIElement`), `MenuBarExtra`, `DesignSystem` folder from `tokens.json`, wave glyph drawn in code | Wave icon in the menu bar; click it for an empty popover |
| 1 | Player control | Spotify + Apple Music via AppleScript: is playing, pause, play, get/set volume. Equal-power fade engine. Debug buttons | Click Pause: Spotify fades out over 1.2 s and pauses in place; Play fades back to normal volume |
| 2 | Rule engine | App watcher (`NSWorkspace`), "In front" and "Running" triggers, debounce, active-trigger list, never resume what the user paused, user-pressed-play override, player-quit handling, away mode (screen saver, lock, sleep hold everything), your own pause wins over rules. Rules hard-coded | Switch to Xcode → music pauses; ⌘Tab away → it resumes; quick switches don't flicker |
| 3 | Quiet shortcut | ⌃⌥Space toggle mode (KeyboardShortcuts package), built on the manual hold from Phase 2, "Still paused for Zoom", ignore presses < 300 ms, never start music | Quiet music from any app; a rule can't bring it back |
| 4 | Real UI | Popover per design system (status line, glyph morph, master switch, Quiet now, rules list, quick rule: "Pause / Lower until Safari quits" for the app in front when it has no rule, with "Make it a rule"). Settings window: Rules (app picker, smart default trigger), Sound, General. UserDefaults persistence. Launch at login (`SMAppService`) | Matches the design page; rules survive a restart |
| 5 | YouTube Music + onboarding | YouTube Music in Chrome and Safari via AppleScript JavaScript (checked every 2 s), with a setup guide showing the menu path. 3-step onboarding: player, suggested quiet apps found on this Mac (Calls, Watching, Games ticked), permissions | YouTube Music pauses too; fresh install walks through setup |
| 6 | Ship | Free/Pro gating, trial, license key. Onboarding can add more rules than Free allows: during the trial they all work; after it, rules past the Free limit pause with a clear note, never deleted. App icon. Developer ID signing, hardened runtime, notarization, DMG | An installable `.dmg` ready for Gumroad or Paddle |

## After v1 (from the spec)

- **v1.1:** "Using mic or sound" trigger (Core Audio), duck per rule, snooze, pause on lock, shortcut hold mode, auto-restore.
- **v2:** Companion browser extension, more players (VLC, Deezer, Tidal, SoundCloud), simple schedules.

## Decisions

| Decision | Choice | When |
|---|---|---|
| Project file | XcodeGen `project.yml` (readable, no `.pbxproj` merge pain). Needs `brew install xcodegen` | Phase 0 |
| Minimum macOS | 14.2. The Core Audio calls the mic trigger needs work best from 14.2 | Phase 0 |
| Distribution | Direct, unsandboxed, notarized DMG first. App Store later, if at all | Phase 1 |
| Master switch placement | In the header, like Wi-Fi in Control Center. Quiet now is the one prominent button. Off means rules rest; Quiet now still works | Phase 4 |
| Live volume row | Kept, as text only (player icon, name, "70%" or "Silent"). It shows the fade happening. The slider lives in Settings › Sound | Phase 4 |
| Two rules at once | The strongest wins (pause beats lower). The status line names it: "Paused for Chess + 1" | Phase 2 |
| What "In front" means | The app you're using (its name in the menu bar), whatever its window size. Split View: only the app you clicked last | Phase 2 |
| Split View sharing a rule | No. macOS has no public way to tell which apps are paired; the quick rule covers it | Phase 2 |
| Away (screen saver, locked, asleep) | Hold everything; nothing resumes or pauses. On return, changes wait a fresh 1.5 s | Phase 2 |
| Your pause vs a rule | Music gets the stronger of the two. A rule ending never undoes your pause; only you do | Phase 2 |

## Changes from the spec

- **Menu bar icon:** the spec's music note with four states is replaced by Concept B, `mauna.wave` (see the design system).
- **Pro at launch:** the Free/Pro table lists the mic trigger, duck, snooze and pause on lock under Pro, but those ship in v1.1. At v1, Pro unlocks unlimited rules, all players including YouTube Music, and custom fade time. The rest joins Pro in v1.1.
