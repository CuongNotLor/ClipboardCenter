import Foundation
import CoreData
import AppKit

// MARK: - Clipboard Content Type
// Categorizes the type of data stored in a clipboard item.
// Stored as a raw String for CoreData compatibility.

enum ClipboardContentType: String, Codable, CaseIterable {
    case text       = "text"
    case richText   = "richText"
    case image      = "image"
    case url        = "url"
    case tabular    = "tabular"
    case file       = "file"

    /// Human-readable label for UI display
    var displayName: String {
        switch self {
        case .text:     return "Text"
        case .richText: return "Rich Text"
        case .image:    return "Image"
        case .url:      return "Link"
        case .tabular:  return "Table"
        case .file:     return "File"
        }
    }

    /// SF Symbol icon name for each content type
    var iconName: String {
        switch self {
        case .text:     return "doc.text"
        case .richText: return "doc.richtext"
        case .image:    return "photo"
        case .url:      return "link"
        case .tabular:  return "tablecells"
        case .file:     return "doc.on.doc"
        }
    }
}

// MARK: - ClipboardItemEntity (CoreData NSManagedObject)
// CoreData persistent model for clipboard history entries.
// Images are stored as Data (PNG) with external binary storage enabled,
// plus a separate thumbnail for list display to minimize memory usage.
// Files store their paths as JSON so they can be restored to the pasteboard
// for Finder paste operations.

@objc(ClipboardItemEntity)
public class ClipboardItemEntity: NSManagedObject {

    // MARK: - CoreData Managed Properties

    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var isPinned: Bool
    @NSManaged public var contentTypeRaw: String?
    @NSManaged public var textContent: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var rtfData: Data?
    @NSManaged public var contentHash: String?

    /// JSON-encoded array of file path strings.
    /// Used for the .file content type to store Finder-copied file paths.
    @NSManaged public var fileURLsJSON: String?

    // MARK: - Transient Caches
    private var _cachedPreview: String?
    private var _cachedMultiLinePreview: String?
    private var _cachedTableDescription: String?

    public func clearCachedValues() {
        _cachedPreview = nil
        _cachedMultiLinePreview = nil
        _cachedTableDescription = nil
    }

    public override func didTurnIntoFault() {
        super.didTurnIntoFault()
        clearCachedValues()
    }

    // MARK: - Computed Properties

    /// Type-safe accessor for the content type enum
    var contentType: ClipboardContentType {
        get { ClipboardContentType(rawValue: contentTypeRaw ?? "text") ?? .text }
        set { contentTypeRaw = newValue.rawValue }
    }

    /// Unwrapped timestamp with fallback
    var safeTimestamp: Date {
        timestamp ?? Date.distantPast
    }

    /// Unwrapped content hash with fallback
    var safeContentHash: String {
        contentHash ?? ""
    }

    private static let thumbnailCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 200 // Keep up to 200 thumbnails in RAM
        return cache
    }()
    
    public static func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    var thumbnailImage: NSImage? {
        guard let data = thumbnailData, let urlID = objectID.uriRepresentation() as NSURL? else { return nil }
        
        if let cached = Self.thumbnailCache.object(forKey: urlID) {
            return cached
        }
        
        if let image = NSImage(data: data) {
            Self.thumbnailCache.setObject(image, forKey: urlID)
            return image
        }
        return nil
    }

    /// Decodes the stored file paths from JSON
    var filePaths: [String] {
        get {
            guard let json = fileURLsJSON,
                  let data = json.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return paths
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                fileURLsJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    /// File URLs reconstructed from stored paths
    var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }

    /// Cached table description (e.g. "3 rows × 4 columns")
    var tableDescription: String {
        if let cached = _cachedTableDescription {
            return cached
        }
        guard let text = textContent else { return "Table" }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let separator: Character = text.contains("\t") ? "\t" : ","
        let cols = lines.first?.split(separator: separator).count ?? 0
        let result = "\(lines.count) rows × \(cols) columns"
        _cachedTableDescription = result
        return result
    }

    /// Returns a truncated preview string suitable for the UI list.
    var preview: String {
        if let cached = _cachedPreview {
            return cached
        }
        let result: String
        switch contentType {
        case .text, .richText, .tabular:
            guard let text = textContent, !text.isEmpty else {
                result = "(empty)"
                break
            }
            let cleaned = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if cleaned.count > 200 {
                result = String(cleaned.prefix(200)) + "…"
            } else {
                result = cleaned
            }

        case .image:
            if let dimensions = textContent {
                result = "Image (\(dimensions))"
            } else {
                result = "Image"
            }

        case .url:
            result = textContent ?? "(empty URL)"

        case .file:
            let paths = filePaths
            if paths.count == 1 {
                result = (paths.first! as NSString).lastPathComponent
            } else if paths.count > 1 {
                let firstName = (paths.first! as NSString).lastPathComponent
                result = "\(firstName) and \(paths.count - 1) more"
            } else {
                result = "(no files)"
            }
        }
        _cachedPreview = result
        return result
    }

    /// Returns a multi-line preview for expanded row display
    var multiLinePreview: String {
        if let cached = _cachedMultiLinePreview {
            return cached
        }
        let result: String
        switch contentType {
        case .file:
            let paths = filePaths
            let names = paths.prefix(4).map { ($0 as NSString).lastPathComponent }
            var text = names.joined(separator: "\n")
            if paths.count > 4 {
                text += "\n… and \(paths.count - 4) more"
            }
            result = text

        default:
            guard let text = textContent, !text.isEmpty else {
                result = "(empty)"
                break
            }
            let lines = text.components(separatedBy: .newlines)
            let truncated = lines.prefix(4).joined(separator: "\n")
            if lines.count > 4 {
                result = truncated + "\n…"
            } else {
                result = truncated
            }
        }
        _cachedMultiLinePreview = result
        return result
    }

    // MARK: - Factory

    /// Creates a new ClipboardItemEntity with the given properties in the specified context.
    static func create(
        in context: NSManagedObjectContext,
        contentType: ClipboardContentType,
        textContent: String? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        rtfData: Data? = nil,
        filePaths: [String]? = nil,
        contentHash: String
    ) -> ClipboardItemEntity {
        let item = ClipboardItemEntity(context: context)
        item.id = UUID()
        item.timestamp = Date()
        item.isPinned = false
        item.contentTypeRaw = contentType.rawValue
        item.textContent = textContent
        item.imageData = imageData
        item.thumbnailData = thumbnailData
        item.rtfData = rtfData
        item.contentHash = contentHash
        if let paths = filePaths {
            item.filePaths = paths
        }
        return item
    }

    // MARK: - Search

    /// Returns true if the item matches the given search query.
    func matchesSearch(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let lowered = query.lowercased()

        // Match by content type name
        if contentType.displayName.lowercased().contains(lowered) {
            return true
        }

        // Match by text content
        if let text = textContent {
            if text.lowercased().contains(lowered) { return true }
        }

        // Match by file names
        if contentType == .file {
            for path in filePaths {
                let name = (path as NSString).lastPathComponent
                if name.lowercased().contains(lowered) { return true }
            }
        }

        return false
    }
}

// MARK: - Fetch Request Helpers

extension ClipboardItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClipboardItemEntity> {
        return NSFetchRequest<ClipboardItemEntity>(entityName: "ClipboardItemEntity")
    }
}
