import SwiftUI
import CoreData

/// Gives any screen the trip currently selected on the Trip tab (nil if there are no trips).
struct CurrentTripReader<Content: View>: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)])
    private var trips: FetchedResults<Trip>
    @AppStorage(AppSettings.selectedTripKey) private var selectedTripID = ""

    @ViewBuilder let content: (Trip?) -> Content

    var body: some View {
        content(trips.first { $0.uuid?.uuidString == selectedTripID } ?? trips.first)
    }
}

/// Small "Offline" capsule shown wherever live data is unavailable.
struct OfflineBadge: View {
    var text = "Offline"

    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.gray, in: Capsule())
            .accessibilityLabel("No internet connection. \(text)")
    }
}
