import Foundation
import AppKit
import CoreData
import CryptoKit
import Darwin

// MARK: - ClipboardCenterViewModel
// The central brain of the app. Handles:
// 1. Clipboard monitoring via changeCount polling (not blind polling — only processes on change)
// 2. Content type detection and item creation
// 3. Duplicate prevention via content hashing
// 4. Auto-pruning to maintain the 100-item unpinned limit
// 5. User actions: pin, delete, clearAll, copy-to-clipboard
//
// Uses ObservableObject + @Published for macOS 13 compatibility
// (the Observation framework's @Observable requires macOS 14+).

final class ClipboardCenterViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var items: [ClipboardItemEntity] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: ContentFilter = .all
    @Published var showWarningAlert: Bool = false
    var isUIVisible: Bool = false

    enum ContentFilter: String, CaseIterable {
        case all = "All"
        case text = "Text"
        case image = "Image"
        case file = "File"
    }

    /// Filtered items based on search text and selected filter
    var filteredItems: [ClipboardItemEntity] {
        var result = items

        switch selectedFilter {
        case .all:
            break
        case .text:
            result = result.filter { $0.contentType == .text || $0.contentType == .richText || $0.contentType == .url || $0.contentType == .tabular }
        case .image:
            result = result.filter { $0.contentType == .image }
        case .file:
            result = result.filter { $0.contentType == .file }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.matchesSearch(searchText) }
        }

        return result
    }

    /// Pinned items (always shown at top)
    var pinnedItems: [ClipboardItemEntity] {
        filteredItems.filter { $0.isPinned }
    }

    /// Unpinned items (history section)
    var unpinnedItems: [ClipboardItemEntity] {
        filteredItems.filter { !$0.isPinned }
    }

    // MARK: - Private Properties

    private var viewContext: NSManagedObjectContext
    private var monitorTimer: Timer?

    /// The last observed pasteboard change count.
    /// We ONLY process new clipboard content when this value changes,
    /// which is the key performance optimization — no wasted CPU cycles
    /// when the user isn't copying anything.
    private var lastChangeCount: Int = 0

    /// Maximum number of unpinned items to retain in storage.
    private let maxUnpinnedItems = 100

    /// Reference to the settings view model for behavior settings.
    private weak var settingsViewModel: SettingsViewModel?

    // MARK: - Initialization

    init(viewContext: NSManagedObjectContext, settingsViewModel: SettingsViewModel? = nil) {
        self.viewContext = viewContext
        self.settingsViewModel = settingsViewModel
        // Capture the current changeCount so we don't re-process
        // whatever is already on the clipboard at launch.
        self.lastChangeCount = NSPasteboard.general.changeCount
        refreshItems()
    }

    // MARK: - Clipboard Monitoring
    // PERFORMANCE: We use a 0.5-second timer that ONLY checks NSPasteboard.changeCount.
    // This is an integer comparison — essentially zero CPU cost.
    // We only do the expensive work (reading pasteboard data, hashing, CoreData insert)
    // when the changeCount actually increments, which happens only when the user copies.

    func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.autoPruneMemoryIfNeeded()
            self?.checkForNewClipboardContent()
        }
        // Allow the timer to fire even when the menu is tracking
        RunLoop.current.add(monitorTimer!, forMode: .common)
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Lightweight check — exits immediately if nothing has changed.
    private func checkForNewClipboardContent() {
        let currentChangeCount = NSPasteboard.general.changeCount

        // FAST PATH: No change → return immediately (costs ~0 CPU)
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        // SLOW PATH: Something was copied → process it
        autoreleasepool {
            processClipboardContent()
        }
    }

    // MARK: - Content Processing

    /// Reads the current pasteboard content, detects its type, creates a ClipboardItemEntity,
    /// and persists it. Skips duplicates and enforces the unpinned item limit.
    private func processClipboardContent() {
        let pasteboard = NSPasteboard.general

        // Detection priority: Files → Image → URL → RTF → Tabular → Plain Text
        // Files come FIRST so Finder file copies are stored as files (not as image icons).
        // Direct image data (screenshots, copy-from-app) still gets captured as images.

        if processFiles(from: pasteboard) { return }
        if processImage(from: pasteboard) { return }
        if processURL(from: pasteboard) { return }
        if processRichText(from: pasteboard) { return }
        if processTabularData(from: pasteboard) { return }
        if processPlainText(from: pasteboard) { return }
    }

    // MARK: - Content Extraction (returns true if item was created)

    /// Detects file URLs from Finder copy operations.
    /// When you Cmd+C files in Finder, macOS puts file URLs on the pasteboard.
    /// We store the file paths and can restore them for Finder paste.
    private func processFiles(from pasteboard: NSPasteboard) -> Bool {
        // Only proceed if the pasteboard has file URLs
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }

        // Filter to only existing files/directories on disk
        let validPaths = urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.path }

        guard !validPaths.isEmpty else { return false }

        // Hash based on sorted paths for consistent duplicate detection
        let pathsString = validPaths.sorted().joined(separator: "\n")
        let hash = computeHash(Data(pathsString.utf8))
        if isDuplicate(hash: hash) { return true }

        // Store file names in textContent for search/preview fallback
        let fileNames = validPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")

        // Generate an icon/thumbnail for the first file
        var thumbnailData: Data? = nil
        if let firstPath = validPaths.first {
            let url = URL(fileURLWithPath: firstPath)
            let ext = url.pathExtension.lowercased()
            let imageExtensions: Set<String> = [
                "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif",
                "heic", "heif", "webp", "svg"
            ]

            if imageExtensions.contains(ext), let image = NSImage(contentsOf: url) {
                // If it's an image file, generate a real thumbnail
                thumbnailData = ImageUtils.generateThumbnail(from: image, maxSize: 60)
            } else {
                // Otherwise use the system icon for this file type (shows music icon for audio, doc for docs, etc.)
                let icon = NSWorkspace.shared.icon(forFile: firstPath)
                thumbnailData = ImageUtils.generateThumbnail(from: icon, maxSize: 60)
            }
        }

        let _ = ClipboardItemEntity.create(
            in: viewContext,
            contentType: .file,
            textContent: fileNames,
            thumbnailData: thumbnailData,
            filePaths: validPaths,
            contentHash: hash
        )

        finalizeSave()
        return true
    }

    private func processImage(from pasteboard: NSPasteboard) -> Bool {
        // NOTE: File URL detection is now handled by processFiles() which runs first.
        // This method only handles direct image data (screenshots, copy-image-from-app).

        // PRIORITY 1: Direct image data from screenshots, copy-image-from-app, etc.
        // Uses readObjects which handles ALL image formats macOS supports.
        // Filter out tiny images (< 16px) to skip file icons/badges.
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           image.size.width >= 16, image.size.height >= 16 {
            return saveImageItem(image)
        }

        // PRIORITY 2: Fallback — try reading raw image data from known pasteboard types
        let rawImageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.webp")
        ]
        if let imageType = pasteboard.availableType(from: rawImageTypes),
           let rawData = pasteboard.data(forType: imageType),
           let fallbackImage = NSImage(data: rawData) {
            return saveImageItem(fallbackImage)
        }

        return false
    }

    /// Saves an NSImage as a clipboard history item with PNG storage and thumbnail.
    private func saveImageItem(_ image: NSImage) -> Bool {
        // Convert to PNG for consistent storage
        guard let pngData = image.pngData() else { return false }

        let hash = computeHash(pngData)
        if isDuplicate(hash: hash) { return true }

        // Generate a 60×60 pt thumbnail for memory-efficient list rendering
        let thumbnailData = ImageUtils.generateThumbnail(from: image, maxSize: 60)
        let dimensions = "\(Int(image.size.width)) × \(Int(image.size.height))"

        let _ = ClipboardItemEntity.create(
            in: viewContext,
            contentType: .image,
            textContent: dimensions,
            imageData: pngData,
            thumbnailData: thumbnailData,
            contentHash: hash
        )

        finalizeSave()
        return true
    }

    private func processURL(from pasteboard: NSPasteboard) -> Bool {
        // Check for explicit URL type first
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString) {
            let hash = computeHash(Data(url.absoluteString.utf8))
            if isDuplicate(hash: hash) { return true }

            let _ = ClipboardItemEntity.create(
                in: viewContext,
                contentType: .url,
                textContent: url.absoluteString,
                contentHash: hash
            )
            finalizeSave()
            return true
        }

        // Also check if plain text looks like a URL
        if let text = pasteboard.string(forType: .string),
           let url = URL(string: text),
           url.scheme != nil,
           ["http", "https", "ftp", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            let hash = computeHash(Data(text.utf8))
            if isDuplicate(hash: hash) { return true }

            let _ = ClipboardItemEntity.create(
                in: viewContext,
                contentType: .url,
                textContent: url.absoluteString,
                contentHash: hash
            )
            finalizeSave()
            return true
        }

        return false
    }

    private func processRichText(from pasteboard: NSPasteboard) -> Bool {
        guard let rtfData = pasteboard.data(forType: .rtf) else { return false }

        // Extract plain text representation for search and preview
        let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil)
        let plainText = attributedString?.string

        let hash = computeHash(rtfData)
        if isDuplicate(hash: hash) { return true }

        let _ = ClipboardItemEntity.create(
            in: viewContext,
            contentType: .richText,
            textContent: plainText,
            rtfData: rtfData,
            contentHash: hash
        )
        finalizeSave()
        return true
    }

    private func processTabularData(from pasteboard: NSPasteboard) -> Bool {
        guard let text = pasteboard.string(forType: .string) else { return false }

        // Detect tabular data: must have multiple lines with consistent
        // tab or comma separators (at least 2 rows, 2 columns)
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }

        let isTabSeparated = lines.allSatisfy { $0.contains("\t") }
        let isCommaSeparated = !isTabSeparated && lines.allSatisfy { $0.contains(",") }

        guard isTabSeparated || isCommaSeparated else { return false }

        let separator: Character = isTabSeparated ? "\t" : ","
        let columnCounts = lines.map { $0.split(separator: separator).count }

        // Require at least 2 columns and consistent column count across rows
        guard let firstCount = columnCounts.first,
              firstCount >= 2,
              columnCounts.allSatisfy({ $0 == firstCount }) else {
            return false
        }

        let hash = computeHash(Data(text.utf8))
        if isDuplicate(hash: hash) { return true }

        let _ = ClipboardItemEntity.create(
            in: viewContext,
            contentType: .tabular,
            textContent: text,
            contentHash: hash
        )
        finalizeSave()
        return true
    }

    private func processPlainText(from pasteboard: NSPasteboard) -> Bool {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let hash = computeHash(Data(text.utf8))
        if isDuplicate(hash: hash) { return true }

        let _ = ClipboardItemEntity.create(
            in: viewContext,
            contentType: .text,
            textContent: text,
            contentHash: hash
        )
        finalizeSave()
        return true
    }

    // MARK: - Duplicate Detection

    /// Computes a SHA256 hash of the data for fast duplicate comparison.
    private func computeHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Checks if the most recent item has the same content hash.
    /// This prevents storing the same content twice in a row.
    private func isDuplicate(hash: String) -> Bool {
        return items.first?.safeContentHash == hash
    }

    // MARK: - Persistence

    /// Prunes old items and saves context after inserting a new item.
    private func finalizeSave() {
        pruneOldItems()
        saveContext()
        refreshItems()
    }

    /// Enforces the 100-item limit on unpinned items.
    /// Only the oldest unpinned items are pruned — pinned items are never touched.
    private func pruneOldItems() {
        let request: NSFetchRequest<ClipboardItemEntity> = ClipboardItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isPinned == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let unpinnedItems = try viewContext.fetch(request)
            if unpinnedItems.count > maxUnpinnedItems {
                showWarningAlert = true
                let itemsToDelete = unpinnedItems.suffix(from: maxUnpinnedItems)
                for item in itemsToDelete {
                    viewContext.delete(item)
                }
            }
        } catch {
            print("Error pruning old items: \(error)")
        }
    }

    // MARK: - Data Refresh

    /// Fetches all items from CoreData, sorted by timestamp (newest first).
    func refreshItems() {
        let request: NSFetchRequest<ClipboardItemEntity> = ClipboardItemEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            items = try viewContext.fetch(request)
        } catch {
            print("Error fetching items: \(error)")
            items = []
        }
    }

    // MARK: - User Actions

    /// Toggles the pinned state of an item.
    func togglePin(_ item: ClipboardItemEntity) {
        item.isPinned.toggle()
        saveContext()
        refreshItems()
    }

    /// Permanently deletes an item from history.
    func delete(_ item: ClipboardItemEntity) {
        viewContext.delete(item)
        saveContext()
        refreshItems()
    }

    /// Deletes all unpinned items. Pinned items are preserved.
    func clearAll() {
        let request: NSFetchRequest<ClipboardItemEntity> = ClipboardItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isPinned == NO")

        do {
            let unpinnedItems = try viewContext.fetch(request)
            for item in unpinnedItems {
                viewContext.delete(item)
            }
            saveContext()
            
            // 1. Update the published array immediately so SwiftUI removes the views
            refreshItems()
            
            // 2. Safely defer the aggressive context reset. This prevents SwiftUI from reading
            // `nil` IDs from forcefully-faulted deleted objects during its active render pass,
            // which causes the layout system to leak memory.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.clearMemoryCache()
            }
        } catch {
            print("Error clearing items: \(error)")
        }
    }

    /// Copies the given item's content back to the system clipboard.
    /// Restores the original data type so paste operations work correctly.
    /// Also updates the item's timestamp so it moves to the top of the list.
    func copyToClipboard(_ item: ClipboardItemEntity) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .richText:
            // Restore both RTF and plain text for maximum compatibility
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .image:
            if let imageData = item.imageData {
                // Use writeObjects with NSImage for broadest app compatibility.
                // This lets the pasteboard negotiate the best format with the receiving app.
                if let image = NSImage(data: imageData) {
                    pasteboard.writeObjects([image])
                } else {
                    // Fallback: write raw PNG + TIFF data
                    pasteboard.setData(imageData, forType: .png)
                }
            }

        case .url:
            if let urlString = item.textContent {
                pasteboard.setString(urlString, forType: .string)
                if let url = URL(string: urlString) {
                    pasteboard.setString(url.absoluteString, forType: .URL)
                }
            }

        case .tabular:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .file:
            // Restore file URLs to the pasteboard so Finder can paste them.
            // writeObjects with NSURL tells Finder "these are files to copy/move".
            let urls = item.fileURLs.map { $0 as NSURL }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
            }
        }

        // Move item to top of the list by updating its timestamp
        // (only when "Show selected item first" is enabled)
        if settingsViewModel?.showSelectedItemFirst ?? true {
            item.timestamp = Date()
        }
        saveContext()

        // Evict raw image data from memory to keep RAM footprint low
        if item.contentType == .image {
            viewContext.refresh(item, mergeChanges: false)
        }

        refreshItems()

        // Update our changeCount so we don't re-capture what we just pasted
        lastChangeCount = pasteboard.changeCount
    }

    /// Updates the text content of a clipboard item, converting it to plain text if it was rich text.
    func updateText(_ item: ClipboardItemEntity, newText: String) {
        item.textContent = newText
        item.clearCachedValues()

        if item.contentType == .richText {
            item.contentType = .text
            item.rtfData = nil
        }

        item.contentHash = computeHash(Data(newText.utf8))
        saveContext()
        refreshItems()
    }


    // MARK: - Context Save

    private func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    /// Aggressively purges memory caches by flushing the Core Data view context and transient image caches.
    func clearMemoryCache() {
        // Drop any in-flight rendering caches from CoreData
        viewContext.reset()
        refreshItems()
        ClipboardItemEntity.clearThumbnailCache()
    }

    // MARK: - Memory Monitoring

    private var lastResetTime: Date = Date.distantPast

    private func getMemoryUsage() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return nil
        }
    }

    private func autoPruneMemoryIfNeeded() {
        // Limit resets to once every 5 seconds to prevent thrashing
        guard Date().timeIntervalSince(lastResetTime) > 5.0 else { return }
        
        let threshold: UInt64 = isUIVisible ? 120 * 1024 * 1024 : 50 * 1024 * 1024
        
        if let bytes = getMemoryUsage(), bytes > threshold {
            lastResetTime = Date()
            clearMemoryCache()
        }
    }
}

// MARK: - NSImage PNG Extension

extension NSImage {
    /// Converts NSImage to PNG data for consistent storage format.
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
