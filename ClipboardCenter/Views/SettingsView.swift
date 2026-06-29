import SwiftUI
import Carbon.HIToolbox

// MARK: - SettingsView
// A full settings panel matching the Clipboard Center design spec:
//   • APPEARANCE — Theme picker (Device/Dark/Light), Language selector
//   • BEHAVIOR — Show selected item first, Start up with system
//   • INTERFACE — Icon mode (Menu bar / Dock)
//   • KEYBOARD — Keyboard shortcut display + Change button
//   • Stats cards — Memory usage & Total items clipped
//
// Design follows DESIGN.md: dark surface, rounded cards, Inter typography,
// macOS-native segmented controls, and the corporate/modern aesthetic.

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let dismissAction: (() -> Void)?

    @State private var statsTimer: Timer?
    @State private var showInfoPopup = false
    @State private var keyEventMonitor: Any?

    /// Reactive localization — re-computes when viewModel.language changes
    private var l: L10n { L10n(viewModel.language) }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Title Bar
            titleBar

            Divider()
                .background(Color(nsColor: .separatorColor))

            // MARK: - Settings Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    behaviorSection
                    interfaceSection
                    keyboardSection
                    debugSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 360, height: 480)
        .background {
            if viewModel.enableBlur {
                VisualEffectBlur()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: viewModel.iconMode == .dock ? 16 : 0))
        .ignoresSafeArea()
        .onAppear {
            viewModel.refreshStats()
            // Refresh stats every 5 seconds while visible
            statsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                DispatchQueue.main.async {
                    viewModel.refreshStats()
                }
            }
        }
        .onDisappear {
            statsTimer?.invalidate()
            statsTimer = nil
        }
        .alert(l.appName, isPresented: $showInfoPopup) {
            Button(l.done, role: .cancel) {}
        } message: {
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")\n\(l.authors)")
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            if viewModel.iconMode == .dock {
                Spacer()
                    .frame(width: 0)
            }

            // Back button
            Button(action: {
                dismissAction?()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l.backToClipboard)

            Spacer()

            Text(l.settingTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Info & Power icons
            HStack(spacing: 12) {
                Button(action: {
                    showInfoPopup = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l.aboutApp)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(l.quitApp)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, viewModel.iconMode == .dock ? 20 : 10)
        .padding(.bottom, 10)
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(l.appearance)

            settingsCard {
                VStack(spacing: 0) {
                    // Theme row
                    settingsRow(icon: "moon.stars.fill", iconColor: .purple, label: l.themes) {
                        themePicker
                    }

                    Divider()
                        .padding(.leading, 40)

                    // Language row
                    settingsRow(icon: "globe", iconColor: .blue, label: l.languageLabel) {
                        languagePicker
                    }

                    Divider()
                        .padding(.leading, 40)

                    // Blur row
                    settingsRow(icon: "drop.fill", iconColor: .cyan, label: l.blur) {
                        Toggle("", isOn: $viewModel.enableBlur)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(l.behavior)

            settingsCard {
                VStack(spacing: 0) {
                    // Show selected item first
                    settingsRow(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        iconColor: .blue,
                        label: l.showSelectedItemFirst
                    ) {
                        Toggle("", isOn: $viewModel.showSelectedItemFirst)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    Divider()
                        .padding(.leading, 40)

                    // Start up with system
                    settingsRow(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        label: l.startUpWithSystem
                    ) {
                        Toggle("", isOn: $viewModel.startUpWithSystem)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Interface Section

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(l.interfaceLabel)

            settingsCard {
                settingsRow(icon: "square.grid.3x3.fill", iconColor: .indigo, label: l.iconMode) {
                    iconModePicker
                }
            }
        }
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(l.keyboard)

            settingsCard {
                if viewModel.isRecordingShortcut {
                    // Recording mode
                    HStack(spacing: 10) {
                        Image(systemName: "command.square.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.teal)
                            .frame(width: 24)

                        Text(l.pressShortcut)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.orange)
                            .opacity(0.8)

                        Spacer()

                        Button(l.cancel) {
                            stopRecording()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .onAppear {
                        startRecording()
                    }
                    .onDisappear {
                        stopRecording()
                    }
                } else {
                    // Normal display mode
                    HStack(spacing: 10) {
                        Image(systemName: "command.square.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.teal)
                            .frame(width: 24)

                        Text(l.keyboardShortcut)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        // Shortcut badge
                        Text(viewModel.keyboardShortcut)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )

                        // Change button
                        Button(l.change) {
                            viewModel.isRecordingShortcut = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Shortcut Recording

    /// Installs a local key event monitor to capture the next key combo.
    private func startRecording() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode

            // Esc cancels recording
            if keyCode == 53 { // kVK_Escape
                stopRecording()
                return nil // Consume the event
            }

            // Convert Cocoa modifier flags to Carbon modifier flags
            let cocoaFlags = event.modifierFlags
            var carbonMods: UInt32 = 0
            if cocoaFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if cocoaFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if cocoaFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if cocoaFlags.contains(.control) { carbonMods |= UInt32(controlKey) }

            // Require at least one modifier (Cmd, Ctrl, or Option) for a valid shortcut
            let hasRequiredModifier = cocoaFlags.contains(.command)
                || cocoaFlags.contains(.control)
                || cocoaFlags.contains(.option)

            if hasRequiredModifier {
                viewModel.applyNewShortcut(keyCode: UInt32(keyCode), modifiers: carbonMods)
                removeKeyMonitor()
            }

            return nil // Consume the event
        }
    }

    /// Stops recording and removes the key event monitor.
    private func stopRecording() {
        viewModel.cancelRecording()
        removeKeyMonitor()
    }

    /// Removes the key event monitor if installed.
    private func removeKeyMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Debug header with toggle
            HStack {
                sectionHeader(l.debug)
                Spacer()
                Toggle("", isOn: $viewModel.showDebugStats)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            if viewModel.showDebugStats {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        // Memory usage card
                        statsCard(
                            icon: "memorychip.fill",
                            iconColor: .blue,
                            value: viewModel.currentMemoryUsage,
                            label: l.memoryFootprint,
                            badge: l.optimized,
                            badgeColor: .green,
                            cardColor: Color.blue.opacity(0.12)
                        )

                        // Total items clipped card
                        statsCard(
                            icon: "doc.on.clipboard.fill",
                            iconColor: .indigo,
                            value: "\(viewModel.totalItemsClipped)",
                            label: l.totalItemsClipped,
                            badge: nil,
                            badgeColor: .clear,
                            cardColor: Color.indigo.opacity(0.12)
                        )
                    }

                    // Thread count card (full width)
                    statsCard(
                        icon: "cpu.fill",
                        iconColor: .orange,
                        value: "\(viewModel.activeThreadCount)",
                        label: l.activeThreads,
                        badge: nil,
                        badgeColor: .clear,
                        cardColor: Color.orange.opacity(0.12)
                    )

                    Button(action: {
                        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        NSApp.terminate(nil)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 14))
                            Text("Restart App")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .systemRed).opacity(0.85))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }


    // MARK: - Reusable Components

    /// Section header label (e.g. "APPEARANCE", "BEHAVIOR")
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.leading, 4)
    }

    /// A rounded card container for grouping related settings rows
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// A single settings row with icon, label, and a trailing control
    private func settingsRow<Control: View>(
        icon: String,
        iconColor: Color,
        label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Stats info card with icon, value, label, and optional badge
    private func statsCard(
        icon: String,
        iconColor: Color,
        value: String,
        label: String,
        badge: String?,
        badgeColor: Color,
        cardColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .tracking(0.5)
                }
            }

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardColor)
        )
    }

    // MARK: - Custom Pickers

    /// Segmented-style theme picker: Device | Dark | Light
    private var themePicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsViewModel.ThemeMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.themeMode = mode
                    }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: viewModel.themeMode == mode ? .semibold : .regular))
                        .foregroundStyle(viewModel.themeMode == mode ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Group {
                                if viewModel.themeMode == mode {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// Language dropdown chip
    private var languagePicker: some View {
        Menu {
            ForEach(SettingsViewModel.Language.allCases, id: \.self) { lang in
                Button(lang.rawValue) {
                    viewModel.language = lang
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.language.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Icon mode segmented picker: Menu bar | Dock
    private var iconModePicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsViewModel.IconMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.iconMode = mode
                    }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: viewModel.iconMode == mode ? .semibold : .regular))
                        .foregroundStyle(viewModel.iconMode == mode ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Group {
                                if viewModel.iconMode == mode {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Primary Button Style

/// A compact primary-colored button for actions like "Change"
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlAccentColor))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
