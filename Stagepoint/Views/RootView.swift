//
//  RootView.swift
//  Simple Teleprompter
//
//  Created by Jashaswimalya Acharjee on 30/05/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Top-level SwiftUI view hosted inside the teleprompter panel.
///
/// Layers, back to front:
/// 1. ``WindowAccessor`` – invisible AppKit bridge publishing window state.
/// 2. ``GlassBackground`` – Liquid Glass (or black, when fullscreen) with tint.
/// 3. Script reader (``ScriptScrollView``) *or* the empty-state prompt.
/// 4. ``MouseTracker`` – invisible AppKit bridge for movement-driven pause.
/// 5. Drop-target highlight border, when relevant.
///
/// File loading routes through two paths:
/// 1. `.dropDestination` — file dragged from Finder.
/// 2. `.fileImporter` — opened from the empty-state button or ⌘O menu,
///    triggered by flipping `appEnv.pickerRequested` to `true`.
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var isDropTargeted = false

    private static let mdType: UTType = UTType(filenameExtension: "md") ?? .plainText

    var body: some View {
        @Bindable var bindable = appEnv

        ZStack {
            #if os(macOS)
            WindowAccessor()
                .allowsHitTesting(false)
            #endif
            GlassBackground()

            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ToolbarView()
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                }

            #if os(macOS)
            MouseTracker(environment: appEnv)
                .allowsHitTesting(false)
            #endif

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }

            if appEnv.preRollActive {
                PreRollOverlay(countdown: appEnv.preRollCountdown) {
                    AppDelegate.shared?.cancelPreRoll()
                }
                .transition(.opacity)
            }
        }
        #if !os(macOS)
        // macOS already has File → Open Script (⌘O), Open Recent submenu,
        // and drag-and-drop. The on-screen pill would be redundant chrome
        // there. iPadOS has no menu bar without a hardware keyboard, so
        // the pill is essential.
        .overlay(alignment: .topTrailing) {
            if appEnv.engine.script != nil {
                OpenScriptPill()
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        #endif
        .onChange(of: appEnv.engine.currentSentenceIndex) { _, _ in
            AppDelegate.shared?.savePositionForCurrentScript()
        }
        .onChange(of: appEnv.engine.currentSlideIndex) { _, _ in
            AppDelegate.shared?.savePositionForCurrentScript()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            AppDelegate.shared?.loadScript(from: url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .fileImporter(
            isPresented: $bindable.pickerRequested,
            allowedContentTypes: [Self.mdType, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                AppDelegate.shared?.loadScript(from: url)
            case .failure:
                break
            }
        }
        .sheet(isPresented: $bindable.showSettings) {
            SettingsSheet()
                .environment(appEnv)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let script = appEnv.engine.script {
            ScriptScrollView(script: script)
                .contentShape(.rect)
                .onTapGesture {
                    AppDelegate.shared?.playPause()
                }
        } else {
            EmptyStatePrompt()
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
    }
}

private struct EmptyStatePrompt: View {
    var body: some View {
        VStack(spacing: 14) {
            Button {
                AppDelegate.shared?.openScriptPicker()
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48, weight: .light))
                    Text("Open Script")
                        .font(.title2)
                    Text("or drop a .md file here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Text("⌘O")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))

            Button {
                AppDelegate.shared?.loadSampleScript()
            } label: {
                Text("Try the sample script")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Discoverable "open another script" affordance shown at top-right when
/// a script is already loaded. Especially important on iPadOS where
/// there's no menu bar — ⌘O via external keyboard is not available to
/// touch-only users. On macOS this complements the File → Open Script
/// menu item.
private struct OpenScriptPill: View {
    var body: some View {
        Button {
            AppDelegate.shared?.openScriptPicker()
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .help("Open Script")
    }
}
