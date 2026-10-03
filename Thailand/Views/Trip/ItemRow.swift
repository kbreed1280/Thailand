import SwiftUI

struct ItemRow: View {
    @ObservedObject var item: Item

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: item.category)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let time = item.time {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.mango)
                    }
                    Text(item.displayTitle)
                        .font(.body.weight(.semibold))
                        .strikethrough(item.status == .done, color: .secondary)
                        .foregroundStyle(item.status == .done ? .secondary : .primary)
                        .lineLimit(2)
                }

                if let address = item.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if item.status != .wantToGo {
                        StatPill(
                            systemImage: item.status.systemImage,
                            text: item.status.title,
                            tint: item.status == .done ? .green : Theme.lagoon
                        )
                    }
                    if item.costTHB > 0 {
                        StatPill(systemImage: "bahtsign", text: item.costTHB.formatted(.number.precision(.fractionLength(0))))
                    }
                    if let count = item.photos?.count, count > 0 {
                        StatPill(systemImage: "photo", text: "\(count)")
                    }
                    if let addedBy = item.addedBy, !addedBy.isEmpty, addedBy != AppSettings.displayName {
                        Text("by \(addedBy)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag to move. Swipe for done or delete.")
    }
}
