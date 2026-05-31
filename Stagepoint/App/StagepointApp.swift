//
//  StagepointApp.swift
//  Stagepoint
//
//  Created by Jashaswimalya Acharjee on 30/05/26.
//

#if os(macOS)
import AppKit
#endif

import Observation
import OSLog
import SwiftUI

@main
struct StagepointApp: App {
    #if os(macOS)
    // On macOS the AppDelegate owns the AppKit `NSPanel` and reacts to
    // standard `NSApplicationDelegate` lifecycle events. SwiftUI's
    // adapter creates and retains the instance.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    // On iPadOS there's no NSApplicationDelegate; we just instantiate
    // the same class directly and hold a SwiftUI-owned reference. The
    // `AppDelegate.shared` static is still set in `init()` so views
    // can reach the action methods exactly as on macOS.
    @State private var appDelegate = AppDelegate()
    #endif

    var body: some Scene {
        mainScene
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Open Script…") {
                        AppDelegate.shared?.openScriptPicker()
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    OpenRecentMenu()
                }

                CommandMenu("Playback") {
                    Button("Play / Pause") { AppDelegate.shared?.playPause() }
                        .keyboardShortcut(.space, modifiers: [])
                    Button("Stop") { AppDelegate.shared?.stopPlayback() }
                        .keyboardShortcut(.escape, modifiers: [])
                    Divider()
                    Button("Next Sentence") { AppDelegate.shared?.nextSentence() }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Previous Sentence") { AppDelegate.shared?.previousSentence() }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Divider()
                    Button("Next Slide") { AppDelegate.shared?.nextSlide() }
                        .keyboardShortcut(.rightArrow, modifiers: .shift)
                    Button("Previous Slide") { AppDelegate.shared?.previousSlide() }
                        .keyboardShortcut(.leftArrow, modifiers: .shift)
                    Button("Restart Slide") { AppDelegate.shared?.restartCurrentSlide() }
                        .keyboardShortcut(.upArrow, modifiers: [])
                }

                CommandMenu("Format") {
                    Button("Larger Font") { AppDelegate.shared?.bumpFontSize(by: 2) }
                        .keyboardShortcut("+", modifiers: .command)
                    Button("Smaller Font") { AppDelegate.shared?.bumpFontSize(by: -2) }
                        .keyboardShortcut("-", modifiers: .command)
                    Divider()
                    Button("Toggle Mirror") { AppDelegate.shared?.toggleMirror() }
                        .keyboardShortcut("m", modifiers: [])
                }

                // Replace the system-default "Settings…" item so ⌘, opens
                // our in-window sheet instead of the empty `Settings { … }`
                // placeholder scene (macOS) or so iPad's external-keyboard
                // shortcut still surfaces the sheet.
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        AppDelegate.shared?.toggleSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }

    @SceneBuilder
    private var mainScene: some Scene {
        #if os(macOS)
        // macOS: the real UI is hosted in an AppKit `NSPanel` (created
        // by `AppDelegate.applicationDidFinishLaunching`). SwiftUI just
        // needs *some* scene to register the command menu; this hidden
        // Settings placeholder is the cheapest option.
        Settings { EmptyView() }
        #else
        // iPadOS: a normal `WindowGroup` hosting `RootView` directly,
        // wired up to the same `AppEnvironment` the AppDelegate created.
        WindowGroup {
            RootView()
                .environment(appDelegate.environment)
        }
        #endif
    }
}

