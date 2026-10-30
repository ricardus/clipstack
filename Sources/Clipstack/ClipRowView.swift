import AppKit
import SwiftUI

@MainActor
struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    /// Faint accent wash marking membership of the pinned section.
    let tinted: Bool
    let store: ClipStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    if let appName = item.appName {
                        Text(appName)
                    }
                    Text(Self.relativeFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isSelected { return Theme.accent.opacity(0.22) }
        if tinted { return Theme.accent.opacity(0.07) }
        return .clear
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                symbolIcon
            }
        case .color:
            if let hex = item.text, let color = NSColor(hexString: hex) {
                Rectangle().fill(Color(nsColor: color))
            } else {
                symbolIcon
            }
        default:
            symbolIcon
        }
    }

    private var symbolIcon: some View {
        Image(systemName: item.kind.symbol)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
    }
}
