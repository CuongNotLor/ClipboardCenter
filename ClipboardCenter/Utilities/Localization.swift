import Foundation

// MARK: - Localization
// A lightweight, code-based localization system for Clipboard Center.
// All user-facing strings are centralized here, keyed by the selected Language.
// This avoids the complexity of .strings/.stringsdict files while still
// providing a clean API for the views.
//
// Usage: L10n.s.settingTitle  →  "Setting" or "Cài đặt"

struct L10n {

    /// Creates a localization instance for the given language.
    /// Use inside views as: `let l = L10n(viewModel.language)` so SwiftUI
    /// re-renders when the @Published language property changes.
    let language: SettingsViewModel.Language

    init(_ language: SettingsViewModel.Language) {
        self.language = language
    }

    /// Convenience for contexts without a direct viewModel reference.
    /// Falls back to UserDefaults (non-reactive, use sparingly).
    static var s: L10n {
        let raw = UserDefaults.standard.string(forKey: "cc_language") ?? "English"
        let lang = SettingsViewModel.Language(rawValue: raw) ?? .english
        return L10n(lang)
    }

    // MARK: - Common

    var appName: String {
        "Clipboard Center"
    }

    var done: String {
        language == .vietnamese ? "Xong" : "Done"
    }

    var cancel: String {
        language == .vietnamese ? "Hủy" : "Cancel"
    }

    // MARK: - Content View (Main Screen)

    var clipboardCenter: String {
        "Clipboard Center"
    }

    var clear: String {
        language == .vietnamese ? "Xóa" : "Clear"
    }

    var clearAllUnpinnedItems: String {
        language == .vietnamese ? "Xóa tất cả mục chưa ghim" : "Clear all unpinned items"
    }

    var clearClipboardHistory: String {
        language == .vietnamese ? "Xóa lịch sử clipboard" : "Clear Clipboard History"
    }

    var clearAll: String {
        language == .vietnamese ? "Xóa tất cả" : "Clear All"
    }

    var clearAllMessage: String {
        language == .vietnamese
            ? "Thao tác này sẽ xóa vĩnh viễn tất cả các mục chưa ghim. Các mục đã ghim sẽ được giữ lại."
            : "This will permanently delete all unpinned items. Pinned items will be preserved."
    }

    var searchPlaceholder: String {
        language == .vietnamese ? "Tìm kiếm" : "Search clipboard history…"
    }

    var filterAll: String {
        language == .vietnamese ? "Tất cả" : "All"
    }

    var filterText: String {
        language == .vietnamese ? "Văn bản" : "Text"
    }

    var filterImage: String {
        language == .vietnamese ? "Hình ảnh" : "Image"
    }

    var filterFile: String {
        language == .vietnamese ? "Tập tin" : "File"
    }

    var pinned: String {
        language == .vietnamese ? "Đã ghim" : "Pinned"
    }

    var history: String {
        language == .vietnamese ? "Lịch sử" : "History"
    }

    var noClipboardHistory: String {
        language == .vietnamese ? "Chưa có lịch sử clipboard" : "No clipboard history"
    }

    var noResultsFound: String {
        language == .vietnamese ? "Không tìm thấy kết quả" : "No results found"
    }

    var copiedItemsWillAppear: String {
        language == .vietnamese ? "Các mục đã sao chép sẽ hiện ở đây" : "Copied items will appear here"
    }

    var tryDifferentSearch: String {
        language == .vietnamese ? "Thử từ khóa khác" : "Try a different search term"
    }

    // MARK: - Settings View

    var settingTitle: String {
        language == .vietnamese ? "Cài đặt" : "Setting"
    }

    var backToClipboard: String {
        language == .vietnamese ? "Quay lại clipboard" : "Back to clipboard"
    }

    var aboutApp: String {
        language == .vietnamese ? "Giới thiệu Clipboard Center" : "About Clipboard Center"
    }

    var quitApp: String {
        language == .vietnamese ? "Thoát Clipboard Center" : "Quit Clipboard Center"
    }

    var exit: String {
        language == .vietnamese ? "Thoát" : "Exit"
    }

    var edit: String {
        language == .vietnamese ? "Sửa" : "Edit"
    }

    var editTextTitle: String {
        language == .vietnamese ? "Chỉnh sửa văn bản" : "Edit Text"
    }

    var save: String {
        language == .vietnamese ? "Lưu" : "Save"
    }

    var authors: String {
        language == .vietnamese ? "Kotarou, cùng với Antigravity" : "Kotarou, with Antigravity"
    }

    // MARK: - Appearance

    var appearance: String {
        language == .vietnamese ? "GIAO DIỆN" : "APPEARANCE"
    }

    var themes: String {
        language == .vietnamese ? "Chủ đề" : "Themes"
    }

    var themeDevice: String {
        language == .vietnamese ? "Hệ thống" : "Device"
    }

    var themeDark: String {
        language == .vietnamese ? "Tối" : "Dark"
    }

    var themeLight: String {
        language == .vietnamese ? "Sáng" : "Light"
    }

    var languageLabel: String {
        language == .vietnamese ? "Ngôn ngữ" : "Language"
    }

    var blur: String {
        language == .vietnamese ? "Làm mờ" : "Blur"
    }

    // MARK: - Behavior

    var behavior: String {
        language == .vietnamese ? "HÀNH VI" : "BEHAVIOR"
    }

    var showSelectedItemFirst: String {
        language == .vietnamese ? "Hiện mục đã chọn lên đầu" : "Show selected item first"
    }

    var startUpWithSystem: String {
        language == .vietnamese ? "Khởi động cùng hệ thống" : "Start up with system"
    }

    // MARK: - Interface

    var interfaceLabel: String {
        language == .vietnamese ? "GIAO DIỆN HIỂN THỊ" : "INTERFACE"
    }

    var iconMode: String {
        language == .vietnamese ? "Chế độ biểu tượng" : "Icon mode"
    }

    var menuBar: String {
        language == .vietnamese ? "Thanh menu" : "Menu bar"
    }

    var dock: String {
        "Dock"
    }

    // MARK: - Keyboard

    var keyboard: String {
        language == .vietnamese ? "BÀN PHÍM" : "KEYBOARD"
    }

    var keyboardShortcut: String {
        language == .vietnamese ? "Phím tắt" : "Keyboard Shortcut"
    }

    var change: String {
        language == .vietnamese ? "Đổi" : "Change"
    }

    var pressShortcut: String {
        language == .vietnamese ? "Nhấn phím tắt…" : "Press shortcut…"
    }

    // MARK: - Debug

    var debug: String {
        "DEBUG"
    }

    var memoryFootprint: String {
        language == .vietnamese ? "Bộ nhớ (footprint)" : "Memory (footprint)"
    }

    var totalItemsClipped: String {
        language == .vietnamese ? "Tổng mục đã sao chép" : "Total items clipped"
    }

    var activeThreads: String {
        language == .vietnamese ? "Luồng hoạt động" : "Active threads"
    }

    var optimized: String {
        language == .vietnamese ? "ĐÃ TỐI ƯU" : "OPTIMIZED"
    }

    // MARK: - Settings (help text)

    var settings: String {
        language == .vietnamese ? "Cài đặt" : "Settings"
    }
}
