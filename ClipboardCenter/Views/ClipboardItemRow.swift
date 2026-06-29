import SwiftUI
import AppKit

// MARK: - ClipboardItemRow
// A single row in the clipboard history list.
// Visually distinct for each content type with appropriate icons and previews.
// Supports tap-to-copy, context menu (right-click), and hover effects.

struct ClipboardItemRow: View {
    let item: ClipboardItemEntity
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Content type icon / thumbnail
                contentIcon
                    .frame(width: 36, height: 36)

                // Text preview
                VStack(alignment: .leading, spacing: 2) {
                    // Content type label + pin icon
                    HStack(spacing: 4) {
                        Text(item.contentType.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Text(item.safeTimestamp.relativeFormat)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }

                    // Preview text
                    previewContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered
                          ? Color(nsColor: .controlAccentColor).opacity(0.08)
                          : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if item.contentType == .text || item.contentType == .richText || item.contentType == .url {
                Button(action: onEdit) {
                    Label(L10n.s.edit, systemImage: "pencil")
                }
                Divider()
            }

            Button(action: onPin) {
                Label(
                    item.isPinned ? "Unpin" : "Pin",
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .help("Click to copy to clipboard")
    }

    // MARK: - Content Type Icon

    @ViewBuilder
    private var contentIcon: some View {
        switch item.contentType {
        case .image:
            // Show thumbnail for images
            if let nsImage = item.thumbnailImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            } else {
                iconBadge(icon: "photo", color: .purple)
            }

        case .url:
            iconBadge(icon: "link", color: .blue)

        case .richText:
            iconBadge(icon: "doc.richtext", color: .orange)

        case .tabular:
            iconBadge(icon: "tablecells", color: .green)

        case .text:
            iconBadge(icon: "doc.text", color: .gray)

        case .file:
            if let nsImage = item.thumbnailImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30) // Slightly smaller for file icons so they look nice
                    .frame(width: 36, height: 36) // Keep the box same size
            } else {
                iconBadge(icon: "doc.on.doc", color: .teal)
            }
        }
    }

    /// Colored icon badge for non-image content types
    private func iconBadge(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.12))

            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color.opacity(0.8))
        }
    }

    // MARK: - Preview Content

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .image:
            Text(item.preview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

        case .url:
            Text(item.textContent ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.blue.opacity(0.8))
                .lineLimit(2)
                .truncationMode(.middle)

        case .tabular:
            VStack(alignment: .leading, spacing: 1) {
                Text(item.tableDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(item.preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        case .text, .richText:
            Text(item.multiLinePreview)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(3)
                .truncationMode(.tail)

        case .file:
            Text(item.multiLinePreview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Date Relative Formatting Extension

extension Date {
    /// Formats the date as a relative string (e.g., "2m ago", "1h ago", "Yesterday")
    var relativeFormat: String {
        let interval = -timeIntervalSinceNow

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }
}
