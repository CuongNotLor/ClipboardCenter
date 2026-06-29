import Foundation
import AppKit
import ServiceManagement
import Combine
import Carbon.HIToolbox

// MARK: - SettingsViewModel
// Manages all user-facing settings with persistence via UserDefaults.
// Exposes reactive @Published properties so SwiftUI views update automatically.
//
// Settings categories (matching the design):
// - Appearance: Theme mode, Language
// - Behavior: Show selected item first, Start up with system
// - Interface: Icon mode (Menu bar vs Dock)
// - Keyboard: Global hotkey shortcut

final class SettingsViewModel: ObservableObject {

    // MARK: - Navigation State

    /// Controls whether settings or clipboard is shown. Reset by AppDelegate on popover open.
    @Published var isShowingSettings = false

    // MARK: - Appearance

    enum ThemeMode: String, CaseIterable {
        case device = "Device"
        case dark = "Dark"
        case light = "Light"
    }

    enum Language: String, CaseIterable {
        case english = "English"
        case vietnamese = "Vietnamese"

        /// Detects language from the system's preferred locale.
        static func fromSystemLocale() -> Language {
            let langCode = Locale.preferredLanguages.first?.prefix(2) ?? "en"
            switch langCode {
            case "vi": return .vietnamese
            default: return .english
            }
        }
    }

