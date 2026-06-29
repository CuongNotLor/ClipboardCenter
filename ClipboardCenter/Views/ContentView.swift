import SwiftUI
import AppKit

// MARK: - VisualEffectBlur
// NSViewRepresentable wrapper for NSVisualEffectView to provide native macOS
// window blur (vibrancy). Uses .hudWindow material for a subtle translucent effect.

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - ContentView
// The main view displayed inside the NSPopover.
// Layout: Search bar → Clear All → Pinned section → History section
// Uses a compact, sleek design optimized for a 360×480pt popover.
//
// Uses @ObservedObject for macOS 13 compatibility (@Bindable requires macOS 14+).

struct ContentView: View {
    @ObservedObject var viewModel: ClipboardCenterViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    let dismissAction: () -> Void

    @State private var showClearAllConfirmation = false
    @State private var editingItem: ClipboardItemEntity? = nil
    @State private var editingText: String = ""

    /// Reactive localization — re-computes when settingsViewModel.language changes
    private var l: L10n { L10n(settingsViewModel.language) }

    var body: some View {
        ZStack {
            Group {
                if settingsViewModel.isShowingSettings {
                    SettingsView(viewModel: settingsViewModel) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settingsViewModel.isShowingSettings = false
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        // MARK: - Header
                        headerView

                        Divider()
                            .background(Color(nsColor: .separatorColor))

                        // MARK: - Content
                        if viewModel.filteredItems.isEmpty {
                            emptyStateView
                        } else {
                            clipboardList
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            // MARK: - Edit Overlay
            if editingItem != nil {
                editOverlayView
            }

            // MARK: - Warning Alert Overlay
            if viewModel.showWarningAlert {
                warningAlertView
            }

            // MARK: - Clear All Confirmation Overlay
            if showClearAllConfirmation {
                clearAllConfirmationView
            }
        }
        .frame(width: 360, height: 480)
        .background {
            if settingsViewModel.enableBlur {
                VisualEffectBlur()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: settingsViewModel.iconMode == .dock ? 16 : 0))
        .ignoresSafeArea()
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            // App title row with Clear All button
            HStack {
                if settingsViewModel.iconMode == .dock {
                    Spacer()
                        .frame(width: 0)
                }

                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(l.clipboardCenter)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Settings gear button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settingsViewModel.isShowingSettings = true
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l.settings)

                // Item count badge
                if !viewModel.items.isEmpty {
                    Text("\(viewModel.items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        )
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showClearAllConfirmation = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text(l.clear)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(l.clearAllUnpinnedItems)
            }
            .padding(.horizontal, 14)
            .padding(.top, settingsViewModel.iconMode == .dock ? 20 : 12)

            // Search bar
            SearchBar(text: $viewModel.searchText, placeholder: l.searchPlaceholder)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // Content Type Filter
            Picker("", selection: $viewModel.selectedFilter) {
                ForEach(ClipboardCenterViewModel.ContentFilter.allCases, id: \.self) { filter in
                    Text(localizedFilterName(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Clipboard List

    private var clipboardList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // Pinned items section
                if !viewModel.pinnedItems.isEmpty {
                    sectionHeader(title: l.pinned, icon: "pin.fill", count: viewModel.pinnedItems.count)

                    ForEach(viewModel.pinnedItems, id: \.objectID) { item in
                        ClipboardItemRow(
                            item: item,
                            onTap: {
                                viewModel.copyToClipboard(item)
                                dismissAction()
                            },
                            onPin: { viewModel.togglePin(item) },
                            onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    viewModel.delete(item)
                                }
                            },
                            onEdit: {
                                editingText = item.textContent ?? ""
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    editingItem = item
                                }
                            }
                        )
                    }

                    if !viewModel.unpinnedItems.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                    }
                }

                // History section
                if !viewModel.unpinnedItems.isEmpty {
                    sectionHeader(title: l.history, icon: "clock", count: viewModel.unpinnedItems.count)

                    ForEach(viewModel.unpinnedItems, id: \.objectID) { item in
                        ClipboardItemRow(
                            item: item,
                            onTap: {
                                viewModel.copyToClipboard(item)
                                dismissAction()
                            },
                            onPin: { viewModel.togglePin(item) },
                            onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    viewModel.delete(item)
                                }
                            },
                            onEdit: {
                                editingText = item.textContent ?? ""
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    editingItem = item
                                }
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text("(\(count))")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: viewModel.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)

            Text(viewModel.searchText.isEmpty ? l.noClipboardHistory : l.noResultsFound)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(viewModel.searchText.isEmpty
                 ? l.copiedItemsWillAppear
                 : l.tryDifferentSearch)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Localized Filter Names

    private func localizedFilterName(_ filter: ClipboardCenterViewModel.ContentFilter) -> String {
        switch filter {
        case .all: return l.filterAll
        case .text: return l.filterText
        case .image: return l.filterImage
        case .file: return l.filterFile
        }
    }

    // MARK: - Edit Overlay View
    private var editOverlayView: some View {
        ZStack {
            // Darkened background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        editingItem = nil
                    }
                }

            // Edit card container
            VStack(alignment: .leading, spacing: 12) {
                Text(l.editTextTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                TextEditor(text: $editingText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .frame(height: 180)

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            editingItem = nil
                        }
                    }) {
                        Text(l.cancel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: {
                        if let item = editingItem {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.updateText(item, newText: editingText)
                                editingItem = nil
                            }
                        }
                    }) {
                        Text(l.save)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlAccentColor))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .zIndex(100)
    }

    // MARK: - Warning Alert View
    private var warningAlertView: some View {
        ZStack {
            // Darkened background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.showWarningAlert = false
                    }
                }

            // Alert card container
            VStack(spacing: 16) {
                // Warning Icon
                Image("sticker")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                
                VStack(spacing: 6) {
                    Text("Warning")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Your clipboard has over 100 items, the oldest item will be remove!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.showWarningAlert = false
                        }
                    }) {
                        Text("OK")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlAccentColor))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .zIndex(101)
    }

    // MARK: - Clear All Confirmation View
    private var clearAllConfirmationView: some View {
        ZStack {
            // Darkened background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showClearAllConfirmation = false
                    }
                }

            // Alert card container
            VStack(spacing: 16) {
                // Warning Icon
                Image("ask")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                
                VStack(spacing: 6) {
                    Text(l.clearClipboardHistory)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(l.clearAllMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showClearAllConfirmation = false
                        }
                    }) {
                        Text(l.cancel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showClearAllConfirmation = false
                        }
                        viewModel.clearAll()
                    }) {
                        Text(l.clearAll)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .zIndex(102)
    }
}
