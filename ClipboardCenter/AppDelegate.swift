import AppKit
import SwiftUI
import CoreData
import Carbon.HIToolbox

// MARK: - AppDelegate
// Manages the status bar icon, popover, and global hotkey.
// This is the central orchestrator — it creates the CoreData container,
// the clipboard monitor, and wires everything into the popover UI.

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var popover: NSPopover!
    private var viewModel: ClipboardCenterViewModel!
    private var settingsViewModel: SettingsViewModel!
    private var hotKeyManager: HotKeyManager?
    private var window: NSWindow?

    /// CoreData persistent container for clipboard history storage
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "ClipboardCenter")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load CoreData store: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    /// Monitor for click-away dismissal of the popover.
    private var globalClickMonitor: Any?
    /// Monitor for local (in-app) click events to dismiss the popover.
    private var localClickMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1b. Create the Settings ViewModel
        settingsViewModel = SettingsViewModel(viewContext: persistentContainer.viewContext)

        // 1. Create the ViewModel with the CoreData view context and settings reference
        viewModel = ClipboardCenterViewModel(viewContext: persistentContainer.viewContext, settingsViewModel: settingsViewModel)

        // 3. Build the popover
        setupPopover()

        // 4. Register global hotkey (Cmd + Shift + V)
        setupHotKey()

        // Setup the icon mode callback
        setupIconModeCallback()

        // Apply initial icon mode settings
        applyIconMode(settingsViewModel.iconMode)

        // 5. Start clipboard monitoring
        viewModel.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
        hotKeyManager?.unregister()
        removeClickMonitors()
    }

    // MARK: - Status Bar Setup

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }

        // Load the custom SVG-based icon as a template image for proper
        // light/dark mode rendering in the menu bar.
        if let iconImage = loadMenuBarIcon() {
            iconImage.isTemplate = true // Allows macOS to color it appropriately
            button.image = iconImage
        } else {
            // Fallback to SF Symbol if custom icon fails to load
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Center")
        }

        button.action = #selector(statusBarClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Loads the custom clipboard.svg and renders it as a properly-sized NSImage
    /// suitable for the menu bar (18×18 pt).
    private func loadMenuBarIcon() -> NSImage? {
        // Look for the SVG in the app bundle first, then fall back to the project root
        let bundlePath = Bundle.main.path(forResource: "clipboard", ofType: "svg")
        let projectPath = Bundle.main.bundlePath
            .components(separatedBy: "/ClipboardCenter.app")
            .first
            .map { $0 + "Asset/clipboard.svg" }

        guard let svgPath = bundlePath ?? projectPath,
              FileManager.default.fileExists(atPath: svgPath),
              let svgImage = NSImage(contentsOfFile: svgPath) else {
            return nil
        }

        // Render at 18×18 pt for crisp menu bar display
        let targetSize = NSSize(width: 18, height: 18)
        let resizedImage = NSImage(size: targetSize, flipped: false) { rect in
            svgImage.draw(in: rect)
            return true
        }

        return resizedImage
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        popover = NSPopover()
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient // Auto-close on click-away
        popover.animates = true

        // Wrap the SwiftUI ContentView with the environment dependencies
        let contentView = ContentView(
            viewModel: viewModel,
            settingsViewModel: settingsViewModel
        ) {
            // Closure to close the popover when an item is clicked
            self.closePopover()
        }

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Popover Toggle

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(sender)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let l = L10n(settingsViewModel.language)

        let settingItem = NSMenuItem(title: l.settingTitle, action: #selector(menuShowSettings), keyEquivalent: ",")
        settingItem.target = self
        menu.addItem(settingItem)

        menu.addItem(NSMenuItem.separator())

        let exitItem = NSMenuItem(title: l.exit, action: #selector(menuExit), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func menuShowSettings() {
        if popover.isShown && settingsViewModel.isShowingSettings {
            closePopover()
        } else {
            showSettings()
        }
    }

    private func showSettings() {
        guard let item = statusItem, let button = item.button else { return }

        viewModel.refreshItems()
        settingsViewModel.isShowingSettings = true

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installClickMonitors()
    }

    @objc private func menuExit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func togglePopover() {
        if settingsViewModel.iconMode == .dock {
            toggleWindow()
        } else {
            if popover.isShown {
                closePopover()
            } else {
                showPopover()
            }
        }
    }

    private func toggleWindow() {
        if let window = window, window.isVisible {
            window.orderOut(nil)
            updateUIVisibility()
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        if window == nil {
            let contentView = ContentView(
                viewModel: viewModel,
                settingsViewModel: settingsViewModel
            ) { [weak self] in
                self?.window?.orderOut(nil)
                self?.updateUIVisibility()
            }

            let newWindow = SleekWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Clipboard Center"
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.isMovableByWindowBackground = true
            newWindow.contentViewController = NSHostingController(rootView: contentView)

            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = true

            newWindow.delegate = self
            
            // Set default window position to bottom-right of screen
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let padding: CGFloat = 20
                let x = visibleFrame.origin.x + visibleFrame.size.width - 360 - padding
                let y = visibleFrame.origin.y + padding
                newWindow.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                newWindow.center()
            }
            
            self.window = newWindow
        }

        viewModel.refreshItems()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateUIVisibility()
    }

    private func setupIconModeCallback() {
        settingsViewModel.onIconModeChanged = { [weak self] mode in
            DispatchQueue.main.async {
                self?.applyIconMode(mode)
            }
        }
    }

    private func applyIconMode(_ mode: SettingsViewModel.IconMode) {
        if mode == .dock {
            if statusItem != nil {
                NSStatusBar.system.removeStatusItem(statusItem!)
                statusItem = nil
            }
            closePopover()
            NSApp.setActivationPolicy(.regular)
            showWindow()
        } else {
            window?.orderOut(nil)
            window = nil
            NSApp.setActivationPolicy(.accessory)
            if statusItem == nil {
                setupStatusBar()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsViewModel.iconMode == .dock {
            showWindow()
            return true
        }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func showPopover() {
        guard let item = statusItem, let button = item.button else { return }

        // Refresh the view model data before showing
        viewModel.refreshItems()
        
        // Always show clipboard screen when opening the popover
        settingsViewModel.isShowingSettings = false

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Install click-away monitors for dismissal
        installClickMonitors()
        updateUIVisibility()
    }

    private func closePopover() {
        popover.performClose(nil)
        updateUIVisibility()
    }

    // MARK: - Click-Away Monitors
    // These monitors detect clicks outside the popover and dismiss it.
    // The .transient behavior handles most cases, but these are belt-and-suspenders.

    private func installClickMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            // Only close if the click is outside the popover
            if let self = self, self.popover.isShown {
                // Let the event pass through — transient behavior handles dismissal
            }
            return event
        }
    }

    private func removeClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    // MARK: - Global HotKey

    private func setupHotKey() {
        hotKeyManager = HotKeyManager()
        registerCurrentHotkey()

        // Re-register when user changes the shortcut in settings
        settingsViewModel.onHotkeyChanged = { [weak self] keyCode, modifiers in
            self?.hotKeyManager?.unregister()
            self?.registerCurrentHotkey()
        }
    }

    /// Registers the hotkey using current values from settingsViewModel.
    private func registerCurrentHotkey() {
        hotKeyManager?.register(
            keyCode: settingsViewModel.hotkeyKeyCode,
            modifiers: settingsViewModel.hotkeyModifiers
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover()
            }
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        removeClickMonitors()
        updateUIVisibility()
        viewModel.clearMemoryCache()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        updateUIVisibility()
        viewModel.clearMemoryCache()
    }

    private func updateUIVisibility() {
        let visible = (popover != nil && popover.isShown) || (window != nil && window!.isVisible)
        viewModel.isUIVisible = visible
    }
}

// MARK: - SleekWindow
// NSWindow subclass that centers the traffic light control buttons vertically
// inside the titlebar container area, giving it a balanced, integrated look.
class SleekWindow: NSWindow {
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        centerTrafficLights()
    }

    override func makeKey() {
        super.makeKey()
        centerTrafficLights()
    }

    override func resignKey() {
        super.resignKey()
        centerTrafficLights()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        centerTrafficLights()
    }

    private func centerTrafficLights() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let closeButton = self.standardWindowButton(.closeButton),
               let minimizeButton = self.standardWindowButton(.miniaturizeButton),
               let zoomButton = self.standardWindowButton(.zoomButton),
               let container = closeButton.superview {
                
                let targetY = (container.frame.height - closeButton.frame.height) / 2
                
                closeButton.setFrameOrigin(NSPoint(x: closeButton.frame.origin.x, y: targetY))
                minimizeButton.setFrameOrigin(NSPoint(x: minimizeButton.frame.origin.x, y: targetY))
                zoomButton.setFrameOrigin(NSPoint(x: zoomButton.frame.origin.x, y: targetY))
            }
        }
    }
}