    @Published var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: Keys.themeMode)
            applyTheme()
        }
    }

    @Published var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    // MARK: - Behavior

    @Published var showSelectedItemFirst: Bool {
        didSet {
            UserDefaults.standard.set(showSelectedItemFirst, forKey: Keys.showSelectedItemFirst)
        }
    }

    @Published var startUpWithSystem: Bool {
        didSet {
            UserDefaults.standard.set(startUpWithSystem, forKey: Keys.startUpWithSystem)
            configureLoginItem()
        }
    }

    // MARK: - Interface

    enum IconMode: String, CaseIterable {
        case menuBar = "Menu bar"
        case dock = "Dock"
    }

    @Published var iconMode: IconMode {
        didSet {
            UserDefaults.standard.set(iconMode.rawValue, forKey: Keys.iconMode)
            onIconModeChanged?(iconMode)
        }
    }

    /// Callback for AppDelegate when icon mode is changed.
    var onIconModeChanged: ((IconMode) -> Void)?

    // MARK: - Blur

    @Published var enableBlur: Bool {
        didSet {
            UserDefaults.standard.set(enableBlur, forKey: Keys.enableBlur)
        }
    }

    // MARK: - Debug

    @Published var showDebugStats: Bool {
        didSet {
            UserDefaults.standard.set(showDebugStats, forKey: Keys.showDebugStats)
        }
    }

    // MARK: - Keyboard

    @Published var keyboardShortcut: String {
        didSet {
            UserDefaults.standard.set(keyboardShortcut, forKey: Keys.keyboardShortcut)
        }
    }

    /// Whether the UI is currently recording a new keyboard shortcut.
    @Published var isRecordingShortcut = false

    /// The stored Carbon key code for the current shortcut.
    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        }
    }

    /// The stored Carbon modifier flags for the current shortcut.
    @Published var hotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        }
    }

    /// Callback for AppDelegate to re-register the hotkey when changed.
    var onHotkeyChanged: ((_ keyCode: UInt32, _ modifiers: UInt32) -> Void)?

    // MARK: - Stats (read-only, computed at display time)

    /// Returns the physical memory footprint of the app (matches Xcode's Memory Report).
    /// Uses `phys_footprint` from task_vm_info, NOT `resident_size` from task_basic_info.
    ///
    /// Why the difference?
    /// - `resident_size`: Counts ALL resident pages including shared frameworks (SwiftUI,
    ///   AppKit, etc.) that are memory-mapped and shared across processes. This inflates
    ///   the number significantly (often 2-3x the real usage).
    /// - `phys_footprint`: Counts only the physical memory actually *charged* to this process.
    ///   This is what Xcode, Activity Monitor's "Memory" column, and Apple's memory
    ///   diagnostics report. It's the accurate measure of the app's memory impact.
    var currentMemoryUsage: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let bytesUsed = info.phys_footprint
            return ByteCountFormatter.string(fromByteCount: Int64(bytesUsed), countStyle: .memory)
        }
        return "—"
    }

    /// Returns the number of active threads in the process.
    var activeThreadCount: Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        if result == KERN_SUCCESS, let threads = threadList {
            // Deallocate the thread list to avoid leaking kernel memory
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threads),
                vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size)
            )
            return Int(threadCount)
        }
        return 0
    }

    /// Returns the total number of clipboard items from CoreData
    var totalItemsClipped: Int {
        let request = ClipboardItemEntity.fetchRequest()
        do {
            return try viewContext?.count(for: request) ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Private

    private weak var viewContext: NSManagedObjectContext?

    private enum Keys {
        static let themeMode = "cc_themeMode"
        static let language = "cc_language"
        static let showSelectedItemFirst = "cc_showSelectedItemFirst"
        static let startUpWithSystem = "cc_startUpWithSystem"
        static let iconMode = "cc_iconMode"
        static let keyboardShortcut = "cc_keyboardShortcut"
        static let enableBlur = "cc_enableBlur"
        static let showDebugStats = "cc_showDebugStats"
        static let hotkeyKeyCode = "cc_hotkeyKeyCode"
        static let hotkeyModifiers = "cc_hotkeyModifiers"
    }

    // MARK: - Initialization

    init(viewContext: NSManagedObjectContext? = nil) {
        self.viewContext = viewContext

        // Load persisted values, falling back to sensible defaults
        let defaults = UserDefaults.standard

        self.themeMode = ThemeMode(
            rawValue: defaults.string(forKey: Keys.themeMode) ?? ""
        ) ?? .dark

        // Auto-detect language from system locale if not previously set
        if let savedLang = defaults.string(forKey: Keys.language),
           let lang = Language(rawValue: savedLang) {
            self.language = lang
        } else {
            self.language = Language.fromSystemLocale()
        }

        self.showSelectedItemFirst = defaults.object(forKey: Keys.showSelectedItemFirst) as? Bool ?? true

        self.startUpWithSystem = defaults.object(forKey: Keys.startUpWithSystem) as? Bool ?? false

        self.iconMode = IconMode(
            rawValue: defaults.string(forKey: Keys.iconMode) ?? ""
        ) ?? .menuBar

        self.keyboardShortcut = defaults.string(forKey: Keys.keyboardShortcut) ?? "⌘ + Shift + V"

        self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode) != 0
            ? defaults.integer(forKey: Keys.hotkeyKeyCode)
            : Int(kVK_ANSI_V))
        self.hotkeyModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers) != 0
            ? defaults.integer(forKey: Keys.hotkeyModifiers)
            : Int(cmdKey | shiftKey))

        self.enableBlur = defaults.object(forKey: Keys.enableBlur) as? Bool ?? true

        self.showDebugStats = defaults.object(forKey: Keys.showDebugStats) as? Bool ?? false

        // Apply the persisted theme on launch
        applyTheme()
    }

    // MARK: - Theme Application

    /// Sets the NSApp appearance based on the selected theme mode.
    func applyTheme() {
        DispatchQueue.main.async {
            switch self.themeMode {
            case .device:
                NSApp.appearance = nil // Follow system
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            }
        }
    }

    // MARK: - Login Item

    /// Configures the app to start at login using SMAppService (macOS 13+).
    private func configureLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if startUpWithSystem {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to configure login item: \(error)")
            }
        }
    }

    // MARK: - Refresh Stats

    /// Forces a stats refresh for the memory and item count cards.
    func refreshStats() {
        objectWillChange.send()
    }

    // MARK: - Keyboard Shortcut Recording

    /// Applies a new keyboard shortcut from the recorded key event.
    func applyNewShortcut(keyCode: UInt32, modifiers: UInt32) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        keyboardShortcut = Self.displayString(keyCode: keyCode, modifiers: modifiers)
        isRecordingShortcut = false
        onHotkeyChanged?(keyCode, modifiers)
    }

    /// Cancels shortcut recording without changes.
    func cancelRecording() {
        isRecordingShortcut = false
    }

    /// Converts Carbon key code and modifier flags to a human-readable string like "⌘ + Shift + V".
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        case kVK_ANSI_0: keyName = "0"
        case kVK_ANSI_1: keyName = "1"
        case kVK_ANSI_2: keyName = "2"
        case kVK_ANSI_3: keyName = "3"
        case kVK_ANSI_4: keyName = "4"
        case kVK_ANSI_5: keyName = "5"
        case kVK_ANSI_6: keyName = "6"
        case kVK_ANSI_7: keyName = "7"
        case kVK_ANSI_8: keyName = "8"
        case kVK_ANSI_9: keyName = "9"
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "Return"
        case kVK_Tab: keyName = "Tab"
        case kVK_Delete: keyName = "Delete"
        case kVK_ForwardDelete: keyName = "Fwd Del"
        case kVK_LeftArrow: keyName = "←"
        case kVK_RightArrow: keyName = "→"
        case kVK_UpArrow: keyName = "↑"
        case kVK_DownArrow: keyName = "↓"
        case kVK_F1: keyName = "F1"
        case kVK_F2: keyName = "F2"
        case kVK_F3: keyName = "F3"
        case kVK_F4: keyName = "F4"
        case kVK_F5: keyName = "F5"
        case kVK_F6: keyName = "F6"
        case kVK_F7: keyName = "F7"
        case kVK_F8: keyName = "F8"
        case kVK_F9: keyName = "F9"
        case kVK_F10: keyName = "F10"
        case kVK_F11: keyName = "F11"
        case kVK_F12: keyName = "F12"
        default: keyName = "Key(\(keyCode))"
        }

        parts.append(keyName)
        return parts.joined(separator: " + ")
    }
}