/// App-wide action surface and (on macOS) `NSApplicationDelegate`.
///
/// One class, two platforms. The cross-platform parts — `environment`,
/// the action methods called from `CommandMenu` buttons and views, the
/// file watcher and pre-roll machinery — live in the body of the class.
/// Everything macOS-specific (the `NSPanel` window controller, NSEvent
/// scroll monitor, fullscreen handling, app-lifecycle delegate methods)
/// is guarded by `#if os(macOS)`.
@MainActor
final class AppDelegate: NSObject {
    /// Canonical reference to the live instance. On macOS the SwiftUI
    /// `@NSApplicationDelegateAdaptor` wraps our delegate in its own
    /// internal type, so `NSApp.delegate as? AppDelegate` returns nil;
    /// views must use `AppDelegate.shared` instead.
    static private(set) var shared: AppDelegate?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SimpleTeleprompter",
        category: "AppDelegate"
    )

    /// Exposed so the App-scope `commands { ... }` block can build the
    /// Open Recent submenu off `environment.recentStore`.
    let environment = AppEnvironment()

    private var fileWatcher: FileWatcher?
    private var preRollTask: Task<Void, Never>?

    #if os(macOS)
    private var windowController: TeleprompterWindowController?
    private var scrollMonitor: Any?
    private var scrollResumeTask: Task<Void, Never>?
    private static let scrollResumeDelay: Duration = .seconds(2)
    #endif

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - Cross-platform action surface
    //
    // SwiftUI `CommandMenu` buttons (and our SwiftUI views) need targets
    // accessible from the App struct. These methods are the user-facing
    // verbs the UI binds to.

    /// Asks ``RootView`` to present its SwiftUI `.fileImporter`.
    func openScriptPicker() {
        ensureWindowVisible()
        environment.pickerRequested = true
    }

    func playPause() {
        // If a pre-roll countdown is already showing, treat the user's
        // play/pause action as a cancel — return to paused state.
        if environment.preRollActive {
            cancelPreRoll()
            return
        }
        if environment.engine.isPlaying {
            environment.engine.pause(reason: .user)
        } else if environment.preRollEnabled {
            startPreRoll()
        } else {
            environment.engine.play()
        }
    }

    func stopPlayback() {
        cancelPreRoll()
        environment.engine.stop()
    }
    func nextSentence() { environment.engine.nextSentence() }
    func previousSentence() { environment.engine.previousSentence() }
    func nextSlide() { environment.engine.nextSlide() }
    func previousSlide() { environment.engine.previousSlide() }
    func restartCurrentSlide() { environment.engine.restartCurrentSlide() }
    func bumpFontSize(by delta: Double) {
        environment.fontSize = min(72, max(16, environment.fontSize + delta))
    }
    func toggleMirror() { environment.isMirrored.toggle() }
    func toggleSettings() { environment.showSettings.toggle() }

    /// Begins a 3 → 2 → 1 → Go visual countdown, then asks the engine
    /// to play. Cancellable via ``cancelPreRoll()``, a click on the
    /// overlay, or pressing Space again.
    private func startPreRoll() {
        preRollTask?.cancel()
        environment.preRollCountdown = 3
        environment.preRollActive = true
        preRollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for n in stride(from: 3, through: 1, by: -1) {
                self.environment.preRollCountdown = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    self.environment.preRollActive = false
                    return
                }
            }
            self.environment.preRollCountdown = 0  // "Go"
            try? await Task.sleep(for: .milliseconds(350))
            self.environment.preRollActive = false
            self.preRollTask = nil
            guard !Task.isCancelled else { return }
            self.environment.engine.play()
        }
    }

    func cancelPreRoll() {
        preRollTask?.cancel()
        preRollTask = nil
        environment.preRollActive = false
    }

    /// Loads a script from any URL — picker, drag-and-drop, or recent files.
    ///
    /// Synchronous on purpose: when called from a `.fileImporter` completion,
    /// the URL's security scope is only valid until the completion returns,
    /// so the read must complete before we yield.
    func loadScript(from url: URL) {
        ensureWindowVisible()
        cancelPreRoll()
        // Persist the previous file's cursor before switching to a new one.
        savePositionForCurrentScript()

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else {
                Self.logger.error("UTF-8 decode failed for \(url.lastPathComponent, privacy: .public)")
                return
            }
            let slides = MarkdownParser().parse(source)
            let script = Script(slides: slides, sourceURL: url)
            environment.engine.setScript(script)
            // Capture the bookmark while we still hold the security scope.
            environment.recentStore.add(url)

            if environment.resumeEnabled,
               let pos = environment.positionStore.load(for: url) {
                restoreCursor(slideIndex: pos.slideIndex,
                              sentenceIndex: pos.sentenceIndex,
                              in: script)
            }

            installFileWatcher(for: url)
            Self.logger.info("Loaded \(slides.count, privacy: .public) slide(s) from \(url.lastPathComponent, privacy: .public)")
        } catch {
            Self.logger.error("Load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Re-reads the currently loaded file from disk and preserves the
    /// slide cursor (clamped to the new slide count). Used by the file
    /// watcher when an external editor saves changes.
    private func reloadCurrentScript() {
        guard let url = environment.engine.script?.sourceURL else { return }
        let wasPlaying = environment.engine.isPlaying
        let priorSlide = environment.engine.currentSlideIndex

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else { return }
            let slides = MarkdownParser().parse(source)
            let script = Script(slides: slides, sourceURL: url)
            environment.engine.setScript(script)

            let clampedSlide = min(priorSlide, max(0, script.slides.count - 1))
            environment.engine.currentSlideIndex = clampedSlide
            environment.engine.currentSentenceIndex = 0

            if wasPlaying { environment.engine.play() }

            // Re-install the watcher — atomic-save replacements give the
            // file a fresh inode, so the old fd is dead.
            installFileWatcher(for: url)
            Self.logger.info("Reloaded \(slides.count, privacy: .public) slide(s) from disk change")
        } catch {
            Self.logger.error("Reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func installFileWatcher(for url: URL) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher.start(url: url) {
            AppDelegate.shared?.reloadCurrentScript()
        }
    }

    private func restoreCursor(slideIndex: Int, sentenceIndex: Int, in script: Script) {
        guard !script.slides.isEmpty else { return }
        let clampedSlide = min(slideIndex, script.slides.count - 1)
        guard clampedSlide >= 0 else { return }
        let slide = script.slides[clampedSlide]
        let clampedSentence = slide.sentences.isEmpty
            ? 0
            : min(sentenceIndex, slide.sentences.count - 1)
        environment.engine.currentSlideIndex = clampedSlide
        environment.engine.currentSentenceIndex = max(0, clampedSentence)
    }

    /// Saves the engine's current cursor position for the currently
    /// loaded script's URL.
    func savePositionForCurrentScript() {
        guard let url = environment.engine.script?.sourceURL else { return }
        environment.positionStore.save(
            slideIndex: environment.engine.currentSlideIndex,
            sentenceIndex: environment.engine.currentSentenceIndex,
            for: url
        )
    }

    /// Resolves a remembered entry's bookmark and loads the script.
    func loadRecent(_ entry: RecentFilesStore.Entry) {
        guard let url = environment.recentStore.resolve(entry) else {
            Self.logger.notice("Recent entry could not be resolved: \(entry.url.lastPathComponent, privacy: .public)")
            return
        }
        loadScript(from: url)
    }

    /// Loads the bundled `SampleScript.md` so first-time users (and
    /// iPad simulator testing) have something to render without having
    /// to find a markdown file first. Skips the recents list, security
    /// scope, and the file watcher — none apply to a bundle resource.
    func loadSampleScript() {
        ensureWindowVisible()
        guard let url = Bundle.main.url(forResource: "SampleScript", withExtension: "md") else {
            Self.logger.error("SampleScript.md missing from bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else { return }
            let slides = MarkdownParser().parse(source)
            let script = Script(slides: slides, sourceURL: url)
            environment.engine.setScript(script)
            Self.logger.info("Loaded sample script (\(slides.count, privacy: .public) slides)")
        } catch {
            Self.logger.error("Sample load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Brings the teleprompter window forward if it was hidden.
    /// macOS: re-orders the `NSPanel` to the front. iPadOS: no-op
    /// because the SwiftUI `WindowGroup` is always live as long as the
    /// scene exists.
    func ensureWindowVisible() {
        #if os(macOS)
        guard let window = windowController?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }
}

#if os(macOS)
extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Launching Stagepoint")

        NSApp.setActivationPolicy(.regular)

        let controller = TeleprompterWindowController(environment: environment)
        controller.showWindow(nil)
        windowController = controller

        installScrollMonitor()

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Return `false`: our teleprompter window is managed manually by
    /// ``TeleprompterWindowController``, not by SwiftUI's scene system.
    /// SwiftUI's only macOS scene is `Settings { EmptyView() }` which
    /// has no visible window, so returning `true` would quit the app
    /// the moment any modal (e.g. `.fileImporter`) dismissed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock-icon click while no windows are visible: bring our panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ensureWindowVisible()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePositionForCurrentScript()
        fileWatcher?.stop()
    }

    /// Toggles native fullscreen on the teleprompter panel. Bound to
    /// the system's globe+F shortcut via collection-behavior.
    func toggleFullScreen() {
        guard let window = windowController?.window else {
            Self.logger.warning("toggleFullScreen invoked without a window")
            return
        }
        window.toggleFullScreen(nil)
    }

    /// Esc — exit fullscreen if in it, else stop playback.
    func handleEscape() {
        if environment.isFullScreen {
            toggleFullScreen()
        } else if environment.engine.isPlaying {
            environment.engine.stop()
        }
    }

    /// Installs a local NSEvent monitor for `.scrollWheel` events.
    /// Scrolling inside the panel pauses the engine with reason
    /// `.userScroll`; we arm a timer that auto-resumes 2 seconds after
    /// the last scroll event when ``AppEnvironment/autoResumeAfterScroll``
    /// is on. Always returns the event so `NSScrollView` still handles
    /// the scroll natively.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            Task { @MainActor in
                AppDelegate.shared?.handleScrollEvent()
            }
            return event
        }
    }

    private func handleScrollEvent() {
        if environment.engine.isPlaying {
            environment.engine.pause(reason: .userScroll)
        }
        if environment.engine.pauseReason == .userScroll, environment.autoResumeAfterScroll {
            armScrollResumeTimer()
        } else {
            scrollResumeTask?.cancel()
            scrollResumeTask = nil
        }
    }

    private func armScrollResumeTimer() {
        scrollResumeTask?.cancel()
        let env = environment
        scrollResumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.scrollResumeDelay)
            guard let self, !Task.isCancelled else { return }
            guard env.autoResumeAfterScroll,
                  env.engine.pauseReason == .userScroll else { return }
            env.engine.play()
            self.scrollResumeTask = nil
        }
    }
}
#endif

/// Submenu shown under File → Open Recent. Implemented as a View so it
/// can observe ``RecentFilesStore``'s `@Observable` entries list and
/// re-render whenever a new file is added or the menu is cleared.
private struct OpenRecentMenu: View {
    var body: some View {
        Menu("Open Recent") {
            if let store = AppDelegate.shared?.environment.recentStore {
                ForEach(store.entries) { entry in
                    Button(entry.url.lastPathComponent) {
                        AppDelegate.shared?.loadRecent(entry)
                    }
                }
                if !store.entries.isEmpty { Divider() }
                Button("Clear Menu") {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            } else {
                Button("Clear Menu") {}.disabled(true)
            }
        }
    }
}
