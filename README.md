# Stagepoint

A minimal, native teleprompter for macOS and iPadOS that reads plain markdown.

Drop in any `.md` file with `#` headings for slides and plain paragraphs for the spoken script. Stagepoint scrolls smoothly at a controlled pace, fades distant lines into the background, and keeps the current sentence centered — so your eyes stay on the line you're delivering.

---

## Features

- **Markdown-driven** — every `#` heading starts a new slide; every paragraph becomes one or more sentences (tokenized with Apple's `NaturalLanguage` framework).
- **WPM-paced auto-scroll** — adjustable words-per-minute (60–260) controls how long each sentence stays centered, derived from its real word count.
- **Liquid Glass UI** — native macOS 26 / iPadOS 26 glass surfaces. Three pills at the bottom: play, slide counter, words-per-minute.
- **Reading focus fade** — the current sentence is at full brightness, neighbours dim slightly, far-away lines settle into the periphery. Adjustable falloff and floor in settings.
- **Tap to seek** — click or tap any sentence to jump straight to it. Works on Mac mouse and iPad touch.
- **Scroll-pause-and-resume** — two-finger scroll pauses playback automatically; stops for two seconds resumes from where the cursor sits. Toggleable.
- **Mirror mode** — flips the script horizontally for optical teleprompter rigs (camera shooting through angled glass).
- **Drag-and-drop** — drag a `.md` file from Finder (macOS) or the Files app (iPadOS) onto the window to load it.
- **Per-file resume** — Stagepoint remembers where you stopped reading in each script and picks up from there the next time you open the same file.
- **Recent files** — File → Open Recent (or the folder pill on iPadOS) lists up to ten previously-opened scripts.
- **Pre-roll countdown** — optional 3 → 2 → 1 → Go before playback starts.
- **Tint themes** — Charcoal, Slate, Warm, Cool, Sepia, None.
- **Settings persist** across launches.
- **No network, no analytics, no telemetry.** Stagepoint is entirely offline.

---

## Markdown format

```markdown
# First slide title

This is the first slide of the speech. Each sentence becomes its own
addressable line that the teleprompter highlights one at a time. Word
counts drive the pacing.

You can have any number of paragraphs in a slide.

## A subheading

Subheadings under a slide are styled differently but don't advance the
slide cursor. Only top-level `#` headings start a new slide.

# Second slide

The next major section starts a new slide. Stagepoint always keeps
the slide cursor and the sentence cursor independent.
```

The bundled **"Try the sample script"** button on the empty-state screen loads a demo that exercises every feature — good way to see how things should look.

---

## Keyboard shortcuts (macOS)

| Shortcut | Action |
|---|---|
| `⌘O` | Open script |
| `Space` | Play / pause |
| `→` / `←` | Next / previous sentence |
| `⇧→` / `⇧←` | Next / previous slide |
| `↑` | Restart current slide |
| `Esc` | Exit fullscreen, otherwise stop playback |
| `⌘+` / `⌘-` | Increase / decrease font size |
| `M` | Toggle mirror mode |
| `⌘,` | Open settings |
| `Globe + F` (or `fn + F`) | Toggle fullscreen |

On iPadOS the same shortcuts work via a connected hardware keyboard. Without a keyboard, all actions are available through the on-screen toolbar pills and the top-right open-file button.

---

## Platform requirements

- **macOS 26** (Tahoe) or later
- **iPadOS 26** or later
- iPad-only on iOS — iPhone form factor is not supported

---

## Installation

Stagepoint is distributed through the App Store.

- **Mac App Store**: [coming soon]
- **iPad App Store**: [coming soon]

For developers building from source: open `Stagepoint.xcodeproj` in Xcode 26+, set the team in Signing & Capabilities to your own, and run.

---

## Support

- **Email**: jashaswimalyaacharjee@gmail.com
- **Bug reports & feature requests**: open an [issue on this repo](https://github.com/jash-maester/Stagepoint/issues).

---

## Privacy

Stagepoint does **not** collect, transmit, or store any user data on remote servers. There is no analytics, no telemetry, no tracking, no account system, no network activity at all.

All of the following live entirely on your device, in the app's sandboxed container, governed by Apple's standard `UserDefaults` and security-scoped bookmark mechanisms:

- Scripts you've opened (read-only access; the app never modifies them).
- Recent files list.
- Per-file cursor positions (slide and sentence).
- Settings (font size, WPM, theme, fade params, toggles).

Uninstalling the app removes all of this data.

If you have privacy questions, email jashaswimalyaacharjee@gmail.com.

Last updated: May 2026.

---

## Tech notes

For the curious — Stagepoint is built with:

- **Swift 6** (strict concurrency, `@MainActor`, `@Observable`)
- **SwiftUI** for content, AppKit for the macOS window panel
- **swift-markdown** ([swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown)) for parsing
- **NaturalLanguage** framework for sentence tokenization
- **macOS 26 Liquid Glass** APIs (`glassEffect`, `GlassEffectContainer`) for the UI surfaces

Single multi-platform Xcode target. Mac-specific code (`NSPanel`, `NSEvent` scroll monitor, AppKit window controller) is conditionalized with `#if os(macOS)`; iPadOS uses a SwiftUI `WindowGroup`. Common service layer (engine, parsing, persistence, file watcher) is platform-agnostic Swift.

---

© 2026 Jashaswimalya Acharjee. All rights reserved.
